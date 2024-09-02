'''MFM floppy analyzer for IWM/SWIM analyzer PIC firmware.

Protocol should be set to MFM (protocol select pin should be pulled high), GPi is ignored.

Requires PySerial.
'''

from collections import deque
import struct
import sys
import time

import serial

class CRC16:
  
  def __init__(self, poly=0x1021, reg=0xFFFF):
    self.poly = poly
    self.reg = reg
  
  def update(self, data):
    for byte in data:
      self.reg = self.reg ^ byte << 8
      for i in range(8): self.reg = self.reg << 1 & 0xFFFF ^ (self.poly if self.reg & 0x8000 else 0)
    return self.reg
  
  def getvalue(self): return self.reg


class TransactionReader:
  
  def __init__(self, serial_port, file_prefix):
    self._s = serial.Serial(port=serial_port, baudrate=1000000, timeout=0.25)
    self._fp = open('%s_serial.bin' % file_prefix, 'wb')
  
  def read(self, length):
    retval = deque()
    for _ in range(length):
      byte = b''
      while not byte:
        byte = self._s.read(1)
        self._fp.write(byte)
      byte = byte[0]
      retval.append(byte)
    return bytes(retval)
  
  def tell(self):
    return self._fp.tell()
  
  def close(self):
    self._s.close()
    self._fp.close()


class Analyzer:
  
  INDEX_MARK_LENGTH = 4  # C2, C2, C2, FC
  ADDRESS_MARK_LENGTH = 10  # A1, A1, A1, FE, track, sector, side, format, CRC16H, CRC16L
  DATA_MARK_LENGTH = 518  # A1, A1, A1, FB, 512 bytes, CRC16H, CRC16L
  
  def __init__(self, serial_port, file_prefix):
    self._reader = TransactionReader(serial_port, file_prefix)
    self._file_prefix = file_prefix
    self._log_fp = open('%s.log' % self._file_prefix, 'w')
    self._window = deque()
    self._window_end = False
    self._cur_data_mark = -1
  
  def _read_trans(self, length):
    tell = self._reader.tell()
    data = self._reader.read(length)
    return tell, data
  
  def _pop_window(self, length):
    for _ in range(length):
      if self._window: self._window.popleft()
    if not self._window: self._window_end = False
  
  def _peek_window(self, length):
    if not self._window_end:
      while len(self._window) < length:
        next_tell, next_data = self._read_trans(1)
        if not next_data:
          self._window_end = True
          break
        self._window.append((next_tell, next_data))
    if self._window:
      read_tell, _ = self._window[0]
      return read_tell, b''.join(i[1] for _, i in zip(range(length), self._window))
    else:
      return None, b''
  
  def _log_ts(self, msg):
    msg = '%s %s\n' % (time.strftime('(%H:%M:%S)'), msg)
    self._log_fp.write(msg)
    sys.stdout.write(msg)
    sys.stdout.flush()
  
  def _log(self, log_tell, msg):
    self._log_ts('%08d: %s' % (log_tell, msg))
  
  def _log_data_mark(self, log_tell, track, sector, side, size, data):
    self._cur_data_mark += 1
    self._log(log_tell, 'DM  %08d' % self._cur_data_mark)
    with open('%s_data_%08d.bin' % (self._file_prefix, self._cur_data_mark), 'wb') as fp: fp.write(data)
  
  def _close(self):
    self._reader.close()
    self._log_fp.close()
  
  def analyze(self):
    try:
      track = sector = side = size = None
      while True:
        _, sig = self._peek_window(4)
        if sig == b'\xC2\xC2\xC2\xFC':
          win_tell, win_data = self._peek_window(self.INDEX_MARK_LENGTH)
          self._pop_window(self.INDEX_MARK_LENGTH)
          self._log(win_tell, 'IM')
        elif sig == b'\xA1\xA1\xA1\xFE':
          win_tell, win_data = self._peek_window(self.ADDRESS_MARK_LENGTH)
          if len(win_data) != self.ADDRESS_MARK_LENGTH:
            self._log(win_tell, 'AM  TRUNCATED (length %d, should be %d)' % (len(win_data), self.ADDRESS_MARK_LENGTH))
            self._pop_window(1)
            continue
          if CRC16().update(win_data):
            self._log(win_tell, 'AM  BAD CRC')
            self._pop_window(1)
            continue
          track, side, sector, size = tuple(win_data[4:8])
          self._log(win_tell, 'AM  tk %03d  side %d  sec %03d  size %03d' % (track, side, sector, size * 256))
          self._pop_window(self.ADDRESS_MARK_LENGTH)
        elif sig == b'\xA1\xA1\xA1\xFB':
          win_tell, win_data = self._peek_window(self.DATA_MARK_LENGTH)
          if len(win_data) != self.DATA_MARK_LENGTH:
            self._log(win_tell, 'DM  TRUNCATED (length %d, should be %d)' % (len(win_data), self.DATA_MARK_LENGTH))
            self._pop_window(1)
            continue
          if CRC16().update(win_data):
            self._log(win_tell, 'DM  BAD CRC')
            self._pop_window(1)
            continue
          self._pop_window(self.DATA_MARK_LENGTH)
          self._log_data_mark(win_tell, track, sector, side, size, win_data[4:])
        else:
          self._pop_window(1)
    except KeyboardInterrupt:
      self._close()
