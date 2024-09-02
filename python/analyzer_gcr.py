'''GCR floppy analyzer for IWM/SWIM analyzer PIC firmware.

Protocol should be set to GCR (protocol select pin should be pulled low), GPi should be connected to !WRREQ.

Requires PySerial.
'''

from collections import deque
import struct
import sys
import time

import serial


IWM_TO_NIBBLE = [None, None, None, None, None, None, None, None, None, None, None, None, None, None, None, None,
                 None, None, None, None, None, None, 0x00, 0x01, None, None, 0x02, 0x03, None, 0x04, 0x05, 0x06,
                 None, None, None, None, None, None, 0x07, 0x08, None, None, None, 0x09, 0x0A, 0x0B, 0x0C, 0x0D,
                 None, None, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, None, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A,
                 None, None, None, None, None, None, None, None, None, None, None, 0x1B, None, 0x1C, 0x1D, 0x1E,
                 None, None, None, 0x1F, None, None, 0x20, 0x21, None, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28,
                 None, None, None, None, None, 0x29, 0x2A, 0x2B, None, 0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32,
                 None, None, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, None, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F]


class DenibblizeError(Exception): pass


def denibblize(data):
  '''Generator to denibblize data.'''
  data = iter(data)
  while True:
    try:
      hi_bits = next(data)
    except StopIteration:
      return
    try:
      yield next(data) | ((hi_bits << 2) & 0xC0)
    except StopIteration:
      raise DenibblizeError('denibblization ended on unused hi-bits nibble (0x%02X)' % hi_bits)
    try:
      yield next(data) | ((hi_bits << 4) & 0xC0)
    except StopIteration:
      if hi_bits & 0x0F: raise DenibblizeError('denibblization ended on partially-unused hi-bits nibble (0x%02X)' % hi_bits)
    try:
      yield next(data) | ((hi_bits << 6) & 0xC0)
    except StopIteration:
      if hi_bits & 0x03: raise DenibblizeError('denibblization ended on partially-unused hi-bits nibble (0x%02X)' % hi_bits)
      return


def demangle(data):
  '''Decoder for mangled GCR data.  Returns a 3-tuple of (demangled data, target checksum, actual checksum).'''
  target_checksum = tuple(denibblize(data[-4:]))
  data = bytearray(denibblize(data[:-4]))
  view = memoryview(data)
  checksum_a = checksum_b = checksum_c = 0
  carry_a = carry_b = carry_c = 0
  for i in range((len(data) + 2) // 3):
    trio = view[i * 3:(i + 1) * 3]
    carry = 1 if (checksum_c & 0x80) else 0
    checksum_c = ((checksum_c << 1) & 0xFF) | carry
    trio[0] ^= checksum_c
    carry, checksum_a = divmod(checksum_a + trio[0] + carry, 256)
    if len(trio) < 2: break
    trio[1] ^= checksum_a
    carry, checksum_b = divmod(checksum_b + trio[1] + carry, 256)
    if len(trio) < 3: break
    trio[2] ^= checksum_b
    carry, checksum_c = divmod(checksum_c + trio[2] + carry, 256)
  actual_checksum = (checksum_a, checksum_b, checksum_c)
  return data, target_checksum, actual_checksum


class TransactionReader:
  
  def __init__(self, serial_port, file_prefix):
    self._s = serial.Serial(port=serial_port, baudrate=1000000, timeout=0.25)
    self._last_dir = None
    self._unget = None
    self._fp = open('%s_serial.bin' % file_prefix, 'wb')
  
  def read(self, length):
    retval = deque()
    for _ in range(length):
      if self._unget:
        byte = self._unget
        self._unget = None
      else:
        byte = b''
        while not byte:
          byte = self._s.read(1)
          self._fp.write(byte)
        byte = byte[0]
      this_dir = True if byte & 0x80 else False
      if self._last_dir is None: self._last_dir = this_dir
      if this_dir != self._last_dir:
        self._last_dir = this_dir
        self._unget = byte
        return not self._last_dir, bytes(i | 0x80 for i in retval)
      retval.append(byte)
    return this_dir, bytes(i | 0x80 for i in retval)
  
  def close(self):
    self._s.close()
    self._fp.close()


class Analyzer:
  
  ADDRESS_MARK_LENGTH = 10  # D5, AA, 96, track, sector, side, format, checksum, DE, AA
  DATA_MARK_LENGTH = 709  # D5, AA, AD, sector, 703 bytes, DE, AA
  
  def __init__(self, serial_port, file_prefix):
    self._reader = TransactionReader(serial_port, file_prefix)
    self._file_prefix = file_prefix
    self._log_fp = open('%s.log' % self._file_prefix, 'w')
    self._last_dir = None
    self._trans_fp = None
    self._cur_trans_num = -1
    self._window = deque()
    self._window_end = False
    self._cur_data_mark = -1
  
  def _step_trans_file(self, this_dir):
    if self._trans_fp: self._trans_fp.close()
    self._cur_trans_num += 1
    self._trans_fp = open('%s_trans_%08d_%s.bin' % (self._file_prefix, self._cur_trans_num, 'rd' if this_dir else 'wr'), 'wb')
  
  def _read_trans(self, length):
    this_dir, data = self._reader.read(length)
    if self._last_dir != this_dir:
      self._last_dir = this_dir
      self._step_trans_file(this_dir)
    tell = self._trans_fp.tell()
    self._trans_fp.write(data)
    return self._cur_trans_num, this_dir, tell, data
  
  def _pop_window(self, length):
    for _ in range(length):
      if self._window: self._window.popleft()
    if not self._window: self._window_end = False
  
  def _peek_window(self, length):
    if not self._window_end:
      while len(self._window) < length:
        next_num, next_dir, next_tell, next_data = self._read_trans(1)
        if not next_data:
          self._window_end = True
          break
        self._window.append((next_num, next_dir, next_tell, next_data))
    if self._window:
      read_num, read_dir, read_tell, _ = self._window[0]
      return read_num, read_dir, read_tell, b''.join(i[3] for _, i in zip(range(length), self._window))
    else:
      return None, None, None, b''
  
  def _log_ts(self, msg):
    msg = '%s %s\n' % (time.strftime('(%H:%M:%S)'), msg)
    self._log_fp.write(msg)
    sys.stdout.write(msg)
    sys.stdout.flush()
  
  def _log(self, log_num, log_dir, log_tell, msg):
    self._log_ts('%08d %s %08d: %s' % (log_num, 'rd' if log_dir else 'wr', log_tell, msg))
  
  def _log_data_mark(self, log_num, log_dir, log_tell, track, sector, side, fmt, data):
    self._cur_data_mark += 1
    self._log(log_num, log_dir, log_tell, 'DM  %08d' % self._cur_data_mark)
    with open('%s_data_%08d_%s.bin' % (self._file_prefix, self._cur_data_mark, 'rd' if log_dir else 'wr'), 'wb') as fp:
      fp.write(data)
    #TODO assemble a .dc42 image?
  
  def _close(self):
    self._reader.close()
    self._log_fp.close()
  
  def analyze(self):
    try:
      track = sector = side = fmt = None
      while True:
        _, _, _, sig = self._peek_window(3)
        if sig == b'\xD5\xAA\x96':
          win_num, win_dir, win_tell, win_data = self._peek_window(self.ADDRESS_MARK_LENGTH)
          if len(win_data) != self.ADDRESS_MARK_LENGTH:
            self._log(win_num, win_dir, win_tell,
                      'AM  TRUNCATED (length %d, should be %d)' % (len(win_data), self.ADDRESS_MARK_LENGTH))
            self._pop_window(1)
            continue
          if not win_data.endswith(b'\xDE\xAA'):
            self._log(win_num, win_dir, win_tell, 'AM  MISSING BIT SLIP BYTES')
            self._pop_window(1)
            continue
          address_mark = tuple(IWM_TO_NIBBLE[byte & 0x7F] for byte in win_data[3:8])
          if None in address_mark:
            invalid_nibbles = tuple(('0x%02X' % (byte | 0x80)) for byte in win_data[3:8] if IWM_TO_NIBBLE[byte & 0x7F] is None)
            self._log(win_num, win_dir, win_tell, 'AM  INVALID NIBBLE(S) %s' % ', '.join(invalid_nibbles))
            self._pop_window(1)
            continue
          track, sector, side, fmt, stored_checksum = address_mark
          calc_checksum = track ^ sector ^ side ^ fmt
          if stored_checksum != calc_checksum:
            self._log(win_num, win_dir, win_tell, 'AM  BAD CHECKSUM, 0x%02X != 0x%02X' % (stored_checksum, calc_checksum))
            self._pop_window(1)
            continue
          track = ((side << 6) | track) & 0x7FF
          side >>= 5
          self._log(win_num, win_dir, win_tell, 'AM  tk %03d  sec %03d  side %d  fmt 0x%02X' % (track, sector, side, fmt))
          self._pop_window(self.ADDRESS_MARK_LENGTH)
        elif sig == b'\xD5\xAA\xAD':
          win_num, win_dir, win_tell, win_data = self._peek_window(self.DATA_MARK_LENGTH)
          if len(win_data) != self.DATA_MARK_LENGTH:
            self._log(win_num, win_dir, win_tell,
                      'DM  TRUNCATED (length %d, should be %d)' % (len(win_data), self.DATA_MARK_LENGTH))
            self._pop_window(1)
            continue
          if not win_data.endswith(b'\xDE\xAA'):
            self._log(win_num, win_dir, win_tell, 'DM  MISSING BIT SLIP BYTES')
            self._pop_window(1)
            continue
          data_mark_sector = IWM_TO_NIBBLE[win_data[3] & 0x7F]
          if data_mark_sector is None:
            self._log(win_num, win_dir, win_tell, 'DM  INVALID SECTOR NIBBLE 0x%02X' % (win_data[3] | 0x80))
            self._pop_window(1)
            continue
          nibbles = [IWM_TO_NIBBLE[i & 0x7F] for i in win_data[4:707]]
          if None in nibbles:
            invalid_nibbles = tuple(('0x%02X' % (byte | 0x80)) for byte in win_data[4:707] if IWM_TO_NIBBLE[byte & 0x7F] is None)
            self._log(win_num, win_dir, win_tell, 'DM  INVALID NIBBLE(S) %s' % ', '.join(invalid_nibbles))
            self._pop_window(1)
            continue
          self._pop_window(self.DATA_MARK_LENGTH)  # at this point, decide that this is a valid-enough data mark
          try:
            data, target_checksum, actual_checksum = demangle(nibbles)
          except DenibblizeError as e:
            self._log(win_num, win_dir, win_tell, 'DM  DENIBBLIZE ERROR: %s' % e.args[0])
            continue
          if data_mark_sector != sector:
            self._log(win_num, win_dir, win_tell, 'DM  WRONG SECTOR: %d, should be %d' % (data_mark_sector, sector))
            continue
          if target_checksum != actual_checksum:
            self._log(win_num, win_dir, win_tell, 'DM  BAD CHECKSUM: %s, should be %s' % (actual_checksum, target_checksum))
            continue
          self._log_data_mark(win_num, win_dir, win_tell, track, sector, side, fmt, data)
        else:
          self._pop_window(1)
    except KeyboardInterrupt:
      self._close()
