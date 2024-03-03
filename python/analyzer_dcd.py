'''DCD analyzer for IWM/SWIM analyzer PIC firmware.

Protocol should be set to GCR (protocol select pin should be pulled low), GPi should be connected to CA0.

Requires PySerial.
'''

from collections import deque
import sys
import time

import serial


class _MacToDcdDecoder:
  
  def __init__(self):
    self.reset()
  
  def reset(self):
    self._accept_data = True
    self._sync = False
    self._first_sync = True
    self._out_groups = None
    self._in_groups = None
    self._data = None
    self._lsb_byte = None
    self._data_idx = None
  
  def feed_byte(self, byte):
    if not self._accept_data: return False, False, False
    if not self._sync:
      if byte == 0xAA: self._sync = True
      if self._first_sync:
        self._first_sync = False
        return True, False, True
      else:
        return False, False, True
    elif not self._out_groups:
      self._out_groups = byte & 0x7F
      self._data = bytearray(self._out_groups * 7)
      self._data_idx = 0
    elif not self._in_groups:
      self._in_groups = byte & 0x7F
    elif self._lsb_byte is None:
      self._lsb_byte = byte | 0x80
    else:
      lsb = self._lsb_byte & 0x01
      self._lsb_byte >>= 1
      if self._lsb_byte == 0x01:
        self._lsb_byte = None
        if byte & 0x80 == 0x00: self._sync = False  # if we're in a holdoff situation, make sure to wait for another sync byte
      self._data[self._data_idx] = ((byte & 0x7F) << 1) | lsb
      self._data_idx += 1
      if self._data_idx == len(self._data):
        self._accept_data = False
        if sum(self._data) & 0xFF == 0x00 and self._data[0] & 0x80 == 0x00: return False, True, False
    return False, False, self._accept_data
  
  def result(self):
    return self._in_groups, self._data


class _DcdToMacDecoder:
  
  def __init__(self):
    self.reset()
  
  def reset(self, in_groups=0):
    self._accept_data = True if in_groups else False
    self._sync = False
    self._first_sync = True
    self._in_groups = in_groups
    self._data = bytearray(in_groups * 7)
    self._expect_lsb_byte = False
    self._data_idx = 0
  
  def feed_byte(self, byte):
    if not self._accept_data: return False, False, False
    if not self._sync:
      if byte == 0xAA: self._sync = True
      if self._first_sync:
        self._first_sync = False
        return True, False, True
      else:
        return False, False, True
    elif self._expect_lsb_byte:
      self._data[self._data_idx - 7] = (self._data[self._data_idx - 7] << 1) | (1 if byte & 0x01 else 0)
      self._data[self._data_idx - 6] = (self._data[self._data_idx - 6] << 1) | (1 if byte & 0x02 else 0)
      self._data[self._data_idx - 5] = (self._data[self._data_idx - 5] << 1) | (1 if byte & 0x04 else 0)
      self._data[self._data_idx - 4] = (self._data[self._data_idx - 4] << 1) | (1 if byte & 0x08 else 0)
      self._data[self._data_idx - 3] = (self._data[self._data_idx - 3] << 1) | (1 if byte & 0x10 else 0)
      self._data[self._data_idx - 2] = (self._data[self._data_idx - 2] << 1) | (1 if byte & 0x20 else 0)
      self._data[self._data_idx - 1] = (self._data[self._data_idx - 1] << 1) | (1 if byte & 0x40 else 0)
      if byte & 0x80 == 0x00: self._sync = False
      self._expect_lsb_byte = False
      if self._data_idx == len(self._data):
        self._accept_data = False
        if sum(self._data) & 0xFF == 0x00 and self._data[0] & 0x80: return False, True, False
    else:
      self._data[self._data_idx] = byte & 0x7F
      self._data_idx += 1
      if self._data_idx % 7 == 0: self._expect_lsb_byte = True
    return False, False, self._accept_data
  
  def result(self):
    return self._in_groups, self._data


class Analyzer:
  
  def __init__(self, serial_port, file_prefix):
    self._s = serial.Serial(port=serial_port, baudrate=1000000, timeout=0.25)
    self._file_prefix = file_prefix
    self._log_fp = open('%s.log' % self._file_prefix, 'w')
    self._serial_fp = open('%s_serial.bin' % self._file_prefix, 'wb')
    self._trans_fp = None
    self._cur_trans_num = -1
    self._cur_data = -1
  
  def _step_trans_file(self):
    if self._trans_fp: self._trans_fp.close()
    self._cur_trans_num += 1
    self._trans_fp = open('%s_trans_%08d.bin' % (self._file_prefix, self._cur_trans_num), 'wb')
  
  def _log_ts(self, msg):
    msg = '%s %s\n' % (time.strftime('(%H:%M:%S)'), msg)
    self._log_fp.write(msg)
    sys.stdout.write(msg)
    sys.stdout.flush()
  
  def _log(self, log_num, log_dir, log_tell, msg):
    self._log_ts('%08d %s %08d: %s' % (log_num, 'DCD' if log_dir else 'Mac', log_tell, msg))
  
  def _log_data(self, log_num, log_dir, log_tell, data):
    self._cur_data += 1
    preview = ' '.join(('%02X' % i) for i, _ in zip(data, range(7)))
    self._log(log_num, log_dir, log_tell, 'Data  %08d: %s' % (self._cur_data, preview))
    with open('%s_data_%08d_%s.bin' % (self._file_prefix, self._cur_data, 'dcd' if log_dir else 'mac'), 'wb') as fp:
      fp.write(data)
  
  def _close(self):
    self._s.close()
    self._log_fp.close()
    self._serial_fp.close()
    if self._trans_fp: self._trans_fp.close()
  
  def analyze(self):
    mid_transaction = False
    mac_to_dcd = _MacToDcdDecoder()
    dcd_to_mac = _DcdToMacDecoder()
    mac_to_dcd_tell = 0
    dcd_to_mac_tell = 0
    try:
      while True:
        byte = self._s.read(1)
        if byte:
          if not mid_transaction:
            mid_transaction = True
            self._step_trans_file()
          self._serial_fp.write(byte)
          byte_val = byte[0]
        else:
          if mid_transaction:
            mid_transaction = False
            mac_to_dcd.reset()
            dcd_to_mac.reset()
            self._log_ts('%08d end of transaction' % self._cur_trans_num)
          continue
        mac_to_dcd_sync, mac_to_dcd_done, mac_to_dcd_hopeful = mac_to_dcd.feed_byte(byte_val)
        dcd_to_mac_sync, dcd_to_mac_done, dcd_to_mac_hopeful = dcd_to_mac.feed_byte(byte_val)
        if mac_to_dcd_sync: mac_to_dcd_tell = self._trans_fp.tell()
        if dcd_to_mac_sync: dcd_to_mac_tell = self._trans_fp.tell()
        self._trans_fp.write(byte)
        if mac_to_dcd_done:
          in_groups, data = mac_to_dcd.result()
          mac_to_dcd.reset()
          dcd_to_mac.reset(in_groups)
          self._log_data(self._cur_trans_num, False, mac_to_dcd_tell, data)
        elif dcd_to_mac_done:
          in_groups, data = dcd_to_mac.result()
          mac_to_dcd.reset()
          dcd_to_mac.reset(in_groups)
          self._log_data(self._cur_trans_num, True, dcd_to_mac_tell, data)
        elif not mac_to_dcd_hopeful and not dcd_to_mac_hopeful:
          mid_transaction = False
          mac_to_dcd.reset()
          dcd_to_mac.reset()
          self._log_ts('%08d DESYNCHRONIZED TRANSACTION' % self._cur_trans_num)
    except KeyboardInterrupt:
      self._close()
