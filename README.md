# IWM/SWIM Analyzer

This PIC16F1704 firmware interprets data from the RD and WR lines on the Macintosh's IWM/SWIM chip and translates them to a simple UART protocol for analysis.  This project also includes a PCB and Python code to interpret the output of the firmware.


## Building Firmware

Building the firmware requires Microchip MPASM, which is included with their development environment, MPLAB. Note that you must use MPLAB X version 5.35 or earlier or MPLAB 8 as later versions of MPLAB X have removed MPASM.


## Pin Assignments

```
                               .--------.
                       Supply -|01 \/ 14|- Ground
      Protocol Select --> RA5 -|02    13|- RA0 <-> ICSPDAT
General Purpose Input --> RA4 -|03    12|- RA1 <-- ICSPCLK
            Vpp/!MCLR --> RA3 -|04    11|- RA2 <--
               !WRREQ --> RC5 -|05    10|- RC0 <--
                !ENBL --> RC4 -|06    09|- RC1 <-- WR
                   RD --> RC3 -|07    08|- RC2 --> UART TX
                               '--------'
```

The pins can be remapped by changing the constants in the Pin Assignments section of the .asm file, however, !WRREQ and !ENBL must be on the same port.


### Protocol Select

This pin determines whether the PIC interprets RD and WR signals as MFM or GCR/DCD.  If the pin reads as high, signals are interpreted as MFM; if the pin reads as low, signals are interpreted as GCR/DCD.  The pin is pulled up by default.


### General Purpose Input

In GCR/DCD mode, this pin's current value is returned to the host along with data from RD and WR.


## UART Protocol and Analysis Capabilities

The PIC's UART transmits at 1 MHz, with 8 data bits, 1 stop bit, and no parity.


### GCR/DCD Mode

This mode is selected when the Protocol Select pin is pulled low.

In this mode, the firmware interprets and relays bytes from the IWM/SWIM chip in IWM (GCR) mode.  In this mode, the Macintosh and disk communicate at 47/96 (~0.490) MHz in 8-bit data bytes, MSB to LSB, where a transition on the line indicates a 1 bit and no transition indicates a 0 bit.  The MSB of the 8-bit data byte is always high, as it is used to indicate the start of a bit.  When !WRREQ is low, data is read from the WR line and both rising and falling transitions are interpreted as 1 bits; when !WRREQ is high, data is read from the RD line and only falling transitions are interpreted as 1 bits.

Because only 7 bits out of 8 are significant, the MSB of the byte as relayed over the UART is sampled, right before transmission, from the General Purpose Input pin.  The GCR analyzer uses this function to sample !WRREQ so it knows whether data is being read from or written to the disk.  The DCD analyzer uses this function to sample CA0 so it can recognize and correctly deal with a holdoff condition when communicating with the DCD device.  The value of the General Purpose Input pin is only communicated along with a data byte.

Because the RD line is also used to communicate the values of drive control signals, the firmware may interpret a falling transition that is not part of any valid data as a data byte.


### MFM Mode

This mode is selected when the Protocol Select pin is allowed to float high.

In this mode, the firmware interprets and relays bytes from the SWIM chip in SWIM (MFM) mode.  In this mode, the Macintosh and disk communicate using modified frequency modulation (MFM) at 1 MHz.  When !WRREQ is low, data is read from the WR line; when !WRREQ is high, data is read from the RD line.  In both cases, only falling transitions are interpreted as significant.

Because both MFM and the UART communicate in terms of 8-bit bytes where all bits are significant, the General Purpose Input pin is not used and the firmware does not communicate the direction of data.

The firmware looks for a pattern of 60 or more consecutive 0 bits in order to synchronize with incoming data.  If more than 2 bit cells pass without a transition, synchronization is lost and must be newly acquired with a pattern of 60 or more consecutive 0 bits.

To indicate index, address, and data marks, MFM uses special versions of the 0xC2 and 0xA1 bytes, with ordinarily-required clock bits missing.  The firmware relays these as ordinary 0xC2 and 0xA1 bytes and their significance must be inferred from context.


## Python Analyzers

### Quick Start

Install PySerial using pip or your distro's package manager.

Invoke the Python interpreter on the desired analyzer with the `-i` command line switch, for example:

```
python3 -i analyzer_gcr.py
```

Once the interpreter is started, instantiate and run the analyzer as follows:

```
Analyzer('/dev/ttyUSB0', 'test').analyze()
```

Replace `/dev/ttyUSB0` by the serial port whence the analyzer's output is to be read and `test` by a prefix to be prepended to files output by the analyzer.


### GCR Analyzer

The GCR analyzer is used to analyze the data read from and written to Macintosh GCR (400/800 KB) disks.


#### Files

The GCR analyzer outputs the following files:

| Suffix                   | Contents                                                                                       |
| ------------------------ | ---------------------------------------------------------------------------------------------- |
| `.log`                   | Same as the data written to stdout.                                                            |
| `_serial.bin`            | All data read from the serial port.                                                            |
| `_trans_99999999_dd.bin` | All data in the numbered (99999999) transaction.  `dd` indicates the direction (`rd` or `wr`). |
| `_data_99999999_dd.bin`  | Data in the numbered (99999999) data mark.  `dd` indicates the direction (`rd` or `wr`).       |

"Transaction" is used to mean a sequence of data bordered by a change in direction.


### DCD Analyzer

The DCD analyzer is used to analyze the data read from and written to DCD (Directly Connected Disk) devices.


#### Files

The DCD analyzer outputs the following files:

| Suffix                    | Contents                                                                                                |
| ------------------------- | ------------------------------------------------------------------------------------------------------- |
| `.log`                    | Same as the data written to stdout.                                                                     |
| `_serial.bin`             | All data read from the serial port.                                                                     |
| `_trans_99999999_ddd.bin` | All data in the numbered (99999999) transaction.  `dd` indicates the source direction (`mac` or `dcd`). |
| `_data_99999999_ddd.bin`  | Data in the numbered (99999999) data payload.  `dd` indicates the source direction (`mac` or `dcd`).    |

"Transaction" is used to mean a sequence of data bordered by a delay of 0.25 seconds or more.
