;;; 80 characters wide please ;;;;;;;;;;;;;;;;;;;;;;;;;; 8-space tabs please ;;;


;
;;;
;;;;;  IWM/SWIM Protocol Analyzer
;;;
;


;;; Connections ;;;

;;;                                                              ;;;
;                                   .--------.                     ;
;                           Supply -|01 \/ 14|- Ground             ;
;          Protocol Select --> RA5 -|02    13|- RA0 <-> ICSPDAT    ;
;    General Purpose Input --> RA4 -|03    12|- RA1 <-- ICSPCLK    ;
;                Vpp/!MCLR --> RA3 -|04    11|- RA2 <--            ;
;                   !WRREQ --> RC5 -|05    10|- RC0 <--            ;
;                    !ENBL --> RC4 -|06    09|- RC1 <-- WR         ;
;                       RD --> RC3 -|07    08|- RC2 --> UART TX    ;
;                                   '--------'                     ;
;;;                                                              ;;;


;;; Assembler Directives ;;;

	list		P=PIC16F1704, F=INHX32, ST=OFF, MM=OFF, R=DEC, X=ON
	#include	P16F1704.inc
	errorlevel	-302	;Suppress "register not in bank 0" messages
	errorlevel	-224	;Suppress TRIS instruction not recommended msgs
	__config	_CONFIG1, _FOSC_INTOSC & _WDTE_OFF & _PWRTE_ON & _MCLRE_OFF & _CP_OFF & _BOREN_OFF & _CLKOUTEN_OFF & _IESO_OFF & _FCMEN_OFF
			;_FOSC_INTOSC	Internal oscillator, I/O on RA5
			;_WDTE_OFF	Watchdog timer disabled
			;_PWRTE_ON	Keep in reset for 64 ms on start
			;_MCLRE_OFF	RA3/!MCLR is RA3
			;_CP_OFF	Code protection off
			;_BOREN_OFF	Brownout reset off
			;_CLKOUTEN_OFF	CLKOUT disabled, I/O on RA4
			;_IESO_OFF	Internal/External switch not needed
			;_FCMEN_OFF	Fail-safe clock monitor not needed
	__config	_CONFIG2, _WRT_OFF & _PPS1WAY_OFF & _ZCDDIS_ON & _PLLEN_ON & _STVREN_OFF & _LVP_OFF
			;_WRT_OFF	Write protection off
			;_PPS1WAY_OFF	PPS can change more than once
			;_ZCDDIS_ON	Zero crossing detector disabled
			;_PLLEN_ON	4x PLL on
			;_STVREN_OFF	Stack over/underflow DOES NOT RESET
			;_LVP_OFF	High-voltage on Vpp to program


;;; Macros ;;;

DELAY	macro	value		;Delay 3*W cycles, set W to 0
	movlw	value
	decfsz	WREG,F
	bra	$-1
	endm

DNOP	macro
	bra	$+1
	endm


;;; Pin Assignments ;;;

TX_PORT	equ	PORTC
TX_PIN	equ	RC2
TX_PPSI	equ	0x12
TX_PPSO	equ	RC2PPS
GI_PORT	equ	PORTA
GI_PIN	equ	RA4
RD_PORT	equ	PORTC
RD_PIN	equ	RC3
RD_PPSI	equ	0x13
EN_PORT	equ	PORTC
EN_IOCP	equ	IOCCP
EN_IOCN	equ	IOCCN
EN_IOCF	equ	IOCCF
EN_PIN	equ	RC4
WQ_PORT	equ	PORTC
WQ_IOCP	equ	IOCCP
WQ_IOCN	equ	IOCCN
WQ_IOCF	equ	IOCCF
WQ_PIN	equ	RC5
WR_PORT	equ	PORTC
WR_PIN	equ	RC1
WR_PPSI	equ	0x11
PS_PORT	equ	PORTA
PS_WPU	equ	WPUA
PS_PIN	equ	RA5

if WQ_IOCF != EN_IOCF
error "!WRREQ and !ENBL must be on same port"
endif


;;; Variable Storage ;;;

	cblock	0x70	;Bank-common registers
	
	FLAGS		;You've got to have flags
	X14
	X13
	X12
	X11
	X10
	X9
	X8
	X7
	X6
	X5
	X4
	X3
	X2
	X1
	X0
	
	endc


;;; Vectors ;;;

	org	0x0		;Reset vector
	movlp	0
	goto	Init

	org	0x4		;Interrupt vector


;;; Interrupt Handler ;;;

Interrupt
	movlb	7		;Clear IOCxF first and reenable interrupts so we
	clrf	WQ_IOCF		; can catch any mode change as quick as possible
	bsf	INTCON,GIE	; "
	movlb	0		; "
	btfsc	EN_PORT,EN_PIN	;If !ENBL is high, just sit and spin
	bra	$		; "
	btfss	PS_PORT,PS_PIN	;Select protocol based on state of pin
	bra	IntGcr		; "
	;fall through

IntMfm
	movlw	WR_PPSI		;We use the same code for MFM receiving in both
	btfsc	WQ_PORT,WQ_PIN	; directions, we just change which pin it's done
	movlw	RD_PPSI		; on based on direction according to !WRREQ pin
	movwf	INDF1		; "
	movlp	8		;Jump into MFM receiver
	goto	RecvMfm		; "

IntGcr
	movlp	0		;Select receiver to jump into based on direction
	btfss	WQ_PORT,WQ_PIN	; according to !WRREQ pin
	goto	RecvWr		; "
	goto	RecvRd		; "


;;; Hardware Initialization ;;;

Init
	banksel	OSCCON		;32 MHz (w/PLL) high-freq internal oscillator
	movlw	B'11110000'
	movwf	OSCCON

	banksel	RCSTA		;UART async mode, 1 MHz, but receiver off
	movlw	B'01001000'
	movwf	BAUDCON
	clrf	SPBRGH
	movlw	7
	movwf	SPBRGL
	movlw	B'00100110'
	movwf	TXSTA
	movlw	B'10000000'
	movwf	RCSTA
	clrf	TXREG

	banksel	OSCSTAT		;Spin until PLL is ready and instruction clock
	btfss	OSCSTAT,PLLR	; gears up to 8 MHz
	bra	$-1

	banksel	IOCAN		;!ENBL and !WRREQ interrupt on either edge
	clrf	IOCAN
	clrf	IOCAP
	clrf	IOCCN
	clrf	IOCCP
	bsf	EN_IOCN,EN_PIN
	bsf	EN_IOCP,EN_PIN
	bsf	WQ_IOCN,WQ_PIN
	bsf	WQ_IOCP,WQ_PIN

	banksel	ANSELA		;All pins digital, not analog
	clrf	ANSELA
	clrf	ANSELC

	banksel	INLVLA		;All inputs TTL, not ST
	clrf	INLVLA
	clrf	INLVLC

	banksel	WPUA		;Weak pullup enabled only on protocol select pin
	clrf	WPUA
	clrf	WPUC
	bsf	PS_WPU,PS_PIN

	banksel	OPTION_REG	;Weak pullups enabled, INT pin interrupt
	movlw	B'00111111'	; triggers on falling edge
	movwf	OPTION_REG

	banksel	RA0PPS		;Set up PPS outputs
	movlw	B'00010100'
	movwf	TX_PPSO

	banksel	CKPPS		;Set up PPS inputs
	movlw	TX_PPSI
	movwf	CKPPS

	banksel	TRISA		;TX output, everything else input
	movlw	B'00111111'
	movwf	TRISA
	movwf	TRISC
	bcf	TX_PORT,TX_PIN

	movlw	high INTPPS	;Set up FSRs to point to INTPPS and TXREG so we
	movwf	FSR1H		; never have to change BSR
	movlw	low INTPPS
	movwf	FSR1L
	movlw	high TXREG
	movwf	FSR0H
	movlw	low TXREG
	movwf	FSR0L
	movlb	0

	movlw	B'10001000'	;IOC interrupt on, interrupt subsystem on
	movwf	INTCON

	bra	$		;Spin until an interrupt changes our mode


;;; RD GCR Receiver ;;;

RecvRd
	movlw	RD_PPSI		;Make sure the INT pin is assigned to the RD
	movwf	INDF1		; pin
	bcf	INTCON,INTF	;Clear flag from any past falling edge
	;fall through

RdStart	btfss	INTCON,INTF	;Signal starts at one, wait until we get a dip
	bra	$-1		; to zero, this is MSB (always 1) of byte
	bcf	INTCON,INTF	;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	nop			;007 cycles, 0.43 bit times
	movlw	B'00000000'	;008 cycles, 0.49 bit times
	btfsc	INTCON,INTF	;009 cycles, 0.55 bit times
	goto	RdChg6		;010 cycles, 0.61 bit times
	btfsc	INTCON,INTF	;011 cycles, 0.67 bit times
	goto	RdChg6		;012 cycles, 0.73 bit times
	btfsc	INTCON,INTF	;013 cycles, 0.80 bit times
	goto	RdChg6		;014 cycles, 0.86 bit times
	btfsc	INTCON,INTF	;015 cycles, 0.92 bit times
	goto	RdChg6		;016 cycles, 0.98 bit times
	btfsc	INTCON,INTF	;017 cycles, 1.04 bit times
	goto	RdChg6		;018 cycles, 1.10 bit times
	btfsc	INTCON,INTF	;019 cycles, 1.16 bit times
	goto	RdChg6		;020 cycles, 1.22 bit times
	btfsc	INTCON,INTF	;021 cycles, 1.29 bit times
	goto	RdChg6		;022 cycles, 1.35 bit times
	btfsc	INTCON,INTF	;023 cycles, 1.41 bit times
	goto	RdChg6		;024 cycles, 1.47 bit times
	btfsc	INTCON,INTF	;025 cycles, 1.53 bit times
	goto	RdChg5		;026 cycles, 1.59 bit times
	btfsc	INTCON,INTF	;027 cycles, 1.65 bit times
	goto	RdChg5		;028 cycles, 1.71 bit times
	btfsc	INTCON,INTF	;029 cycles, 1.77 bit times
	goto	RdChg5		;030 cycles, 1.84 bit times
	btfsc	INTCON,INTF	;031 cycles, 1.90 bit times
	goto	RdChg5		;032 cycles, 1.96 bit times
	btfsc	INTCON,INTF	;033 cycles, 2.02 bit times
	goto	RdChg5		;034 cycles, 2.08 bit times
	btfsc	INTCON,INTF	;035 cycles, 2.14 bit times
	goto	RdChg5		;036 cycles, 2.20 bit times
	btfsc	INTCON,INTF	;037 cycles, 2.26 bit times
	goto	RdChg5		;038 cycles, 2.33 bit times
	btfsc	INTCON,INTF	;039 cycles, 2.39 bit times
	goto	RdChg5		;040 cycles, 2.45 bit times
	btfsc	INTCON,INTF	;041 cycles, 2.51 bit times
	goto	RdChg4		;042 cycles, 2.57 bit times
	btfsc	INTCON,INTF	;043 cycles, 2.63 bit times
	goto	RdChg4		;044 cycles, 2.69 bit times
	btfsc	INTCON,INTF	;045 cycles, 2.75 bit times
	goto	RdChg4		;046 cycles, 2.82 bit times
	btfsc	INTCON,INTF	;047 cycles, 2.88 bit times
	goto	RdChg4		;048 cycles, 2.94 bit times
	btfsc	INTCON,INTF	;049 cycles, 3.00 bit times
	goto	RdChg4		;050 cycles, 3.06 bit times
	btfsc	INTCON,INTF	;051 cycles, 3.12 bit times
	goto	RdChg4		;052 cycles, 3.18 bit times
	btfsc	INTCON,INTF	;053 cycles, 3.24 bit times
	goto	RdChg4		;054 cycles, 3.30 bit times
	btfsc	INTCON,INTF	;055 cycles, 3.37 bit times
	goto	RdChg4		;056 cycles, 3.43 bit times
	btfsc	INTCON,INTF	;057 cycles, 3.49 bit times
	goto	RdChg4		;058 cycles, 3.55 bit times
	btfsc	INTCON,INTF	;059 cycles, 3.61 bit times
	goto	RdChg3		;060 cycles, 3.67 bit times
	btfsc	INTCON,INTF	;061 cycles, 3.73 bit times
	goto	RdChg3		;062 cycles, 3.79 bit times
	btfsc	INTCON,INTF	;063 cycles, 3.86 bit times
	goto	RdChg3		;064 cycles, 3.92 bit times
	btfsc	INTCON,INTF	;065 cycles, 3.98 bit times
	goto	RdChg3		;066 cycles, 4.04 bit times
	btfsc	INTCON,INTF	;067 cycles, 4.10 bit times
	goto	RdChg3		;068 cycles, 4.16 bit times
	btfsc	INTCON,INTF	;069 cycles, 4.22 bit times
	goto	RdChg3		;070 cycles, 4.28 bit times
	btfsc	INTCON,INTF	;071 cycles, 4.35 bit times
	goto	RdChg3		;072 cycles, 4.41 bit times
	btfsc	INTCON,INTF	;073 cycles, 4.47 bit times
	goto	RdChg3		;074 cycles, 4.53 bit times
	btfsc	INTCON,INTF	;075 cycles, 4.59 bit times
	goto	RdChg2		;076 cycles, 4.65 bit times
	btfsc	INTCON,INTF	;077 cycles, 4.71 bit times
	goto	RdChg2		;078 cycles, 4.77 bit times
	btfsc	INTCON,INTF	;079 cycles, 4.83 bit times
	goto	RdChg2		;080 cycles, 4.90 bit times
	btfsc	INTCON,INTF	;081 cycles, 4.96 bit times
	goto	RdChg2		;082 cycles, 5.02 bit times
	btfsc	INTCON,INTF	;083 cycles, 5.08 bit times
	goto	RdChg2		;084 cycles, 5.14 bit times
	btfsc	INTCON,INTF	;085 cycles, 5.20 bit times
	goto	RdChg2		;086 cycles, 5.26 bit times
	btfsc	INTCON,INTF	;087 cycles, 5.32 bit times
	goto	RdChg2		;088 cycles, 5.39 bit times
	btfsc	INTCON,INTF	;089 cycles, 5.45 bit times
	goto	RdChg2		;090 cycles, 5.51 bit times
	btfsc	INTCON,INTF	;091 cycles, 5.57 bit times
	goto	RdChg1		;092 cycles, 5.63 bit times
	btfsc	INTCON,INTF	;093 cycles, 5.69 bit times
	goto	RdChg1		;094 cycles, 5.75 bit times
	btfsc	INTCON,INTF	;095 cycles, 5.81 bit times
	goto	RdChg1		;096 cycles, 5.88 bit times
	btfsc	INTCON,INTF	;097 cycles, 5.94 bit times
	goto	RdChg1		;098 cycles, 6.00 bit times
	btfsc	INTCON,INTF	;099 cycles, 6.06 bit times
	goto	RdChg1		;100 cycles, 6.12 bit times
	btfsc	INTCON,INTF	;101 cycles, 6.18 bit times
	goto	RdChg1		;102 cycles, 6.24 bit times
	btfsc	INTCON,INTF	;103 cycles, 6.30 bit times
	goto	RdChg1		;104 cycles, 6.36 bit times
	btfsc	INTCON,INTF	;105 cycles, 6.43 bit times
	goto	RdChg1		;106 cycles, 6.49 bit times
	btfsc	INTCON,INTF	;107 cycles, 6.55 bit times
	goto	RdChg0		;108 cycles, 6.61 bit times
	btfsc	INTCON,INTF	;109 cycles, 6.67 bit times
	goto	RdChg0		;110 cycles, 6.73 bit times
	btfsc	INTCON,INTF	;111 cycles, 6.79 bit times
	goto	RdChg0		;112 cycles, 6.85 bit times
	btfsc	INTCON,INTF	;113 cycles, 6.92 bit times
	goto	RdChg0		;114 cycles, 6.98 bit times
	btfsc	INTCON,INTF	;115 cycles, 7.04 bit times
	goto	RdChg0		;116 cycles, 7.10 bit times
	btfsc	INTCON,INTF	;117 cycles, 7.16 bit times
	goto	RdChg0		;118 cycles, 7.22 bit times
	btfsc	INTCON,INTF	;119 cycles, 7.28 bit times
	goto	RdChg0		;120 cycles, 7.34 bit times
	btfsc	INTCON,INTF	;121 cycles, 7.40 bit times
	goto	RdChg0		;122 cycles, 7.47 bit times
	btfsc	GI_PORT,GI_PIN	;123 cycles, 7.53 bit times
	iorlw	B'10000000'	;124 cycles, 7.59 bit times
	movwf	INDF0		;125 cycles, 7.65 bit times
	goto	RdStart		;126 cycles, 7.71 bit times

RdChg6	iorlw	B'01000000'	;003 cycles, 0.18 bit times
	bcf	INTCON,INTF	;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfsc	INTCON,INTF	;009 cycles, 0.55 bit times
	goto	RdChg5		;010 cycles, 0.61 bit times
	btfsc	INTCON,INTF	;011 cycles, 0.67 bit times
	goto	RdChg5		;012 cycles, 0.73 bit times
	btfsc	INTCON,INTF	;013 cycles, 0.80 bit times
	goto	RdChg5		;014 cycles, 0.86 bit times
	btfsc	INTCON,INTF	;015 cycles, 0.92 bit times
	goto	RdChg5		;016 cycles, 0.98 bit times
	btfsc	INTCON,INTF	;017 cycles, 1.04 bit times
	goto	RdChg5		;018 cycles, 1.10 bit times
	btfsc	INTCON,INTF	;019 cycles, 1.16 bit times
	goto	RdChg5		;020 cycles, 1.22 bit times
	btfsc	INTCON,INTF	;021 cycles, 1.29 bit times
	goto	RdChg5		;022 cycles, 1.35 bit times
	btfsc	INTCON,INTF	;023 cycles, 1.41 bit times
	goto	RdChg5		;024 cycles, 1.47 bit times
	btfsc	INTCON,INTF	;025 cycles, 1.53 bit times
	goto	RdChg4		;026 cycles, 1.59 bit times
	btfsc	INTCON,INTF	;027 cycles, 1.65 bit times
	goto	RdChg4		;028 cycles, 1.71 bit times
	btfsc	INTCON,INTF	;029 cycles, 1.77 bit times
	goto	RdChg4		;030 cycles, 1.84 bit times
	btfsc	INTCON,INTF	;031 cycles, 1.90 bit times
	goto	RdChg4		;032 cycles, 1.96 bit times
	btfsc	INTCON,INTF	;033 cycles, 2.02 bit times
	goto	RdChg4		;034 cycles, 2.08 bit times
	btfsc	INTCON,INTF	;035 cycles, 2.14 bit times
	goto	RdChg4		;036 cycles, 2.20 bit times
	btfsc	INTCON,INTF	;037 cycles, 2.26 bit times
	goto	RdChg4		;038 cycles, 2.33 bit times
	btfsc	INTCON,INTF	;039 cycles, 2.39 bit times
	goto	RdChg4		;040 cycles, 2.45 bit times
	btfsc	INTCON,INTF	;041 cycles, 2.51 bit times
	goto	RdChg3		;042 cycles, 2.57 bit times
	btfsc	INTCON,INTF	;043 cycles, 2.63 bit times
	goto	RdChg3		;044 cycles, 2.69 bit times
	btfsc	INTCON,INTF	;045 cycles, 2.75 bit times
	goto	RdChg3		;046 cycles, 2.82 bit times
	btfsc	INTCON,INTF	;047 cycles, 2.88 bit times
	goto	RdChg3		;048 cycles, 2.94 bit times
	btfsc	INTCON,INTF	;049 cycles, 3.00 bit times
	goto	RdChg3		;050 cycles, 3.06 bit times
	btfsc	INTCON,INTF	;051 cycles, 3.12 bit times
	goto	RdChg3		;052 cycles, 3.18 bit times
	btfsc	INTCON,INTF	;053 cycles, 3.24 bit times
	goto	RdChg3		;054 cycles, 3.30 bit times
	btfsc	INTCON,INTF	;055 cycles, 3.37 bit times
	goto	RdChg3		;056 cycles, 3.43 bit times
	btfsc	INTCON,INTF	;057 cycles, 3.49 bit times
	goto	RdChg3		;058 cycles, 3.55 bit times
	btfsc	INTCON,INTF	;059 cycles, 3.61 bit times
	goto	RdChg2		;060 cycles, 3.67 bit times
	btfsc	INTCON,INTF	;061 cycles, 3.73 bit times
	goto	RdChg2		;062 cycles, 3.79 bit times
	btfsc	INTCON,INTF	;063 cycles, 3.86 bit times
	goto	RdChg2		;064 cycles, 3.92 bit times
	btfsc	INTCON,INTF	;065 cycles, 3.98 bit times
	goto	RdChg2		;066 cycles, 4.04 bit times
	btfsc	INTCON,INTF	;067 cycles, 4.10 bit times
	goto	RdChg2		;068 cycles, 4.16 bit times
	btfsc	INTCON,INTF	;069 cycles, 4.22 bit times
	goto	RdChg2		;070 cycles, 4.28 bit times
	btfsc	INTCON,INTF	;071 cycles, 4.35 bit times
	goto	RdChg2		;072 cycles, 4.41 bit times
	btfsc	INTCON,INTF	;073 cycles, 4.47 bit times
	goto	RdChg2		;074 cycles, 4.53 bit times
	btfsc	INTCON,INTF	;075 cycles, 4.59 bit times
	goto	RdChg1		;076 cycles, 4.65 bit times
	btfsc	INTCON,INTF	;077 cycles, 4.71 bit times
	goto	RdChg1		;078 cycles, 4.77 bit times
	btfsc	INTCON,INTF	;079 cycles, 4.83 bit times
	goto	RdChg1		;080 cycles, 4.90 bit times
	btfsc	INTCON,INTF	;081 cycles, 4.96 bit times
	goto	RdChg1		;082 cycles, 5.02 bit times
	btfsc	INTCON,INTF	;083 cycles, 5.08 bit times
	goto	RdChg1		;084 cycles, 5.14 bit times
	btfsc	INTCON,INTF	;085 cycles, 5.20 bit times
	goto	RdChg1		;086 cycles, 5.26 bit times
	btfsc	INTCON,INTF	;087 cycles, 5.32 bit times
	goto	RdChg1		;088 cycles, 5.39 bit times
	btfsc	INTCON,INTF	;089 cycles, 5.45 bit times
	goto	RdChg1		;090 cycles, 5.51 bit times
	btfsc	INTCON,INTF	;091 cycles, 5.57 bit times
	goto	RdChg0		;092 cycles, 5.63 bit times
	btfsc	INTCON,INTF	;093 cycles, 5.69 bit times
	goto	RdChg0		;094 cycles, 5.75 bit times
	btfsc	INTCON,INTF	;095 cycles, 5.81 bit times
	goto	RdChg0		;096 cycles, 5.88 bit times
	btfsc	INTCON,INTF	;097 cycles, 5.94 bit times
	goto	RdChg0		;098 cycles, 6.00 bit times
	btfsc	INTCON,INTF	;099 cycles, 6.06 bit times
	goto	RdChg0		;100 cycles, 6.12 bit times
	btfsc	INTCON,INTF	;101 cycles, 6.18 bit times
	goto	RdChg0		;102 cycles, 6.24 bit times
	btfsc	INTCON,INTF	;103 cycles, 6.30 bit times
	goto	RdChg0		;104 cycles, 6.36 bit times
	btfsc	INTCON,INTF	;105 cycles, 6.43 bit times
	goto	RdChg0		;106 cycles, 6.49 bit times
	btfsc	GI_PORT,GI_PIN	;107 cycles, 6.55 bit times
	iorlw	B'10000000'	;108 cycles, 6.61 bit times
	movwf	INDF0		;109 cycles, 6.67 bit times
	goto	RdStart		;110 cycles, 6.73 bit times

RdChg5	iorlw	B'00100000'	;003 cycles, 0.18 bit times
	bcf	INTCON,INTF	;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfsc	INTCON,INTF	;009 cycles, 0.55 bit times
	goto	RdChg4		;010 cycles, 0.61 bit times
	btfsc	INTCON,INTF	;011 cycles, 0.67 bit times
	goto	RdChg4		;012 cycles, 0.73 bit times
	btfsc	INTCON,INTF	;013 cycles, 0.80 bit times
	goto	RdChg4		;014 cycles, 0.86 bit times
	btfsc	INTCON,INTF	;015 cycles, 0.92 bit times
	goto	RdChg4		;016 cycles, 0.98 bit times
	btfsc	INTCON,INTF	;017 cycles, 1.04 bit times
	goto	RdChg4		;018 cycles, 1.10 bit times
	btfsc	INTCON,INTF	;019 cycles, 1.16 bit times
	goto	RdChg4		;020 cycles, 1.22 bit times
	btfsc	INTCON,INTF	;021 cycles, 1.29 bit times
	goto	RdChg4		;022 cycles, 1.35 bit times
	btfsc	INTCON,INTF	;023 cycles, 1.41 bit times
	goto	RdChg4		;024 cycles, 1.47 bit times
	btfsc	INTCON,INTF	;025 cycles, 1.53 bit times
	goto	RdChg3		;026 cycles, 1.59 bit times
	btfsc	INTCON,INTF	;027 cycles, 1.65 bit times
	goto	RdChg3		;028 cycles, 1.71 bit times
	btfsc	INTCON,INTF	;029 cycles, 1.77 bit times
	goto	RdChg3		;030 cycles, 1.84 bit times
	btfsc	INTCON,INTF	;031 cycles, 1.90 bit times
	goto	RdChg3		;032 cycles, 1.96 bit times
	btfsc	INTCON,INTF	;033 cycles, 2.02 bit times
	goto	RdChg3		;034 cycles, 2.08 bit times
	btfsc	INTCON,INTF	;035 cycles, 2.14 bit times
	goto	RdChg3		;036 cycles, 2.20 bit times
	btfsc	INTCON,INTF	;037 cycles, 2.26 bit times
	goto	RdChg3		;038 cycles, 2.33 bit times
	btfsc	INTCON,INTF	;039 cycles, 2.39 bit times
	goto	RdChg3		;040 cycles, 2.45 bit times
	btfsc	INTCON,INTF	;041 cycles, 2.51 bit times
	goto	RdChg2		;042 cycles, 2.57 bit times
	btfsc	INTCON,INTF	;043 cycles, 2.63 bit times
	goto	RdChg2		;044 cycles, 2.69 bit times
	btfsc	INTCON,INTF	;045 cycles, 2.75 bit times
	goto	RdChg2		;046 cycles, 2.82 bit times
	btfsc	INTCON,INTF	;047 cycles, 2.88 bit times
	goto	RdChg2		;048 cycles, 2.94 bit times
	btfsc	INTCON,INTF	;049 cycles, 3.00 bit times
	goto	RdChg2		;050 cycles, 3.06 bit times
	btfsc	INTCON,INTF	;051 cycles, 3.12 bit times
	goto	RdChg2		;052 cycles, 3.18 bit times
	btfsc	INTCON,INTF	;053 cycles, 3.24 bit times
	goto	RdChg2		;054 cycles, 3.30 bit times
	btfsc	INTCON,INTF	;055 cycles, 3.37 bit times
	goto	RdChg2		;056 cycles, 3.43 bit times
	btfsc	INTCON,INTF	;057 cycles, 3.49 bit times
	goto	RdChg2		;058 cycles, 3.55 bit times
	btfsc	INTCON,INTF	;059 cycles, 3.61 bit times
	goto	RdChg1		;060 cycles, 3.67 bit times
	btfsc	INTCON,INTF	;061 cycles, 3.73 bit times
	goto	RdChg1		;062 cycles, 3.79 bit times
	btfsc	INTCON,INTF	;063 cycles, 3.86 bit times
	goto	RdChg1		;064 cycles, 3.92 bit times
	btfsc	INTCON,INTF	;065 cycles, 3.98 bit times
	goto	RdChg1		;066 cycles, 4.04 bit times
	btfsc	INTCON,INTF	;067 cycles, 4.10 bit times
	goto	RdChg1		;068 cycles, 4.16 bit times
	btfsc	INTCON,INTF	;069 cycles, 4.22 bit times
	goto	RdChg1		;070 cycles, 4.28 bit times
	btfsc	INTCON,INTF	;071 cycles, 4.35 bit times
	goto	RdChg1		;072 cycles, 4.41 bit times
	btfsc	INTCON,INTF	;073 cycles, 4.47 bit times
	goto	RdChg1		;074 cycles, 4.53 bit times
	btfsc	INTCON,INTF	;075 cycles, 4.59 bit times
	goto	RdChg0		;076 cycles, 4.65 bit times
	btfsc	INTCON,INTF	;077 cycles, 4.71 bit times
	goto	RdChg0		;078 cycles, 4.77 bit times
	btfsc	INTCON,INTF	;079 cycles, 4.83 bit times
	goto	RdChg0		;080 cycles, 4.90 bit times
	btfsc	INTCON,INTF	;081 cycles, 4.96 bit times
	goto	RdChg0		;082 cycles, 5.02 bit times
	btfsc	INTCON,INTF	;083 cycles, 5.08 bit times
	goto	RdChg0		;084 cycles, 5.14 bit times
	btfsc	INTCON,INTF	;085 cycles, 5.20 bit times
	goto	RdChg0		;086 cycles, 5.26 bit times
	btfsc	INTCON,INTF	;087 cycles, 5.32 bit times
	goto	RdChg0		;088 cycles, 5.39 bit times
	btfsc	INTCON,INTF	;089 cycles, 5.45 bit times
	goto	RdChg0		;090 cycles, 5.51 bit times
	btfsc	GI_PORT,GI_PIN	;091 cycles, 5.57 bit times
	iorlw	B'10000000'	;092 cycles, 5.63 bit times
	movwf	INDF0		;093 cycles, 5.69 bit times
	goto	RdStart		;094 cycles, 5.75 bit times

RdChg4	iorlw	B'00010000'	;003 cycles, 0.18 bit times
	bcf	INTCON,INTF	;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfsc	INTCON,INTF	;009 cycles, 0.55 bit times
	goto	RdChg3		;010 cycles, 0.61 bit times
	btfsc	INTCON,INTF	;011 cycles, 0.67 bit times
	goto	RdChg3		;012 cycles, 0.73 bit times
	btfsc	INTCON,INTF	;013 cycles, 0.80 bit times
	goto	RdChg3		;014 cycles, 0.86 bit times
	btfsc	INTCON,INTF	;015 cycles, 0.92 bit times
	goto	RdChg3		;016 cycles, 0.98 bit times
	btfsc	INTCON,INTF	;017 cycles, 1.04 bit times
	goto	RdChg3		;018 cycles, 1.10 bit times
	btfsc	INTCON,INTF	;019 cycles, 1.16 bit times
	goto	RdChg3		;020 cycles, 1.22 bit times
	btfsc	INTCON,INTF	;021 cycles, 1.29 bit times
	goto	RdChg3		;022 cycles, 1.35 bit times
	btfsc	INTCON,INTF	;023 cycles, 1.41 bit times
	goto	RdChg3		;024 cycles, 1.47 bit times
	btfsc	INTCON,INTF	;025 cycles, 1.53 bit times
	goto	RdChg2		;026 cycles, 1.59 bit times
	btfsc	INTCON,INTF	;027 cycles, 1.65 bit times
	goto	RdChg2		;028 cycles, 1.71 bit times
	btfsc	INTCON,INTF	;029 cycles, 1.77 bit times
	goto	RdChg2		;030 cycles, 1.84 bit times
	btfsc	INTCON,INTF	;031 cycles, 1.90 bit times
	goto	RdChg2		;032 cycles, 1.96 bit times
	btfsc	INTCON,INTF	;033 cycles, 2.02 bit times
	goto	RdChg2		;034 cycles, 2.08 bit times
	btfsc	INTCON,INTF	;035 cycles, 2.14 bit times
	goto	RdChg2		;036 cycles, 2.20 bit times
	btfsc	INTCON,INTF	;037 cycles, 2.26 bit times
	goto	RdChg2		;038 cycles, 2.33 bit times
	btfsc	INTCON,INTF	;039 cycles, 2.39 bit times
	goto	RdChg2		;040 cycles, 2.45 bit times
	btfsc	INTCON,INTF	;041 cycles, 2.51 bit times
	goto	RdChg1		;042 cycles, 2.57 bit times
	btfsc	INTCON,INTF	;043 cycles, 2.63 bit times
	goto	RdChg1		;044 cycles, 2.69 bit times
	btfsc	INTCON,INTF	;045 cycles, 2.75 bit times
	goto	RdChg1		;046 cycles, 2.82 bit times
	btfsc	INTCON,INTF	;047 cycles, 2.88 bit times
	goto	RdChg1		;048 cycles, 2.94 bit times
	btfsc	INTCON,INTF	;049 cycles, 3.00 bit times
	goto	RdChg1		;050 cycles, 3.06 bit times
	btfsc	INTCON,INTF	;051 cycles, 3.12 bit times
	goto	RdChg1		;052 cycles, 3.18 bit times
	btfsc	INTCON,INTF	;053 cycles, 3.24 bit times
	goto	RdChg1		;054 cycles, 3.30 bit times
	btfsc	INTCON,INTF	;055 cycles, 3.37 bit times
	goto	RdChg1		;056 cycles, 3.43 bit times
	btfsc	INTCON,INTF	;057 cycles, 3.49 bit times
	goto	RdChg1		;058 cycles, 3.55 bit times
	btfsc	INTCON,INTF	;059 cycles, 3.61 bit times
	goto	RdChg0		;060 cycles, 3.67 bit times
	btfsc	INTCON,INTF	;061 cycles, 3.73 bit times
	goto	RdChg0		;062 cycles, 3.79 bit times
	btfsc	INTCON,INTF	;063 cycles, 3.86 bit times
	goto	RdChg0		;064 cycles, 3.92 bit times
	btfsc	INTCON,INTF	;065 cycles, 3.98 bit times
	goto	RdChg0		;066 cycles, 4.04 bit times
	btfsc	INTCON,INTF	;067 cycles, 4.10 bit times
	goto	RdChg0		;068 cycles, 4.16 bit times
	btfsc	INTCON,INTF	;069 cycles, 4.22 bit times
	goto	RdChg0		;070 cycles, 4.28 bit times
	btfsc	INTCON,INTF	;071 cycles, 4.35 bit times
	goto	RdChg0		;072 cycles, 4.41 bit times
	btfsc	INTCON,INTF	;073 cycles, 4.47 bit times
	goto	RdChg0		;074 cycles, 4.53 bit times
	btfsc	GI_PORT,GI_PIN	;075 cycles, 4.59 bit times
	iorlw	B'10000000'	;076 cycles, 4.65 bit times
	movwf	INDF0		;077 cycles, 4.71 bit times
	goto	RdStart		;078 cycles, 4.77 bit times

RdChg3	iorlw	B'00001000'	;003 cycles, 0.18 bit times
	bcf	INTCON,INTF	;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfsc	INTCON,INTF	;009 cycles, 0.55 bit times
	goto	RdChg2		;010 cycles, 0.61 bit times
	btfsc	INTCON,INTF	;011 cycles, 0.67 bit times
	goto	RdChg2		;012 cycles, 0.73 bit times
	btfsc	INTCON,INTF	;013 cycles, 0.80 bit times
	goto	RdChg2		;014 cycles, 0.86 bit times
	btfsc	INTCON,INTF	;015 cycles, 0.92 bit times
	goto	RdChg2		;016 cycles, 0.98 bit times
	btfsc	INTCON,INTF	;017 cycles, 1.04 bit times
	goto	RdChg2		;018 cycles, 1.10 bit times
	btfsc	INTCON,INTF	;019 cycles, 1.16 bit times
	goto	RdChg2		;020 cycles, 1.22 bit times
	btfsc	INTCON,INTF	;021 cycles, 1.29 bit times
	goto	RdChg2		;022 cycles, 1.35 bit times
	btfsc	INTCON,INTF	;023 cycles, 1.41 bit times
	goto	RdChg2		;024 cycles, 1.47 bit times
	btfsc	INTCON,INTF	;025 cycles, 1.53 bit times
	goto	RdChg1		;026 cycles, 1.59 bit times
	btfsc	INTCON,INTF	;027 cycles, 1.65 bit times
	goto	RdChg1		;028 cycles, 1.71 bit times
	btfsc	INTCON,INTF	;029 cycles, 1.77 bit times
	goto	RdChg1		;030 cycles, 1.84 bit times
	btfsc	INTCON,INTF	;031 cycles, 1.90 bit times
	goto	RdChg1		;032 cycles, 1.96 bit times
	btfsc	INTCON,INTF	;033 cycles, 2.02 bit times
	goto	RdChg1		;034 cycles, 2.08 bit times
	btfsc	INTCON,INTF	;035 cycles, 2.14 bit times
	goto	RdChg1		;036 cycles, 2.20 bit times
	btfsc	INTCON,INTF	;037 cycles, 2.26 bit times
	goto	RdChg1		;038 cycles, 2.33 bit times
	btfsc	INTCON,INTF	;039 cycles, 2.39 bit times
	goto	RdChg1		;040 cycles, 2.45 bit times
	btfsc	INTCON,INTF	;041 cycles, 2.51 bit times
	goto	RdChg0		;042 cycles, 2.57 bit times
	btfsc	INTCON,INTF	;043 cycles, 2.63 bit times
	goto	RdChg0		;044 cycles, 2.69 bit times
	btfsc	INTCON,INTF	;045 cycles, 2.75 bit times
	goto	RdChg0		;046 cycles, 2.82 bit times
	btfsc	INTCON,INTF	;047 cycles, 2.88 bit times
	goto	RdChg0		;048 cycles, 2.94 bit times
	btfsc	INTCON,INTF	;049 cycles, 3.00 bit times
	goto	RdChg0		;050 cycles, 3.06 bit times
	btfsc	INTCON,INTF	;051 cycles, 3.12 bit times
	goto	RdChg0		;052 cycles, 3.18 bit times
	btfsc	INTCON,INTF	;053 cycles, 3.24 bit times
	goto	RdChg0		;054 cycles, 3.30 bit times
	btfsc	INTCON,INTF	;055 cycles, 3.37 bit times
	goto	RdChg0		;056 cycles, 3.43 bit times
	btfsc	INTCON,INTF	;057 cycles, 3.49 bit times
	goto	RdChg0		;058 cycles, 3.55 bit times
	btfsc	GI_PORT,GI_PIN	;059 cycles, 3.61 bit times
	iorlw	B'10000000'	;060 cycles, 3.67 bit times
	movwf	INDF0		;061 cycles, 3.73 bit times
	goto	RdStart		;062 cycles, 3.79 bit times

RdChg2	iorlw	B'00000100'	;003 cycles, 0.18 bit times
	bcf	INTCON,INTF	;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfsc	INTCON,INTF	;009 cycles, 0.55 bit times
	goto	RdChg1		;010 cycles, 0.61 bit times
	btfsc	INTCON,INTF	;011 cycles, 0.67 bit times
	goto	RdChg1		;012 cycles, 0.73 bit times
	btfsc	INTCON,INTF	;013 cycles, 0.80 bit times
	goto	RdChg1		;014 cycles, 0.86 bit times
	btfsc	INTCON,INTF	;015 cycles, 0.92 bit times
	goto	RdChg1		;016 cycles, 0.98 bit times
	btfsc	INTCON,INTF	;017 cycles, 1.04 bit times
	goto	RdChg1		;018 cycles, 1.10 bit times
	btfsc	INTCON,INTF	;019 cycles, 1.16 bit times
	goto	RdChg1		;020 cycles, 1.22 bit times
	btfsc	INTCON,INTF	;021 cycles, 1.29 bit times
	goto	RdChg1		;022 cycles, 1.35 bit times
	btfsc	INTCON,INTF	;023 cycles, 1.41 bit times
	goto	RdChg1		;024 cycles, 1.47 bit times
	btfsc	INTCON,INTF	;025 cycles, 1.53 bit times
	goto	RdChg0		;026 cycles, 1.59 bit times
	btfsc	INTCON,INTF	;027 cycles, 1.65 bit times
	goto	RdChg0		;028 cycles, 1.71 bit times
	btfsc	INTCON,INTF	;029 cycles, 1.77 bit times
	goto	RdChg0		;030 cycles, 1.84 bit times
	btfsc	INTCON,INTF	;031 cycles, 1.90 bit times
	goto	RdChg0		;032 cycles, 1.96 bit times
	btfsc	INTCON,INTF	;033 cycles, 2.02 bit times
	goto	RdChg0		;034 cycles, 2.08 bit times
	btfsc	INTCON,INTF	;035 cycles, 2.14 bit times
	goto	RdChg0		;036 cycles, 2.20 bit times
	btfsc	INTCON,INTF	;037 cycles, 2.26 bit times
	goto	RdChg0		;038 cycles, 2.33 bit times
	btfsc	INTCON,INTF	;039 cycles, 2.39 bit times
	goto	RdChg0		;040 cycles, 2.45 bit times
	btfsc	GI_PORT,GI_PIN	;041 cycles, 2.51 bit times
	iorlw	B'10000000'	;042 cycles, 2.57 bit times
	movwf	INDF0		;043 cycles, 2.63 bit times
	goto	RdStart		;044 cycles, 2.69 bit times

RdChg1	iorlw	B'00000010'	;003 cycles, 0.18 bit times
	bcf	INTCON,INTF	;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfsc	INTCON,INTF	;009 cycles, 0.55 bit times
	goto	RdChg0		;010 cycles, 0.61 bit times
	btfsc	INTCON,INTF	;011 cycles, 0.67 bit times
	goto	RdChg0		;012 cycles, 0.73 bit times
	btfsc	INTCON,INTF	;013 cycles, 0.80 bit times
	goto	RdChg0		;014 cycles, 0.86 bit times
	btfsc	INTCON,INTF	;015 cycles, 0.92 bit times
	goto	RdChg0		;016 cycles, 0.98 bit times
	btfsc	INTCON,INTF	;017 cycles, 1.04 bit times
	goto	RdChg0		;018 cycles, 1.10 bit times
	btfsc	INTCON,INTF	;019 cycles, 1.16 bit times
	goto	RdChg0		;020 cycles, 1.22 bit times
	btfsc	INTCON,INTF	;021 cycles, 1.29 bit times
	goto	RdChg0		;022 cycles, 1.35 bit times
	btfsc	INTCON,INTF	;023 cycles, 1.41 bit times
	goto	RdChg0		;024 cycles, 1.47 bit times
	btfsc	GI_PORT,GI_PIN	;025 cycles, 1.53 bit times
	iorlw	B'10000000'	;026 cycles, 1.59 bit times
	movwf	INDF0		;027 cycles, 1.65 bit times
	goto	RdStart		;028 cycles, 1.71 bit times

RdChg0	iorlw	B'00000001'	;003 cycles, 0.18 bit times
	bcf	INTCON,INTF	;004 cycles, 0.24 bit times
	btfsc	GI_PORT,GI_PIN	;005 cycles, 0.31 bit times
	iorlw	B'10000000'	;006 cycles, 0.37 bit times
	movwf	INDF0		;007 cycles, 0.43 bit times
	goto	RdStart		;008 cycles, 0.49 bit times


;;; WR GCR Receiver ;;;

RecvWr
	;fall through

WrSt0	btfss	WR_PORT,WR_PIN	;Signal starts at zero, wait until transition
	bra	$-1		; to one, this is MSB (always 1) of byte
	movlw	B'00000000'	;003 cycles, 0.18 bit times
	nop			;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfss	WR_PORT,WR_PIN	;009 cycles, 0.55 bit times
	goto	WrTo0_6		;010 cycles, 0.61 bit times
	btfss	WR_PORT,WR_PIN	;011 cycles, 0.67 bit times
	goto	WrTo0_6		;012 cycles, 0.73 bit times
	btfss	WR_PORT,WR_PIN	;013 cycles, 0.80 bit times
	goto	WrTo0_6		;014 cycles, 0.86 bit times
	btfss	WR_PORT,WR_PIN	;015 cycles, 0.92 bit times
	goto	WrTo0_6		;016 cycles, 0.98 bit times
	btfss	WR_PORT,WR_PIN	;017 cycles, 1.04 bit times
	goto	WrTo0_6		;018 cycles, 1.10 bit times
	btfss	WR_PORT,WR_PIN	;019 cycles, 1.16 bit times
	goto	WrTo0_6		;020 cycles, 1.22 bit times
	btfss	WR_PORT,WR_PIN	;021 cycles, 1.29 bit times
	goto	WrTo0_6		;022 cycles, 1.35 bit times
	btfss	WR_PORT,WR_PIN	;023 cycles, 1.41 bit times
	goto	WrTo0_6		;024 cycles, 1.47 bit times
	btfss	WR_PORT,WR_PIN	;025 cycles, 1.53 bit times
	goto	WrTo0_5		;026 cycles, 1.59 bit times
	btfss	WR_PORT,WR_PIN	;027 cycles, 1.65 bit times
	goto	WrTo0_5		;028 cycles, 1.71 bit times
	btfss	WR_PORT,WR_PIN	;029 cycles, 1.77 bit times
	goto	WrTo0_5		;030 cycles, 1.84 bit times
	btfss	WR_PORT,WR_PIN	;031 cycles, 1.90 bit times
	goto	WrTo0_5		;032 cycles, 1.96 bit times
	btfss	WR_PORT,WR_PIN	;033 cycles, 2.02 bit times
	goto	WrTo0_5		;034 cycles, 2.08 bit times
	btfss	WR_PORT,WR_PIN	;035 cycles, 2.14 bit times
	goto	WrTo0_5		;036 cycles, 2.20 bit times
	btfss	WR_PORT,WR_PIN	;037 cycles, 2.26 bit times
	goto	WrTo0_5		;038 cycles, 2.33 bit times
	btfss	WR_PORT,WR_PIN	;039 cycles, 2.39 bit times
	goto	WrTo0_5		;040 cycles, 2.45 bit times
	btfss	WR_PORT,WR_PIN	;041 cycles, 2.51 bit times
	goto	WrTo0_4		;042 cycles, 2.57 bit times
	btfss	WR_PORT,WR_PIN	;043 cycles, 2.63 bit times
	goto	WrTo0_4		;044 cycles, 2.69 bit times
	btfss	WR_PORT,WR_PIN	;045 cycles, 2.75 bit times
	goto	WrTo0_4		;046 cycles, 2.82 bit times
	btfss	WR_PORT,WR_PIN	;047 cycles, 2.88 bit times
	goto	WrTo0_4		;048 cycles, 2.94 bit times
	btfss	WR_PORT,WR_PIN	;049 cycles, 3.00 bit times
	goto	WrTo0_4		;050 cycles, 3.06 bit times
	btfss	WR_PORT,WR_PIN	;051 cycles, 3.12 bit times
	goto	WrTo0_4		;052 cycles, 3.18 bit times
	btfss	WR_PORT,WR_PIN	;053 cycles, 3.24 bit times
	goto	WrTo0_4		;054 cycles, 3.30 bit times
	btfss	WR_PORT,WR_PIN	;055 cycles, 3.37 bit times
	goto	WrTo0_4		;056 cycles, 3.43 bit times
	btfss	WR_PORT,WR_PIN	;057 cycles, 3.49 bit times
	goto	WrTo0_4		;058 cycles, 3.55 bit times
	btfss	WR_PORT,WR_PIN	;059 cycles, 3.61 bit times
	goto	WrTo0_3		;060 cycles, 3.67 bit times
	btfss	WR_PORT,WR_PIN	;061 cycles, 3.73 bit times
	goto	WrTo0_3		;062 cycles, 3.79 bit times
	btfss	WR_PORT,WR_PIN	;063 cycles, 3.86 bit times
	goto	WrTo0_3		;064 cycles, 3.92 bit times
	btfss	WR_PORT,WR_PIN	;065 cycles, 3.98 bit times
	goto	WrTo0_3		;066 cycles, 4.04 bit times
	btfss	WR_PORT,WR_PIN	;067 cycles, 4.10 bit times
	goto	WrTo0_3		;068 cycles, 4.16 bit times
	btfss	WR_PORT,WR_PIN	;069 cycles, 4.22 bit times
	goto	WrTo0_3		;070 cycles, 4.28 bit times
	btfss	WR_PORT,WR_PIN	;071 cycles, 4.35 bit times
	goto	WrTo0_3		;072 cycles, 4.41 bit times
	btfss	WR_PORT,WR_PIN	;073 cycles, 4.47 bit times
	goto	WrTo0_3		;074 cycles, 4.53 bit times
	btfss	WR_PORT,WR_PIN	;075 cycles, 4.59 bit times
	goto	WrTo0_2		;076 cycles, 4.65 bit times
	btfss	WR_PORT,WR_PIN	;077 cycles, 4.71 bit times
	goto	WrTo0_2		;078 cycles, 4.77 bit times
	btfss	WR_PORT,WR_PIN	;079 cycles, 4.83 bit times
	goto	WrTo0_2		;080 cycles, 4.90 bit times
	btfss	WR_PORT,WR_PIN	;081 cycles, 4.96 bit times
	goto	WrTo0_2		;082 cycles, 5.02 bit times
	btfss	WR_PORT,WR_PIN	;083 cycles, 5.08 bit times
	goto	WrTo0_2		;084 cycles, 5.14 bit times
	btfss	WR_PORT,WR_PIN	;085 cycles, 5.20 bit times
	goto	WrTo0_2		;086 cycles, 5.26 bit times
	btfss	WR_PORT,WR_PIN	;087 cycles, 5.32 bit times
	goto	WrTo0_2		;088 cycles, 5.39 bit times
	btfss	WR_PORT,WR_PIN	;089 cycles, 5.45 bit times
	goto	WrTo0_2		;090 cycles, 5.51 bit times
	btfss	WR_PORT,WR_PIN	;091 cycles, 5.57 bit times
	goto	WrTo0_1		;092 cycles, 5.63 bit times
	btfss	WR_PORT,WR_PIN	;093 cycles, 5.69 bit times
	goto	WrTo0_1		;094 cycles, 5.75 bit times
	btfss	WR_PORT,WR_PIN	;095 cycles, 5.81 bit times
	goto	WrTo0_1		;096 cycles, 5.88 bit times
	btfss	WR_PORT,WR_PIN	;097 cycles, 5.94 bit times
	goto	WrTo0_1		;098 cycles, 6.00 bit times
	btfss	WR_PORT,WR_PIN	;099 cycles, 6.06 bit times
	goto	WrTo0_1		;100 cycles, 6.12 bit times
	btfss	WR_PORT,WR_PIN	;101 cycles, 6.18 bit times
	goto	WrTo0_1		;102 cycles, 6.24 bit times
	btfss	WR_PORT,WR_PIN	;103 cycles, 6.30 bit times
	goto	WrTo0_1		;104 cycles, 6.36 bit times
	btfss	WR_PORT,WR_PIN	;105 cycles, 6.43 bit times
	goto	WrTo0_1		;106 cycles, 6.49 bit times
	btfss	WR_PORT,WR_PIN	;107 cycles, 6.55 bit times
	goto	WrTo0_0		;108 cycles, 6.61 bit times
	btfss	WR_PORT,WR_PIN	;109 cycles, 6.67 bit times
	goto	WrTo0_0		;110 cycles, 6.73 bit times
	btfss	WR_PORT,WR_PIN	;111 cycles, 6.79 bit times
	goto	WrTo0_0		;112 cycles, 6.85 bit times
	btfss	WR_PORT,WR_PIN	;113 cycles, 6.92 bit times
	goto	WrTo0_0		;114 cycles, 6.98 bit times
	btfss	WR_PORT,WR_PIN	;115 cycles, 7.04 bit times
	goto	WrTo0_0		;116 cycles, 7.10 bit times
	btfss	WR_PORT,WR_PIN	;117 cycles, 7.16 bit times
	goto	WrTo0_0		;118 cycles, 7.22 bit times
	btfss	WR_PORT,WR_PIN	;119 cycles, 7.28 bit times
	goto	WrTo0_0		;120 cycles, 7.34 bit times
	btfss	WR_PORT,WR_PIN	;121 cycles, 7.40 bit times
	goto	WrTo0_0		;122 cycles, 7.47 bit times
	btfsc	GI_PORT,GI_PIN	;123 cycles, 7.53 bit times
	iorlw	B'10000000'	;124 cycles, 7.59 bit times
	movwf	INDF0		;125 cycles, 7.65 bit times
	goto	WrSt1		;126 cycles, 7.71 bit times

WrTo1_6	iorlw	B'01000000'	;003 cycles, 0.18 bit times
	nop			;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfss	WR_PORT,WR_PIN	;009 cycles, 0.55 bit times
	goto	WrTo0_5		;010 cycles, 0.61 bit times
	btfss	WR_PORT,WR_PIN	;011 cycles, 0.67 bit times
	goto	WrTo0_5		;012 cycles, 0.73 bit times
	btfss	WR_PORT,WR_PIN	;013 cycles, 0.80 bit times
	goto	WrTo0_5		;014 cycles, 0.86 bit times
	btfss	WR_PORT,WR_PIN	;015 cycles, 0.92 bit times
	goto	WrTo0_5		;016 cycles, 0.98 bit times
	btfss	WR_PORT,WR_PIN	;017 cycles, 1.04 bit times
	goto	WrTo0_5		;018 cycles, 1.10 bit times
	btfss	WR_PORT,WR_PIN	;019 cycles, 1.16 bit times
	goto	WrTo0_5		;020 cycles, 1.22 bit times
	btfss	WR_PORT,WR_PIN	;021 cycles, 1.29 bit times
	goto	WrTo0_5		;022 cycles, 1.35 bit times
	btfss	WR_PORT,WR_PIN	;023 cycles, 1.41 bit times
	goto	WrTo0_5		;024 cycles, 1.47 bit times
	btfss	WR_PORT,WR_PIN	;025 cycles, 1.53 bit times
	goto	WrTo0_4		;026 cycles, 1.59 bit times
	btfss	WR_PORT,WR_PIN	;027 cycles, 1.65 bit times
	goto	WrTo0_4		;028 cycles, 1.71 bit times
	btfss	WR_PORT,WR_PIN	;029 cycles, 1.77 bit times
	goto	WrTo0_4		;030 cycles, 1.84 bit times
	btfss	WR_PORT,WR_PIN	;031 cycles, 1.90 bit times
	goto	WrTo0_4		;032 cycles, 1.96 bit times
	btfss	WR_PORT,WR_PIN	;033 cycles, 2.02 bit times
	goto	WrTo0_4		;034 cycles, 2.08 bit times
	btfss	WR_PORT,WR_PIN	;035 cycles, 2.14 bit times
	goto	WrTo0_4		;036 cycles, 2.20 bit times
	btfss	WR_PORT,WR_PIN	;037 cycles, 2.26 bit times
	goto	WrTo0_4		;038 cycles, 2.33 bit times
	btfss	WR_PORT,WR_PIN	;039 cycles, 2.39 bit times
	goto	WrTo0_4		;040 cycles, 2.45 bit times
	btfss	WR_PORT,WR_PIN	;041 cycles, 2.51 bit times
	goto	WrTo0_3		;042 cycles, 2.57 bit times
	btfss	WR_PORT,WR_PIN	;043 cycles, 2.63 bit times
	goto	WrTo0_3		;044 cycles, 2.69 bit times
	btfss	WR_PORT,WR_PIN	;045 cycles, 2.75 bit times
	goto	WrTo0_3		;046 cycles, 2.82 bit times
	btfss	WR_PORT,WR_PIN	;047 cycles, 2.88 bit times
	goto	WrTo0_3		;048 cycles, 2.94 bit times
	btfss	WR_PORT,WR_PIN	;049 cycles, 3.00 bit times
	goto	WrTo0_3		;050 cycles, 3.06 bit times
	btfss	WR_PORT,WR_PIN	;051 cycles, 3.12 bit times
	goto	WrTo0_3		;052 cycles, 3.18 bit times
	btfss	WR_PORT,WR_PIN	;053 cycles, 3.24 bit times
	goto	WrTo0_3		;054 cycles, 3.30 bit times
	btfss	WR_PORT,WR_PIN	;055 cycles, 3.37 bit times
	goto	WrTo0_3		;056 cycles, 3.43 bit times
	btfss	WR_PORT,WR_PIN	;057 cycles, 3.49 bit times
	goto	WrTo0_3		;058 cycles, 3.55 bit times
	btfss	WR_PORT,WR_PIN	;059 cycles, 3.61 bit times
	goto	WrTo0_2		;060 cycles, 3.67 bit times
	btfss	WR_PORT,WR_PIN	;061 cycles, 3.73 bit times
	goto	WrTo0_2		;062 cycles, 3.79 bit times
	btfss	WR_PORT,WR_PIN	;063 cycles, 3.86 bit times
	goto	WrTo0_2		;064 cycles, 3.92 bit times
	btfss	WR_PORT,WR_PIN	;065 cycles, 3.98 bit times
	goto	WrTo0_2		;066 cycles, 4.04 bit times
	btfss	WR_PORT,WR_PIN	;067 cycles, 4.10 bit times
	goto	WrTo0_2		;068 cycles, 4.16 bit times
	btfss	WR_PORT,WR_PIN	;069 cycles, 4.22 bit times
	goto	WrTo0_2		;070 cycles, 4.28 bit times
	btfss	WR_PORT,WR_PIN	;071 cycles, 4.35 bit times
	goto	WrTo0_2		;072 cycles, 4.41 bit times
	btfss	WR_PORT,WR_PIN	;073 cycles, 4.47 bit times
	goto	WrTo0_2		;074 cycles, 4.53 bit times
	btfss	WR_PORT,WR_PIN	;075 cycles, 4.59 bit times
	goto	WrTo0_1		;076 cycles, 4.65 bit times
	btfss	WR_PORT,WR_PIN	;077 cycles, 4.71 bit times
	goto	WrTo0_1		;078 cycles, 4.77 bit times
	btfss	WR_PORT,WR_PIN	;079 cycles, 4.83 bit times
	goto	WrTo0_1		;080 cycles, 4.90 bit times
	btfss	WR_PORT,WR_PIN	;081 cycles, 4.96 bit times
	goto	WrTo0_1		;082 cycles, 5.02 bit times
	btfss	WR_PORT,WR_PIN	;083 cycles, 5.08 bit times
	goto	WrTo0_1		;084 cycles, 5.14 bit times
	btfss	WR_PORT,WR_PIN	;085 cycles, 5.20 bit times
	goto	WrTo0_1		;086 cycles, 5.26 bit times
	btfss	WR_PORT,WR_PIN	;087 cycles, 5.32 bit times
	goto	WrTo0_1		;088 cycles, 5.39 bit times
	btfss	WR_PORT,WR_PIN	;089 cycles, 5.45 bit times
	goto	WrTo0_1		;090 cycles, 5.51 bit times
	btfss	WR_PORT,WR_PIN	;091 cycles, 5.57 bit times
	goto	WrTo0_0		;092 cycles, 5.63 bit times
	btfss	WR_PORT,WR_PIN	;093 cycles, 5.69 bit times
	goto	WrTo0_0		;094 cycles, 5.75 bit times
	btfss	WR_PORT,WR_PIN	;095 cycles, 5.81 bit times
	goto	WrTo0_0		;096 cycles, 5.88 bit times
	btfss	WR_PORT,WR_PIN	;097 cycles, 5.94 bit times
	goto	WrTo0_0		;098 cycles, 6.00 bit times
	btfss	WR_PORT,WR_PIN	;099 cycles, 6.06 bit times
	goto	WrTo0_0		;100 cycles, 6.12 bit times
	btfss	WR_PORT,WR_PIN	;101 cycles, 6.18 bit times
	goto	WrTo0_0		;102 cycles, 6.24 bit times
	btfss	WR_PORT,WR_PIN	;103 cycles, 6.30 bit times
	goto	WrTo0_0		;104 cycles, 6.36 bit times
	btfss	WR_PORT,WR_PIN	;105 cycles, 6.43 bit times
	goto	WrTo0_0		;106 cycles, 6.49 bit times
	btfsc	GI_PORT,GI_PIN	;107 cycles, 6.55 bit times
	iorlw	B'10000000'	;108 cycles, 6.61 bit times
	movwf	INDF0		;109 cycles, 6.67 bit times
	goto	WrSt1		;110 cycles, 6.73 bit times

WrTo1_5	iorlw	B'00100000'	;003 cycles, 0.18 bit times
	nop			;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfss	WR_PORT,WR_PIN	;009 cycles, 0.55 bit times
	goto	WrTo0_4		;010 cycles, 0.61 bit times
	btfss	WR_PORT,WR_PIN	;011 cycles, 0.67 bit times
	goto	WrTo0_4		;012 cycles, 0.73 bit times
	btfss	WR_PORT,WR_PIN	;013 cycles, 0.80 bit times
	goto	WrTo0_4		;014 cycles, 0.86 bit times
	btfss	WR_PORT,WR_PIN	;015 cycles, 0.92 bit times
	goto	WrTo0_4		;016 cycles, 0.98 bit times
	btfss	WR_PORT,WR_PIN	;017 cycles, 1.04 bit times
	goto	WrTo0_4		;018 cycles, 1.10 bit times
	btfss	WR_PORT,WR_PIN	;019 cycles, 1.16 bit times
	goto	WrTo0_4		;020 cycles, 1.22 bit times
	btfss	WR_PORT,WR_PIN	;021 cycles, 1.29 bit times
	goto	WrTo0_4		;022 cycles, 1.35 bit times
	btfss	WR_PORT,WR_PIN	;023 cycles, 1.41 bit times
	goto	WrTo0_4		;024 cycles, 1.47 bit times
	btfss	WR_PORT,WR_PIN	;025 cycles, 1.53 bit times
	goto	WrTo0_3		;026 cycles, 1.59 bit times
	btfss	WR_PORT,WR_PIN	;027 cycles, 1.65 bit times
	goto	WrTo0_3		;028 cycles, 1.71 bit times
	btfss	WR_PORT,WR_PIN	;029 cycles, 1.77 bit times
	goto	WrTo0_3		;030 cycles, 1.84 bit times
	btfss	WR_PORT,WR_PIN	;031 cycles, 1.90 bit times
	goto	WrTo0_3		;032 cycles, 1.96 bit times
	btfss	WR_PORT,WR_PIN	;033 cycles, 2.02 bit times
	goto	WrTo0_3		;034 cycles, 2.08 bit times
	btfss	WR_PORT,WR_PIN	;035 cycles, 2.14 bit times
	goto	WrTo0_3		;036 cycles, 2.20 bit times
	btfss	WR_PORT,WR_PIN	;037 cycles, 2.26 bit times
	goto	WrTo0_3		;038 cycles, 2.33 bit times
	btfss	WR_PORT,WR_PIN	;039 cycles, 2.39 bit times
	goto	WrTo0_3		;040 cycles, 2.45 bit times
	btfss	WR_PORT,WR_PIN	;041 cycles, 2.51 bit times
	goto	WrTo0_2		;042 cycles, 2.57 bit times
	btfss	WR_PORT,WR_PIN	;043 cycles, 2.63 bit times
	goto	WrTo0_2		;044 cycles, 2.69 bit times
	btfss	WR_PORT,WR_PIN	;045 cycles, 2.75 bit times
	goto	WrTo0_2		;046 cycles, 2.82 bit times
	btfss	WR_PORT,WR_PIN	;047 cycles, 2.88 bit times
	goto	WrTo0_2		;048 cycles, 2.94 bit times
	btfss	WR_PORT,WR_PIN	;049 cycles, 3.00 bit times
	goto	WrTo0_2		;050 cycles, 3.06 bit times
	btfss	WR_PORT,WR_PIN	;051 cycles, 3.12 bit times
	goto	WrTo0_2		;052 cycles, 3.18 bit times
	btfss	WR_PORT,WR_PIN	;053 cycles, 3.24 bit times
	goto	WrTo0_2		;054 cycles, 3.30 bit times
	btfss	WR_PORT,WR_PIN	;055 cycles, 3.37 bit times
	goto	WrTo0_2		;056 cycles, 3.43 bit times
	btfss	WR_PORT,WR_PIN	;057 cycles, 3.49 bit times
	goto	WrTo0_2		;058 cycles, 3.55 bit times
	btfss	WR_PORT,WR_PIN	;059 cycles, 3.61 bit times
	goto	WrTo0_1		;060 cycles, 3.67 bit times
	btfss	WR_PORT,WR_PIN	;061 cycles, 3.73 bit times
	goto	WrTo0_1		;062 cycles, 3.79 bit times
	btfss	WR_PORT,WR_PIN	;063 cycles, 3.86 bit times
	goto	WrTo0_1		;064 cycles, 3.92 bit times
	btfss	WR_PORT,WR_PIN	;065 cycles, 3.98 bit times
	goto	WrTo0_1		;066 cycles, 4.04 bit times
	btfss	WR_PORT,WR_PIN	;067 cycles, 4.10 bit times
	goto	WrTo0_1		;068 cycles, 4.16 bit times
	btfss	WR_PORT,WR_PIN	;069 cycles, 4.22 bit times
	goto	WrTo0_1		;070 cycles, 4.28 bit times
	btfss	WR_PORT,WR_PIN	;071 cycles, 4.35 bit times
	goto	WrTo0_1		;072 cycles, 4.41 bit times
	btfss	WR_PORT,WR_PIN	;073 cycles, 4.47 bit times
	goto	WrTo0_1		;074 cycles, 4.53 bit times
	btfss	WR_PORT,WR_PIN	;075 cycles, 4.59 bit times
	goto	WrTo0_0		;076 cycles, 4.65 bit times
	btfss	WR_PORT,WR_PIN	;077 cycles, 4.71 bit times
	goto	WrTo0_0		;078 cycles, 4.77 bit times
	btfss	WR_PORT,WR_PIN	;079 cycles, 4.83 bit times
	goto	WrTo0_0		;080 cycles, 4.90 bit times
	btfss	WR_PORT,WR_PIN	;081 cycles, 4.96 bit times
	goto	WrTo0_0		;082 cycles, 5.02 bit times
	btfss	WR_PORT,WR_PIN	;083 cycles, 5.08 bit times
	goto	WrTo0_0		;084 cycles, 5.14 bit times
	btfss	WR_PORT,WR_PIN	;085 cycles, 5.20 bit times
	goto	WrTo0_0		;086 cycles, 5.26 bit times
	btfss	WR_PORT,WR_PIN	;087 cycles, 5.32 bit times
	goto	WrTo0_0		;088 cycles, 5.39 bit times
	btfss	WR_PORT,WR_PIN	;089 cycles, 5.45 bit times
	goto	WrTo0_0		;090 cycles, 5.51 bit times
	btfsc	GI_PORT,GI_PIN	;091 cycles, 5.57 bit times
	iorlw	B'10000000'	;092 cycles, 5.63 bit times
	movwf	INDF0		;093 cycles, 5.69 bit times
	goto	WrSt1		;094 cycles, 5.75 bit times

WrTo1_4	iorlw	B'00010000'	;003 cycles, 0.18 bit times
	nop			;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfss	WR_PORT,WR_PIN	;009 cycles, 0.55 bit times
	goto	WrTo0_3		;010 cycles, 0.61 bit times
	btfss	WR_PORT,WR_PIN	;011 cycles, 0.67 bit times
	goto	WrTo0_3		;012 cycles, 0.73 bit times
	btfss	WR_PORT,WR_PIN	;013 cycles, 0.80 bit times
	goto	WrTo0_3		;014 cycles, 0.86 bit times
	btfss	WR_PORT,WR_PIN	;015 cycles, 0.92 bit times
	goto	WrTo0_3		;016 cycles, 0.98 bit times
	btfss	WR_PORT,WR_PIN	;017 cycles, 1.04 bit times
	goto	WrTo0_3		;018 cycles, 1.10 bit times
	btfss	WR_PORT,WR_PIN	;019 cycles, 1.16 bit times
	goto	WrTo0_3		;020 cycles, 1.22 bit times
	btfss	WR_PORT,WR_PIN	;021 cycles, 1.29 bit times
	goto	WrTo0_3		;022 cycles, 1.35 bit times
	btfss	WR_PORT,WR_PIN	;023 cycles, 1.41 bit times
	goto	WrTo0_3		;024 cycles, 1.47 bit times
	btfss	WR_PORT,WR_PIN	;025 cycles, 1.53 bit times
	goto	WrTo0_2		;026 cycles, 1.59 bit times
	btfss	WR_PORT,WR_PIN	;027 cycles, 1.65 bit times
	goto	WrTo0_2		;028 cycles, 1.71 bit times
	btfss	WR_PORT,WR_PIN	;029 cycles, 1.77 bit times
	goto	WrTo0_2		;030 cycles, 1.84 bit times
	btfss	WR_PORT,WR_PIN	;031 cycles, 1.90 bit times
	goto	WrTo0_2		;032 cycles, 1.96 bit times
	btfss	WR_PORT,WR_PIN	;033 cycles, 2.02 bit times
	goto	WrTo0_2		;034 cycles, 2.08 bit times
	btfss	WR_PORT,WR_PIN	;035 cycles, 2.14 bit times
	goto	WrTo0_2		;036 cycles, 2.20 bit times
	btfss	WR_PORT,WR_PIN	;037 cycles, 2.26 bit times
	goto	WrTo0_2		;038 cycles, 2.33 bit times
	btfss	WR_PORT,WR_PIN	;039 cycles, 2.39 bit times
	goto	WrTo0_2		;040 cycles, 2.45 bit times
	btfss	WR_PORT,WR_PIN	;041 cycles, 2.51 bit times
	goto	WrTo0_1		;042 cycles, 2.57 bit times
	btfss	WR_PORT,WR_PIN	;043 cycles, 2.63 bit times
	goto	WrTo0_1		;044 cycles, 2.69 bit times
	btfss	WR_PORT,WR_PIN	;045 cycles, 2.75 bit times
	goto	WrTo0_1		;046 cycles, 2.82 bit times
	btfss	WR_PORT,WR_PIN	;047 cycles, 2.88 bit times
	goto	WrTo0_1		;048 cycles, 2.94 bit times
	btfss	WR_PORT,WR_PIN	;049 cycles, 3.00 bit times
	goto	WrTo0_1		;050 cycles, 3.06 bit times
	btfss	WR_PORT,WR_PIN	;051 cycles, 3.12 bit times
	goto	WrTo0_1		;052 cycles, 3.18 bit times
	btfss	WR_PORT,WR_PIN	;053 cycles, 3.24 bit times
	goto	WrTo0_1		;054 cycles, 3.30 bit times
	btfss	WR_PORT,WR_PIN	;055 cycles, 3.37 bit times
	goto	WrTo0_1		;056 cycles, 3.43 bit times
	btfss	WR_PORT,WR_PIN	;057 cycles, 3.49 bit times
	goto	WrTo0_1		;058 cycles, 3.55 bit times
	btfss	WR_PORT,WR_PIN	;059 cycles, 3.61 bit times
	goto	WrTo0_0		;060 cycles, 3.67 bit times
	btfss	WR_PORT,WR_PIN	;061 cycles, 3.73 bit times
	goto	WrTo0_0		;062 cycles, 3.79 bit times
	btfss	WR_PORT,WR_PIN	;063 cycles, 3.86 bit times
	goto	WrTo0_0		;064 cycles, 3.92 bit times
	btfss	WR_PORT,WR_PIN	;065 cycles, 3.98 bit times
	goto	WrTo0_0		;066 cycles, 4.04 bit times
	btfss	WR_PORT,WR_PIN	;067 cycles, 4.10 bit times
	goto	WrTo0_0		;068 cycles, 4.16 bit times
	btfss	WR_PORT,WR_PIN	;069 cycles, 4.22 bit times
	goto	WrTo0_0		;070 cycles, 4.28 bit times
	btfss	WR_PORT,WR_PIN	;071 cycles, 4.35 bit times
	goto	WrTo0_0		;072 cycles, 4.41 bit times
	btfss	WR_PORT,WR_PIN	;073 cycles, 4.47 bit times
	goto	WrTo0_0		;074 cycles, 4.53 bit times
	btfsc	GI_PORT,GI_PIN	;075 cycles, 4.59 bit times
	iorlw	B'10000000'	;076 cycles, 4.65 bit times
	movwf	INDF0		;077 cycles, 4.71 bit times
	goto	WrSt1		;078 cycles, 4.77 bit times

WrTo1_3	iorlw	B'00001000'	;003 cycles, 0.18 bit times
	nop			;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfss	WR_PORT,WR_PIN	;009 cycles, 0.55 bit times
	goto	WrTo0_2		;010 cycles, 0.61 bit times
	btfss	WR_PORT,WR_PIN	;011 cycles, 0.67 bit times
	goto	WrTo0_2		;012 cycles, 0.73 bit times
	btfss	WR_PORT,WR_PIN	;013 cycles, 0.80 bit times
	goto	WrTo0_2		;014 cycles, 0.86 bit times
	btfss	WR_PORT,WR_PIN	;015 cycles, 0.92 bit times
	goto	WrTo0_2		;016 cycles, 0.98 bit times
	btfss	WR_PORT,WR_PIN	;017 cycles, 1.04 bit times
	goto	WrTo0_2		;018 cycles, 1.10 bit times
	btfss	WR_PORT,WR_PIN	;019 cycles, 1.16 bit times
	goto	WrTo0_2		;020 cycles, 1.22 bit times
	btfss	WR_PORT,WR_PIN	;021 cycles, 1.29 bit times
	goto	WrTo0_2		;022 cycles, 1.35 bit times
	btfss	WR_PORT,WR_PIN	;023 cycles, 1.41 bit times
	goto	WrTo0_2		;024 cycles, 1.47 bit times
	btfss	WR_PORT,WR_PIN	;025 cycles, 1.53 bit times
	goto	WrTo0_1		;026 cycles, 1.59 bit times
	btfss	WR_PORT,WR_PIN	;027 cycles, 1.65 bit times
	goto	WrTo0_1		;028 cycles, 1.71 bit times
	btfss	WR_PORT,WR_PIN	;029 cycles, 1.77 bit times
	goto	WrTo0_1		;030 cycles, 1.84 bit times
	btfss	WR_PORT,WR_PIN	;031 cycles, 1.90 bit times
	goto	WrTo0_1		;032 cycles, 1.96 bit times
	btfss	WR_PORT,WR_PIN	;033 cycles, 2.02 bit times
	goto	WrTo0_1		;034 cycles, 2.08 bit times
	btfss	WR_PORT,WR_PIN	;035 cycles, 2.14 bit times
	goto	WrTo0_1		;036 cycles, 2.20 bit times
	btfss	WR_PORT,WR_PIN	;037 cycles, 2.26 bit times
	goto	WrTo0_1		;038 cycles, 2.33 bit times
	btfss	WR_PORT,WR_PIN	;039 cycles, 2.39 bit times
	goto	WrTo0_1		;040 cycles, 2.45 bit times
	btfss	WR_PORT,WR_PIN	;041 cycles, 2.51 bit times
	goto	WrTo0_0		;042 cycles, 2.57 bit times
	btfss	WR_PORT,WR_PIN	;043 cycles, 2.63 bit times
	goto	WrTo0_0		;044 cycles, 2.69 bit times
	btfss	WR_PORT,WR_PIN	;045 cycles, 2.75 bit times
	goto	WrTo0_0		;046 cycles, 2.82 bit times
	btfss	WR_PORT,WR_PIN	;047 cycles, 2.88 bit times
	goto	WrTo0_0		;048 cycles, 2.94 bit times
	btfss	WR_PORT,WR_PIN	;049 cycles, 3.00 bit times
	goto	WrTo0_0		;050 cycles, 3.06 bit times
	btfss	WR_PORT,WR_PIN	;051 cycles, 3.12 bit times
	goto	WrTo0_0		;052 cycles, 3.18 bit times
	btfss	WR_PORT,WR_PIN	;053 cycles, 3.24 bit times
	goto	WrTo0_0		;054 cycles, 3.30 bit times
	btfss	WR_PORT,WR_PIN	;055 cycles, 3.37 bit times
	goto	WrTo0_0		;056 cycles, 3.43 bit times
	btfss	WR_PORT,WR_PIN	;057 cycles, 3.49 bit times
	goto	WrTo0_0		;058 cycles, 3.55 bit times
	btfsc	GI_PORT,GI_PIN	;059 cycles, 3.61 bit times
	iorlw	B'10000000'	;060 cycles, 3.67 bit times
	movwf	INDF0		;061 cycles, 3.73 bit times
	goto	WrSt1		;062 cycles, 3.79 bit times

WrTo1_2	iorlw	B'00000100'	;003 cycles, 0.18 bit times
	nop			;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfss	WR_PORT,WR_PIN	;009 cycles, 0.55 bit times
	goto	WrTo0_1		;010 cycles, 0.61 bit times
	btfss	WR_PORT,WR_PIN	;011 cycles, 0.67 bit times
	goto	WrTo0_1		;012 cycles, 0.73 bit times
	btfss	WR_PORT,WR_PIN	;013 cycles, 0.80 bit times
	goto	WrTo0_1		;014 cycles, 0.86 bit times
	btfss	WR_PORT,WR_PIN	;015 cycles, 0.92 bit times
	goto	WrTo0_1		;016 cycles, 0.98 bit times
	btfss	WR_PORT,WR_PIN	;017 cycles, 1.04 bit times
	goto	WrTo0_1		;018 cycles, 1.10 bit times
	btfss	WR_PORT,WR_PIN	;019 cycles, 1.16 bit times
	goto	WrTo0_1		;020 cycles, 1.22 bit times
	btfss	WR_PORT,WR_PIN	;021 cycles, 1.29 bit times
	goto	WrTo0_1		;022 cycles, 1.35 bit times
	btfss	WR_PORT,WR_PIN	;023 cycles, 1.41 bit times
	goto	WrTo0_1		;024 cycles, 1.47 bit times
	btfss	WR_PORT,WR_PIN	;025 cycles, 1.53 bit times
	goto	WrTo0_0		;026 cycles, 1.59 bit times
	btfss	WR_PORT,WR_PIN	;027 cycles, 1.65 bit times
	goto	WrTo0_0		;028 cycles, 1.71 bit times
	btfss	WR_PORT,WR_PIN	;029 cycles, 1.77 bit times
	goto	WrTo0_0		;030 cycles, 1.84 bit times
	btfss	WR_PORT,WR_PIN	;031 cycles, 1.90 bit times
	goto	WrTo0_0		;032 cycles, 1.96 bit times
	btfss	WR_PORT,WR_PIN	;033 cycles, 2.02 bit times
	goto	WrTo0_0		;034 cycles, 2.08 bit times
	btfss	WR_PORT,WR_PIN	;035 cycles, 2.14 bit times
	goto	WrTo0_0		;036 cycles, 2.20 bit times
	btfss	WR_PORT,WR_PIN	;037 cycles, 2.26 bit times
	goto	WrTo0_0		;038 cycles, 2.33 bit times
	btfss	WR_PORT,WR_PIN	;039 cycles, 2.39 bit times
	goto	WrTo0_0		;040 cycles, 2.45 bit times
	btfsc	GI_PORT,GI_PIN	;041 cycles, 2.51 bit times
	iorlw	B'10000000'	;042 cycles, 2.57 bit times
	movwf	INDF0		;043 cycles, 2.63 bit times
	goto	WrSt1		;044 cycles, 2.69 bit times

WrTo1_1	iorlw	B'00000010'	;003 cycles, 0.18 bit times
	nop			;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfss	WR_PORT,WR_PIN	;009 cycles, 0.55 bit times
	goto	WrTo0_0		;010 cycles, 0.61 bit times
	btfss	WR_PORT,WR_PIN	;011 cycles, 0.67 bit times
	goto	WrTo0_0		;012 cycles, 0.73 bit times
	btfss	WR_PORT,WR_PIN	;013 cycles, 0.80 bit times
	goto	WrTo0_0		;014 cycles, 0.86 bit times
	btfss	WR_PORT,WR_PIN	;015 cycles, 0.92 bit times
	goto	WrTo0_0		;016 cycles, 0.98 bit times
	btfss	WR_PORT,WR_PIN	;017 cycles, 1.04 bit times
	goto	WrTo0_0		;018 cycles, 1.10 bit times
	btfss	WR_PORT,WR_PIN	;019 cycles, 1.16 bit times
	goto	WrTo0_0		;020 cycles, 1.22 bit times
	btfss	WR_PORT,WR_PIN	;021 cycles, 1.29 bit times
	goto	WrTo0_0		;022 cycles, 1.35 bit times
	btfss	WR_PORT,WR_PIN	;023 cycles, 1.41 bit times
	goto	WrTo0_0		;024 cycles, 1.47 bit times
	btfsc	GI_PORT,GI_PIN	;025 cycles, 1.53 bit times
	iorlw	B'10000000'	;026 cycles, 1.59 bit times
	movwf	INDF0		;027 cycles, 1.65 bit times
	goto	WrSt1		;028 cycles, 1.71 bit times

WrTo1_0	iorlw	B'00000001'	;003 cycles, 0.18 bit times
	btfsc	GI_PORT,GI_PIN	;004 cycles, 0.24 bit times
	iorlw	B'10000000'	;005 cycles, 0.31 bit times
	movwf	INDF0		;006 cycles, 0.37 bit times
	goto	WrSt1		;007 cycles, 0.43 bit times
	
WrSt1	btfsc	WR_PORT,WR_PIN	;Signal starts at one, wait until transition
	bra	$-1		; to zero, this is MSB (always 1) of first byte
	movlw	B'00000000'	;003 cycles, 0.18 bit times
	nop			;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfsc	WR_PORT,WR_PIN	;009 cycles, 0.55 bit times
	goto	WrTo1_6		;010 cycles, 0.61 bit times
	btfsc	WR_PORT,WR_PIN	;011 cycles, 0.67 bit times
	goto	WrTo1_6		;012 cycles, 0.73 bit times
	btfsc	WR_PORT,WR_PIN	;013 cycles, 0.80 bit times
	goto	WrTo1_6		;014 cycles, 0.86 bit times
	btfsc	WR_PORT,WR_PIN	;015 cycles, 0.92 bit times
	goto	WrTo1_6		;016 cycles, 0.98 bit times
	btfsc	WR_PORT,WR_PIN	;017 cycles, 1.04 bit times
	goto	WrTo1_6		;018 cycles, 1.10 bit times
	btfsc	WR_PORT,WR_PIN	;019 cycles, 1.16 bit times
	goto	WrTo1_6		;020 cycles, 1.22 bit times
	btfsc	WR_PORT,WR_PIN	;021 cycles, 1.29 bit times
	goto	WrTo1_6		;022 cycles, 1.35 bit times
	btfsc	WR_PORT,WR_PIN	;023 cycles, 1.41 bit times
	goto	WrTo1_6		;024 cycles, 1.47 bit times
	btfsc	WR_PORT,WR_PIN	;025 cycles, 1.53 bit times
	goto	WrTo1_5		;026 cycles, 1.59 bit times
	btfsc	WR_PORT,WR_PIN	;027 cycles, 1.65 bit times
	goto	WrTo1_5		;028 cycles, 1.71 bit times
	btfsc	WR_PORT,WR_PIN	;029 cycles, 1.77 bit times
	goto	WrTo1_5		;030 cycles, 1.84 bit times
	btfsc	WR_PORT,WR_PIN	;031 cycles, 1.90 bit times
	goto	WrTo1_5		;032 cycles, 1.96 bit times
	btfsc	WR_PORT,WR_PIN	;033 cycles, 2.02 bit times
	goto	WrTo1_5		;034 cycles, 2.08 bit times
	btfsc	WR_PORT,WR_PIN	;035 cycles, 2.14 bit times
	goto	WrTo1_5		;036 cycles, 2.20 bit times
	btfsc	WR_PORT,WR_PIN	;037 cycles, 2.26 bit times
	goto	WrTo1_5		;038 cycles, 2.33 bit times
	btfsc	WR_PORT,WR_PIN	;039 cycles, 2.39 bit times
	goto	WrTo1_5		;040 cycles, 2.45 bit times
	btfsc	WR_PORT,WR_PIN	;041 cycles, 2.51 bit times
	goto	WrTo1_4		;042 cycles, 2.57 bit times
	btfsc	WR_PORT,WR_PIN	;043 cycles, 2.63 bit times
	goto	WrTo1_4		;044 cycles, 2.69 bit times
	btfsc	WR_PORT,WR_PIN	;045 cycles, 2.75 bit times
	goto	WrTo1_4		;046 cycles, 2.82 bit times
	btfsc	WR_PORT,WR_PIN	;047 cycles, 2.88 bit times
	goto	WrTo1_4		;048 cycles, 2.94 bit times
	btfsc	WR_PORT,WR_PIN	;049 cycles, 3.00 bit times
	goto	WrTo1_4		;050 cycles, 3.06 bit times
	btfsc	WR_PORT,WR_PIN	;051 cycles, 3.12 bit times
	goto	WrTo1_4		;052 cycles, 3.18 bit times
	btfsc	WR_PORT,WR_PIN	;053 cycles, 3.24 bit times
	goto	WrTo1_4		;054 cycles, 3.30 bit times
	btfsc	WR_PORT,WR_PIN	;055 cycles, 3.37 bit times
	goto	WrTo1_4		;056 cycles, 3.43 bit times
	btfsc	WR_PORT,WR_PIN	;057 cycles, 3.49 bit times
	goto	WrTo1_4		;058 cycles, 3.55 bit times
	btfsc	WR_PORT,WR_PIN	;059 cycles, 3.61 bit times
	goto	WrTo1_3		;060 cycles, 3.67 bit times
	btfsc	WR_PORT,WR_PIN	;061 cycles, 3.73 bit times
	goto	WrTo1_3		;062 cycles, 3.79 bit times
	btfsc	WR_PORT,WR_PIN	;063 cycles, 3.86 bit times
	goto	WrTo1_3		;064 cycles, 3.92 bit times
	btfsc	WR_PORT,WR_PIN	;065 cycles, 3.98 bit times
	goto	WrTo1_3		;066 cycles, 4.04 bit times
	btfsc	WR_PORT,WR_PIN	;067 cycles, 4.10 bit times
	goto	WrTo1_3		;068 cycles, 4.16 bit times
	btfsc	WR_PORT,WR_PIN	;069 cycles, 4.22 bit times
	goto	WrTo1_3		;070 cycles, 4.28 bit times
	btfsc	WR_PORT,WR_PIN	;071 cycles, 4.35 bit times
	goto	WrTo1_3		;072 cycles, 4.41 bit times
	btfsc	WR_PORT,WR_PIN	;073 cycles, 4.47 bit times
	goto	WrTo1_3		;074 cycles, 4.53 bit times
	btfsc	WR_PORT,WR_PIN	;075 cycles, 4.59 bit times
	goto	WrTo1_2		;076 cycles, 4.65 bit times
	btfsc	WR_PORT,WR_PIN	;077 cycles, 4.71 bit times
	goto	WrTo1_2		;078 cycles, 4.77 bit times
	btfsc	WR_PORT,WR_PIN	;079 cycles, 4.83 bit times
	goto	WrTo1_2		;080 cycles, 4.90 bit times
	btfsc	WR_PORT,WR_PIN	;081 cycles, 4.96 bit times
	goto	WrTo1_2		;082 cycles, 5.02 bit times
	btfsc	WR_PORT,WR_PIN	;083 cycles, 5.08 bit times
	goto	WrTo1_2		;084 cycles, 5.14 bit times
	btfsc	WR_PORT,WR_PIN	;085 cycles, 5.20 bit times
	goto	WrTo1_2		;086 cycles, 5.26 bit times
	btfsc	WR_PORT,WR_PIN	;087 cycles, 5.32 bit times
	goto	WrTo1_2		;088 cycles, 5.39 bit times
	btfsc	WR_PORT,WR_PIN	;089 cycles, 5.45 bit times
	goto	WrTo1_2		;090 cycles, 5.51 bit times
	btfsc	WR_PORT,WR_PIN	;091 cycles, 5.57 bit times
	goto	WrTo1_1		;092 cycles, 5.63 bit times
	btfsc	WR_PORT,WR_PIN	;093 cycles, 5.69 bit times
	goto	WrTo1_1		;094 cycles, 5.75 bit times
	btfsc	WR_PORT,WR_PIN	;095 cycles, 5.81 bit times
	goto	WrTo1_1		;096 cycles, 5.88 bit times
	btfsc	WR_PORT,WR_PIN	;097 cycles, 5.94 bit times
	goto	WrTo1_1		;098 cycles, 6.00 bit times
	btfsc	WR_PORT,WR_PIN	;099 cycles, 6.06 bit times
	goto	WrTo1_1		;100 cycles, 6.12 bit times
	btfsc	WR_PORT,WR_PIN	;101 cycles, 6.18 bit times
	goto	WrTo1_1		;102 cycles, 6.24 bit times
	btfsc	WR_PORT,WR_PIN	;103 cycles, 6.30 bit times
	goto	WrTo1_1		;104 cycles, 6.36 bit times
	btfsc	WR_PORT,WR_PIN	;105 cycles, 6.43 bit times
	goto	WrTo1_1		;106 cycles, 6.49 bit times
	btfsc	WR_PORT,WR_PIN	;107 cycles, 6.55 bit times
	goto	WrTo1_0		;108 cycles, 6.61 bit times
	btfsc	WR_PORT,WR_PIN	;109 cycles, 6.67 bit times
	goto	WrTo1_0		;110 cycles, 6.73 bit times
	btfsc	WR_PORT,WR_PIN	;111 cycles, 6.79 bit times
	goto	WrTo1_0		;112 cycles, 6.85 bit times
	btfsc	WR_PORT,WR_PIN	;113 cycles, 6.92 bit times
	goto	WrTo1_0		;114 cycles, 6.98 bit times
	btfsc	WR_PORT,WR_PIN	;115 cycles, 7.04 bit times
	goto	WrTo1_0		;116 cycles, 7.10 bit times
	btfsc	WR_PORT,WR_PIN	;117 cycles, 7.16 bit times
	goto	WrTo1_0		;118 cycles, 7.22 bit times
	btfsc	WR_PORT,WR_PIN	;119 cycles, 7.28 bit times
	goto	WrTo1_0		;120 cycles, 7.34 bit times
	btfsc	WR_PORT,WR_PIN	;121 cycles, 7.40 bit times
	goto	WrTo1_0		;122 cycles, 7.47 bit times
	btfsc	GI_PORT,GI_PIN	;123 cycles, 7.53 bit times
	iorlw	B'10000000'	;124 cycles, 7.59 bit times
	movwf	INDF0		;125 cycles, 7.65 bit times
	goto	WrSt0		;126 cycles, 7.71 bit times

WrTo0_6	iorlw	B'01000000'	;003 cycles, 0.18 bit times
	nop			;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfsc	WR_PORT,WR_PIN	;009 cycles, 0.55 bit times
	goto	WrTo1_5		;010 cycles, 0.61 bit times
	btfsc	WR_PORT,WR_PIN	;011 cycles, 0.67 bit times
	goto	WrTo1_5		;012 cycles, 0.73 bit times
	btfsc	WR_PORT,WR_PIN	;013 cycles, 0.80 bit times
	goto	WrTo1_5		;014 cycles, 0.86 bit times
	btfsc	WR_PORT,WR_PIN	;015 cycles, 0.92 bit times
	goto	WrTo1_5		;016 cycles, 0.98 bit times
	btfsc	WR_PORT,WR_PIN	;017 cycles, 1.04 bit times
	goto	WrTo1_5		;018 cycles, 1.10 bit times
	btfsc	WR_PORT,WR_PIN	;019 cycles, 1.16 bit times
	goto	WrTo1_5		;020 cycles, 1.22 bit times
	btfsc	WR_PORT,WR_PIN	;021 cycles, 1.29 bit times
	goto	WrTo1_5		;022 cycles, 1.35 bit times
	btfsc	WR_PORT,WR_PIN	;023 cycles, 1.41 bit times
	goto	WrTo1_5		;024 cycles, 1.47 bit times
	btfsc	WR_PORT,WR_PIN	;025 cycles, 1.53 bit times
	goto	WrTo1_4		;026 cycles, 1.59 bit times
	btfsc	WR_PORT,WR_PIN	;027 cycles, 1.65 bit times
	goto	WrTo1_4		;028 cycles, 1.71 bit times
	btfsc	WR_PORT,WR_PIN	;029 cycles, 1.77 bit times
	goto	WrTo1_4		;030 cycles, 1.84 bit times
	btfsc	WR_PORT,WR_PIN	;031 cycles, 1.90 bit times
	goto	WrTo1_4		;032 cycles, 1.96 bit times
	btfsc	WR_PORT,WR_PIN	;033 cycles, 2.02 bit times
	goto	WrTo1_4		;034 cycles, 2.08 bit times
	btfsc	WR_PORT,WR_PIN	;035 cycles, 2.14 bit times
	goto	WrTo1_4		;036 cycles, 2.20 bit times
	btfsc	WR_PORT,WR_PIN	;037 cycles, 2.26 bit times
	goto	WrTo1_4		;038 cycles, 2.33 bit times
	btfsc	WR_PORT,WR_PIN	;039 cycles, 2.39 bit times
	goto	WrTo1_4		;040 cycles, 2.45 bit times
	btfsc	WR_PORT,WR_PIN	;041 cycles, 2.51 bit times
	goto	WrTo1_3		;042 cycles, 2.57 bit times
	btfsc	WR_PORT,WR_PIN	;043 cycles, 2.63 bit times
	goto	WrTo1_3		;044 cycles, 2.69 bit times
	btfsc	WR_PORT,WR_PIN	;045 cycles, 2.75 bit times
	goto	WrTo1_3		;046 cycles, 2.82 bit times
	btfsc	WR_PORT,WR_PIN	;047 cycles, 2.88 bit times
	goto	WrTo1_3		;048 cycles, 2.94 bit times
	btfsc	WR_PORT,WR_PIN	;049 cycles, 3.00 bit times
	goto	WrTo1_3		;050 cycles, 3.06 bit times
	btfsc	WR_PORT,WR_PIN	;051 cycles, 3.12 bit times
	goto	WrTo1_3		;052 cycles, 3.18 bit times
	btfsc	WR_PORT,WR_PIN	;053 cycles, 3.24 bit times
	goto	WrTo1_3		;054 cycles, 3.30 bit times
	btfsc	WR_PORT,WR_PIN	;055 cycles, 3.37 bit times
	goto	WrTo1_3		;056 cycles, 3.43 bit times
	btfsc	WR_PORT,WR_PIN	;057 cycles, 3.49 bit times
	goto	WrTo1_3		;058 cycles, 3.55 bit times
	btfsc	WR_PORT,WR_PIN	;059 cycles, 3.61 bit times
	goto	WrTo1_2		;060 cycles, 3.67 bit times
	btfsc	WR_PORT,WR_PIN	;061 cycles, 3.73 bit times
	goto	WrTo1_2		;062 cycles, 3.79 bit times
	btfsc	WR_PORT,WR_PIN	;063 cycles, 3.86 bit times
	goto	WrTo1_2		;064 cycles, 3.92 bit times
	btfsc	WR_PORT,WR_PIN	;065 cycles, 3.98 bit times
	goto	WrTo1_2		;066 cycles, 4.04 bit times
	btfsc	WR_PORT,WR_PIN	;067 cycles, 4.10 bit times
	goto	WrTo1_2		;068 cycles, 4.16 bit times
	btfsc	WR_PORT,WR_PIN	;069 cycles, 4.22 bit times
	goto	WrTo1_2		;070 cycles, 4.28 bit times
	btfsc	WR_PORT,WR_PIN	;071 cycles, 4.35 bit times
	goto	WrTo1_2		;072 cycles, 4.41 bit times
	btfsc	WR_PORT,WR_PIN	;073 cycles, 4.47 bit times
	goto	WrTo1_2		;074 cycles, 4.53 bit times
	btfsc	WR_PORT,WR_PIN	;075 cycles, 4.59 bit times
	goto	WrTo1_1		;076 cycles, 4.65 bit times
	btfsc	WR_PORT,WR_PIN	;077 cycles, 4.71 bit times
	goto	WrTo1_1		;078 cycles, 4.77 bit times
	btfsc	WR_PORT,WR_PIN	;079 cycles, 4.83 bit times
	goto	WrTo1_1		;080 cycles, 4.90 bit times
	btfsc	WR_PORT,WR_PIN	;081 cycles, 4.96 bit times
	goto	WrTo1_1		;082 cycles, 5.02 bit times
	btfsc	WR_PORT,WR_PIN	;083 cycles, 5.08 bit times
	goto	WrTo1_1		;084 cycles, 5.14 bit times
	btfsc	WR_PORT,WR_PIN	;085 cycles, 5.20 bit times
	goto	WrTo1_1		;086 cycles, 5.26 bit times
	btfsc	WR_PORT,WR_PIN	;087 cycles, 5.32 bit times
	goto	WrTo1_1		;088 cycles, 5.39 bit times
	btfsc	WR_PORT,WR_PIN	;089 cycles, 5.45 bit times
	goto	WrTo1_1		;090 cycles, 5.51 bit times
	btfsc	WR_PORT,WR_PIN	;091 cycles, 5.57 bit times
	goto	WrTo1_0		;092 cycles, 5.63 bit times
	btfsc	WR_PORT,WR_PIN	;093 cycles, 5.69 bit times
	goto	WrTo1_0		;094 cycles, 5.75 bit times
	btfsc	WR_PORT,WR_PIN	;095 cycles, 5.81 bit times
	goto	WrTo1_0		;096 cycles, 5.88 bit times
	btfsc	WR_PORT,WR_PIN	;097 cycles, 5.94 bit times
	goto	WrTo1_0		;098 cycles, 6.00 bit times
	btfsc	WR_PORT,WR_PIN	;099 cycles, 6.06 bit times
	goto	WrTo1_0		;100 cycles, 6.12 bit times
	btfsc	WR_PORT,WR_PIN	;101 cycles, 6.18 bit times
	goto	WrTo1_0		;102 cycles, 6.24 bit times
	btfsc	WR_PORT,WR_PIN	;103 cycles, 6.30 bit times
	goto	WrTo1_0		;104 cycles, 6.36 bit times
	btfsc	WR_PORT,WR_PIN	;105 cycles, 6.43 bit times
	goto	WrTo1_0		;106 cycles, 6.49 bit times
	btfsc	GI_PORT,GI_PIN	;107 cycles, 6.55 bit times
	iorlw	B'10000000'	;108 cycles, 6.61 bit times
	movwf	INDF0		;109 cycles, 6.67 bit times
	goto	WrSt0		;110 cycles, 6.73 bit times

WrTo0_5	iorlw	B'00100000'	;003 cycles, 0.18 bit times
	nop			;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfsc	WR_PORT,WR_PIN	;009 cycles, 0.55 bit times
	goto	WrTo1_4		;010 cycles, 0.61 bit times
	btfsc	WR_PORT,WR_PIN	;011 cycles, 0.67 bit times
	goto	WrTo1_4		;012 cycles, 0.73 bit times
	btfsc	WR_PORT,WR_PIN	;013 cycles, 0.80 bit times
	goto	WrTo1_4		;014 cycles, 0.86 bit times
	btfsc	WR_PORT,WR_PIN	;015 cycles, 0.92 bit times
	goto	WrTo1_4		;016 cycles, 0.98 bit times
	btfsc	WR_PORT,WR_PIN	;017 cycles, 1.04 bit times
	goto	WrTo1_4		;018 cycles, 1.10 bit times
	btfsc	WR_PORT,WR_PIN	;019 cycles, 1.16 bit times
	goto	WrTo1_4		;020 cycles, 1.22 bit times
	btfsc	WR_PORT,WR_PIN	;021 cycles, 1.29 bit times
	goto	WrTo1_4		;022 cycles, 1.35 bit times
	btfsc	WR_PORT,WR_PIN	;023 cycles, 1.41 bit times
	goto	WrTo1_4		;024 cycles, 1.47 bit times
	btfsc	WR_PORT,WR_PIN	;025 cycles, 1.53 bit times
	goto	WrTo1_3		;026 cycles, 1.59 bit times
	btfsc	WR_PORT,WR_PIN	;027 cycles, 1.65 bit times
	goto	WrTo1_3		;028 cycles, 1.71 bit times
	btfsc	WR_PORT,WR_PIN	;029 cycles, 1.77 bit times
	goto	WrTo1_3		;030 cycles, 1.84 bit times
	btfsc	WR_PORT,WR_PIN	;031 cycles, 1.90 bit times
	goto	WrTo1_3		;032 cycles, 1.96 bit times
	btfsc	WR_PORT,WR_PIN	;033 cycles, 2.02 bit times
	goto	WrTo1_3		;034 cycles, 2.08 bit times
	btfsc	WR_PORT,WR_PIN	;035 cycles, 2.14 bit times
	goto	WrTo1_3		;036 cycles, 2.20 bit times
	btfsc	WR_PORT,WR_PIN	;037 cycles, 2.26 bit times
	goto	WrTo1_3		;038 cycles, 2.33 bit times
	btfsc	WR_PORT,WR_PIN	;039 cycles, 2.39 bit times
	goto	WrTo1_3		;040 cycles, 2.45 bit times
	btfsc	WR_PORT,WR_PIN	;041 cycles, 2.51 bit times
	goto	WrTo1_2		;042 cycles, 2.57 bit times
	btfsc	WR_PORT,WR_PIN	;043 cycles, 2.63 bit times
	goto	WrTo1_2		;044 cycles, 2.69 bit times
	btfsc	WR_PORT,WR_PIN	;045 cycles, 2.75 bit times
	goto	WrTo1_2		;046 cycles, 2.82 bit times
	btfsc	WR_PORT,WR_PIN	;047 cycles, 2.88 bit times
	goto	WrTo1_2		;048 cycles, 2.94 bit times
	btfsc	WR_PORT,WR_PIN	;049 cycles, 3.00 bit times
	goto	WrTo1_2		;050 cycles, 3.06 bit times
	btfsc	WR_PORT,WR_PIN	;051 cycles, 3.12 bit times
	goto	WrTo1_2		;052 cycles, 3.18 bit times
	btfsc	WR_PORT,WR_PIN	;053 cycles, 3.24 bit times
	goto	WrTo1_2		;054 cycles, 3.30 bit times
	btfsc	WR_PORT,WR_PIN	;055 cycles, 3.37 bit times
	goto	WrTo1_2		;056 cycles, 3.43 bit times
	btfsc	WR_PORT,WR_PIN	;057 cycles, 3.49 bit times
	goto	WrTo1_2		;058 cycles, 3.55 bit times
	btfsc	WR_PORT,WR_PIN	;059 cycles, 3.61 bit times
	goto	WrTo1_1		;060 cycles, 3.67 bit times
	btfsc	WR_PORT,WR_PIN	;061 cycles, 3.73 bit times
	goto	WrTo1_1		;062 cycles, 3.79 bit times
	btfsc	WR_PORT,WR_PIN	;063 cycles, 3.86 bit times
	goto	WrTo1_1		;064 cycles, 3.92 bit times
	btfsc	WR_PORT,WR_PIN	;065 cycles, 3.98 bit times
	goto	WrTo1_1		;066 cycles, 4.04 bit times
	btfsc	WR_PORT,WR_PIN	;067 cycles, 4.10 bit times
	goto	WrTo1_1		;068 cycles, 4.16 bit times
	btfsc	WR_PORT,WR_PIN	;069 cycles, 4.22 bit times
	goto	WrTo1_1		;070 cycles, 4.28 bit times
	btfsc	WR_PORT,WR_PIN	;071 cycles, 4.35 bit times
	goto	WrTo1_1		;072 cycles, 4.41 bit times
	btfsc	WR_PORT,WR_PIN	;073 cycles, 4.47 bit times
	goto	WrTo1_1		;074 cycles, 4.53 bit times
	btfsc	WR_PORT,WR_PIN	;075 cycles, 4.59 bit times
	goto	WrTo1_0		;076 cycles, 4.65 bit times
	btfsc	WR_PORT,WR_PIN	;077 cycles, 4.71 bit times
	goto	WrTo1_0		;078 cycles, 4.77 bit times
	btfsc	WR_PORT,WR_PIN	;079 cycles, 4.83 bit times
	goto	WrTo1_0		;080 cycles, 4.90 bit times
	btfsc	WR_PORT,WR_PIN	;081 cycles, 4.96 bit times
	goto	WrTo1_0		;082 cycles, 5.02 bit times
	btfsc	WR_PORT,WR_PIN	;083 cycles, 5.08 bit times
	goto	WrTo1_0		;084 cycles, 5.14 bit times
	btfsc	WR_PORT,WR_PIN	;085 cycles, 5.20 bit times
	goto	WrTo1_0		;086 cycles, 5.26 bit times
	btfsc	WR_PORT,WR_PIN	;087 cycles, 5.32 bit times
	goto	WrTo1_0		;088 cycles, 5.39 bit times
	btfsc	WR_PORT,WR_PIN	;089 cycles, 5.45 bit times
	goto	WrTo1_0		;090 cycles, 5.51 bit times
	btfsc	GI_PORT,GI_PIN	;091 cycles, 5.57 bit times
	iorlw	B'10000000'	;092 cycles, 5.63 bit times
	movwf	INDF0		;093 cycles, 5.69 bit times
	goto	WrSt0		;094 cycles, 5.75 bit times

WrTo0_4	iorlw	B'00010000'	;003 cycles, 0.18 bit times
	nop			;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfsc	WR_PORT,WR_PIN	;009 cycles, 0.55 bit times
	goto	WrTo1_3		;010 cycles, 0.61 bit times
	btfsc	WR_PORT,WR_PIN	;011 cycles, 0.67 bit times
	goto	WrTo1_3		;012 cycles, 0.73 bit times
	btfsc	WR_PORT,WR_PIN	;013 cycles, 0.80 bit times
	goto	WrTo1_3		;014 cycles, 0.86 bit times
	btfsc	WR_PORT,WR_PIN	;015 cycles, 0.92 bit times
	goto	WrTo1_3		;016 cycles, 0.98 bit times
	btfsc	WR_PORT,WR_PIN	;017 cycles, 1.04 bit times
	goto	WrTo1_3		;018 cycles, 1.10 bit times
	btfsc	WR_PORT,WR_PIN	;019 cycles, 1.16 bit times
	goto	WrTo1_3		;020 cycles, 1.22 bit times
	btfsc	WR_PORT,WR_PIN	;021 cycles, 1.29 bit times
	goto	WrTo1_3		;022 cycles, 1.35 bit times
	btfsc	WR_PORT,WR_PIN	;023 cycles, 1.41 bit times
	goto	WrTo1_3		;024 cycles, 1.47 bit times
	btfsc	WR_PORT,WR_PIN	;025 cycles, 1.53 bit times
	goto	WrTo1_2		;026 cycles, 1.59 bit times
	btfsc	WR_PORT,WR_PIN	;027 cycles, 1.65 bit times
	goto	WrTo1_2		;028 cycles, 1.71 bit times
	btfsc	WR_PORT,WR_PIN	;029 cycles, 1.77 bit times
	goto	WrTo1_2		;030 cycles, 1.84 bit times
	btfsc	WR_PORT,WR_PIN	;031 cycles, 1.90 bit times
	goto	WrTo1_2		;032 cycles, 1.96 bit times
	btfsc	WR_PORT,WR_PIN	;033 cycles, 2.02 bit times
	goto	WrTo1_2		;034 cycles, 2.08 bit times
	btfsc	WR_PORT,WR_PIN	;035 cycles, 2.14 bit times
	goto	WrTo1_2		;036 cycles, 2.20 bit times
	btfsc	WR_PORT,WR_PIN	;037 cycles, 2.26 bit times
	goto	WrTo1_2		;038 cycles, 2.33 bit times
	btfsc	WR_PORT,WR_PIN	;039 cycles, 2.39 bit times
	goto	WrTo1_2		;040 cycles, 2.45 bit times
	btfsc	WR_PORT,WR_PIN	;041 cycles, 2.51 bit times
	goto	WrTo1_1		;042 cycles, 2.57 bit times
	btfsc	WR_PORT,WR_PIN	;043 cycles, 2.63 bit times
	goto	WrTo1_1		;044 cycles, 2.69 bit times
	btfsc	WR_PORT,WR_PIN	;045 cycles, 2.75 bit times
	goto	WrTo1_1		;046 cycles, 2.82 bit times
	btfsc	WR_PORT,WR_PIN	;047 cycles, 2.88 bit times
	goto	WrTo1_1		;048 cycles, 2.94 bit times
	btfsc	WR_PORT,WR_PIN	;049 cycles, 3.00 bit times
	goto	WrTo1_1		;050 cycles, 3.06 bit times
	btfsc	WR_PORT,WR_PIN	;051 cycles, 3.12 bit times
	goto	WrTo1_1		;052 cycles, 3.18 bit times
	btfsc	WR_PORT,WR_PIN	;053 cycles, 3.24 bit times
	goto	WrTo1_1		;054 cycles, 3.30 bit times
	btfsc	WR_PORT,WR_PIN	;055 cycles, 3.37 bit times
	goto	WrTo1_1		;056 cycles, 3.43 bit times
	btfsc	WR_PORT,WR_PIN	;057 cycles, 3.49 bit times
	goto	WrTo1_1		;058 cycles, 3.55 bit times
	btfsc	WR_PORT,WR_PIN	;059 cycles, 3.61 bit times
	goto	WrTo1_0		;060 cycles, 3.67 bit times
	btfsc	WR_PORT,WR_PIN	;061 cycles, 3.73 bit times
	goto	WrTo1_0		;062 cycles, 3.79 bit times
	btfsc	WR_PORT,WR_PIN	;063 cycles, 3.86 bit times
	goto	WrTo1_0		;064 cycles, 3.92 bit times
	btfsc	WR_PORT,WR_PIN	;065 cycles, 3.98 bit times
	goto	WrTo1_0		;066 cycles, 4.04 bit times
	btfsc	WR_PORT,WR_PIN	;067 cycles, 4.10 bit times
	goto	WrTo1_0		;068 cycles, 4.16 bit times
	btfsc	WR_PORT,WR_PIN	;069 cycles, 4.22 bit times
	goto	WrTo1_0		;070 cycles, 4.28 bit times
	btfsc	WR_PORT,WR_PIN	;071 cycles, 4.35 bit times
	goto	WrTo1_0		;072 cycles, 4.41 bit times
	btfsc	WR_PORT,WR_PIN	;073 cycles, 4.47 bit times
	goto	WrTo1_0		;074 cycles, 4.53 bit times
	btfsc	GI_PORT,GI_PIN	;075 cycles, 4.59 bit times
	iorlw	B'10000000'	;076 cycles, 4.65 bit times
	movwf	INDF0		;077 cycles, 4.71 bit times
	goto	WrSt0		;078 cycles, 4.77 bit times

WrTo0_3	iorlw	B'00001000'	;003 cycles, 0.18 bit times
	nop			;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfsc	WR_PORT,WR_PIN	;009 cycles, 0.55 bit times
	goto	WrTo1_2		;010 cycles, 0.61 bit times
	btfsc	WR_PORT,WR_PIN	;011 cycles, 0.67 bit times
	goto	WrTo1_2		;012 cycles, 0.73 bit times
	btfsc	WR_PORT,WR_PIN	;013 cycles, 0.80 bit times
	goto	WrTo1_2		;014 cycles, 0.86 bit times
	btfsc	WR_PORT,WR_PIN	;015 cycles, 0.92 bit times
	goto	WrTo1_2		;016 cycles, 0.98 bit times
	btfsc	WR_PORT,WR_PIN	;017 cycles, 1.04 bit times
	goto	WrTo1_2		;018 cycles, 1.10 bit times
	btfsc	WR_PORT,WR_PIN	;019 cycles, 1.16 bit times
	goto	WrTo1_2		;020 cycles, 1.22 bit times
	btfsc	WR_PORT,WR_PIN	;021 cycles, 1.29 bit times
	goto	WrTo1_2		;022 cycles, 1.35 bit times
	btfsc	WR_PORT,WR_PIN	;023 cycles, 1.41 bit times
	goto	WrTo1_2		;024 cycles, 1.47 bit times
	btfsc	WR_PORT,WR_PIN	;025 cycles, 1.53 bit times
	goto	WrTo1_1		;026 cycles, 1.59 bit times
	btfsc	WR_PORT,WR_PIN	;027 cycles, 1.65 bit times
	goto	WrTo1_1		;028 cycles, 1.71 bit times
	btfsc	WR_PORT,WR_PIN	;029 cycles, 1.77 bit times
	goto	WrTo1_1		;030 cycles, 1.84 bit times
	btfsc	WR_PORT,WR_PIN	;031 cycles, 1.90 bit times
	goto	WrTo1_1		;032 cycles, 1.96 bit times
	btfsc	WR_PORT,WR_PIN	;033 cycles, 2.02 bit times
	goto	WrTo1_1		;034 cycles, 2.08 bit times
	btfsc	WR_PORT,WR_PIN	;035 cycles, 2.14 bit times
	goto	WrTo1_1		;036 cycles, 2.20 bit times
	btfsc	WR_PORT,WR_PIN	;037 cycles, 2.26 bit times
	goto	WrTo1_1		;038 cycles, 2.33 bit times
	btfsc	WR_PORT,WR_PIN	;039 cycles, 2.39 bit times
	goto	WrTo1_1		;040 cycles, 2.45 bit times
	btfsc	WR_PORT,WR_PIN	;041 cycles, 2.51 bit times
	goto	WrTo1_0		;042 cycles, 2.57 bit times
	btfsc	WR_PORT,WR_PIN	;043 cycles, 2.63 bit times
	goto	WrTo1_0		;044 cycles, 2.69 bit times
	btfsc	WR_PORT,WR_PIN	;045 cycles, 2.75 bit times
	goto	WrTo1_0		;046 cycles, 2.82 bit times
	btfsc	WR_PORT,WR_PIN	;047 cycles, 2.88 bit times
	goto	WrTo1_0		;048 cycles, 2.94 bit times
	btfsc	WR_PORT,WR_PIN	;049 cycles, 3.00 bit times
	goto	WrTo1_0		;050 cycles, 3.06 bit times
	btfsc	WR_PORT,WR_PIN	;051 cycles, 3.12 bit times
	goto	WrTo1_0		;052 cycles, 3.18 bit times
	btfsc	WR_PORT,WR_PIN	;053 cycles, 3.24 bit times
	goto	WrTo1_0		;054 cycles, 3.30 bit times
	btfsc	WR_PORT,WR_PIN	;055 cycles, 3.37 bit times
	goto	WrTo1_0		;056 cycles, 3.43 bit times
	btfsc	WR_PORT,WR_PIN	;057 cycles, 3.49 bit times
	goto	WrTo1_0		;058 cycles, 3.55 bit times
	btfsc	GI_PORT,GI_PIN	;059 cycles, 3.61 bit times
	iorlw	B'10000000'	;060 cycles, 3.67 bit times
	movwf	INDF0		;061 cycles, 3.73 bit times
	goto	WrSt0		;062 cycles, 3.79 bit times

WrTo0_2	iorlw	B'00000100'	;003 cycles, 0.18 bit times
	nop			;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfsc	WR_PORT,WR_PIN	;009 cycles, 0.55 bit times
	goto	WrTo1_1		;010 cycles, 0.61 bit times
	btfsc	WR_PORT,WR_PIN	;011 cycles, 0.67 bit times
	goto	WrTo1_1		;012 cycles, 0.73 bit times
	btfsc	WR_PORT,WR_PIN	;013 cycles, 0.80 bit times
	goto	WrTo1_1		;014 cycles, 0.86 bit times
	btfsc	WR_PORT,WR_PIN	;015 cycles, 0.92 bit times
	goto	WrTo1_1		;016 cycles, 0.98 bit times
	btfsc	WR_PORT,WR_PIN	;017 cycles, 1.04 bit times
	goto	WrTo1_1		;018 cycles, 1.10 bit times
	btfsc	WR_PORT,WR_PIN	;019 cycles, 1.16 bit times
	goto	WrTo1_1		;020 cycles, 1.22 bit times
	btfsc	WR_PORT,WR_PIN	;021 cycles, 1.29 bit times
	goto	WrTo1_1		;022 cycles, 1.35 bit times
	btfsc	WR_PORT,WR_PIN	;023 cycles, 1.41 bit times
	goto	WrTo1_1		;024 cycles, 1.47 bit times
	btfsc	WR_PORT,WR_PIN	;025 cycles, 1.53 bit times
	goto	WrTo1_0		;026 cycles, 1.59 bit times
	btfsc	WR_PORT,WR_PIN	;027 cycles, 1.65 bit times
	goto	WrTo1_0		;028 cycles, 1.71 bit times
	btfsc	WR_PORT,WR_PIN	;029 cycles, 1.77 bit times
	goto	WrTo1_0		;030 cycles, 1.84 bit times
	btfsc	WR_PORT,WR_PIN	;031 cycles, 1.90 bit times
	goto	WrTo1_0		;032 cycles, 1.96 bit times
	btfsc	WR_PORT,WR_PIN	;033 cycles, 2.02 bit times
	goto	WrTo1_0		;034 cycles, 2.08 bit times
	btfsc	WR_PORT,WR_PIN	;035 cycles, 2.14 bit times
	goto	WrTo1_0		;036 cycles, 2.20 bit times
	btfsc	WR_PORT,WR_PIN	;037 cycles, 2.26 bit times
	goto	WrTo1_0		;038 cycles, 2.33 bit times
	btfsc	WR_PORT,WR_PIN	;039 cycles, 2.39 bit times
	goto	WrTo1_0		;040 cycles, 2.45 bit times
	btfsc	GI_PORT,GI_PIN	;041 cycles, 2.51 bit times
	iorlw	B'10000000'	;042 cycles, 2.57 bit times
	movwf	INDF0		;043 cycles, 2.63 bit times
	goto	WrSt0		;044 cycles, 2.69 bit times

WrTo0_1	iorlw	B'00000010'	;003 cycles, 0.18 bit times
	nop			;004 cycles, 0.24 bit times
	DNOP			;005-006 cycles, 0.31-0.37 bit times
	DNOP			;007-008 cycles, 0.43-0.49 bit times
	btfsc	WR_PORT,WR_PIN	;009 cycles, 0.55 bit times
	goto	WrTo1_0		;010 cycles, 0.61 bit times
	btfsc	WR_PORT,WR_PIN	;011 cycles, 0.67 bit times
	goto	WrTo1_0		;012 cycles, 0.73 bit times
	btfsc	WR_PORT,WR_PIN	;013 cycles, 0.80 bit times
	goto	WrTo1_0		;014 cycles, 0.86 bit times
	btfsc	WR_PORT,WR_PIN	;015 cycles, 0.92 bit times
	goto	WrTo1_0		;016 cycles, 0.98 bit times
	btfsc	WR_PORT,WR_PIN	;017 cycles, 1.04 bit times
	goto	WrTo1_0		;018 cycles, 1.10 bit times
	btfsc	WR_PORT,WR_PIN	;019 cycles, 1.16 bit times
	goto	WrTo1_0		;020 cycles, 1.22 bit times
	btfsc	WR_PORT,WR_PIN	;021 cycles, 1.29 bit times
	goto	WrTo1_0		;022 cycles, 1.35 bit times
	btfsc	WR_PORT,WR_PIN	;023 cycles, 1.41 bit times
	goto	WrTo1_0		;024 cycles, 1.47 bit times
	btfsc	GI_PORT,GI_PIN	;025 cycles, 1.53 bit times
	iorlw	B'10000000'	;026 cycles, 1.59 bit times
	movwf	INDF0		;027 cycles, 1.65 bit times
	goto	WrSt0		;028 cycles, 1.71 bit times

WrTo0_0	iorlw	B'00000001'	;003 cycles, 0.18 bit times
	btfsc	GI_PORT,GI_PIN	;004 cycles, 0.24 bit times
	iorlw	B'10000000'	;005 cycles, 0.31 bit times
	movwf	INDF0		;006 cycles, 0.37 bit times
	goto	WrSt0		;007 cycles, 0.43 bit times


;;; RD MFM Receiver ;;;

	org	0x800

RecvMfm
	bcf	INTCON,INTF	;Clear flag from any past falling edge
	;fall through

RecvMfmRestart
	btfss	INTCON,INTF	;Wait for a blip as the start of a sync series
	bra	$-1		; "
	bcf	INTCON,INTF	;05 cycles, 0.625 us, 0.306 bit cells
	movlw	-60		;06 cycles, 0.750 us, 0.367 bit cells
	btfsc	INTCON,INTF	;07 cycles, 0.875 us, 0.428 bit cells
	goto	RecvMfmSync	;08 cycles, 1.000 us, 0.490 bit cells
	btfsc	INTCON,INTF	;09 cycles, 1.125 us, 0.551 bit cells
	goto	RecvMfmSync	;10 cycles, 1.250 us, 0.612 bit cells
	btfsc	INTCON,INTF	;11 cycles, 1.375 us, 0.673 bit cells
	goto	RecvMfmSync	;12 cycles, 1.500 us, 0.734 bit cells
	btfsc	INTCON,INTF	;13 cycles, 1.625 us, 0.796 bit cells
	goto	RecvMfmSync	;14 cycles, 1.750 us, 0.857 bit cells
	btfsc	INTCON,INTF	;15 cycles, 1.875 us, 0.918 bit cells
	goto	RecvMfmSync	;16 cycles, 2.000 us, 0.979 bit cells
	btfsc	INTCON,INTF	;17 cycles, 2.125 us, 1.040 bit cells
	goto	RecvMfmSync	;18 cycles, 2.250 us, 1.102 bit cells
	btfsc	INTCON,INTF	;19 cycles, 2.375 us, 1.163 bit cells
	goto	RecvMfmSync	;20 cycles, 2.500 us, 1.224 bit cells
	btfsc	INTCON,INTF	;21 cycles, 2.625 us, 1.285 bit cells
	goto	RecvMfmSync	;22 cycles, 2.750 us, 1.346 bit cells
	goto	RecvMfmRestart	;Too long between transitions, start over

RecvMfmSync
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	addlw	1		;06 cycles, 0.750 us, 0.367 bit cells
	btfsc	STATUS,Z	;07 cycles, 0.875 us, 0.428 bit cells
	goto	RcvMGot		;08 cycles, 1.000 us, 0.490 bit cells
	btfsc	INTCON,INTF	;09 cycles, 1.125 us, 0.551 bit cells
	goto	RecvMfmSync	;10 cycles, 1.250 us, 0.612 bit cells
	btfsc	INTCON,INTF	;11 cycles, 1.375 us, 0.673 bit cells
	goto	RecvMfmSync	;12 cycles, 1.500 us, 0.734 bit cells
	btfsc	INTCON,INTF	;13 cycles, 1.625 us, 0.796 bit cells
	goto	RecvMfmSync	;14 cycles, 1.750 us, 0.857 bit cells
	btfsc	INTCON,INTF	;15 cycles, 1.875 us, 0.918 bit cells
	goto	RecvMfmSync	;16 cycles, 2.000 us, 0.979 bit cells
	btfsc	INTCON,INTF	;17 cycles, 2.125 us, 1.040 bit cells
	goto	RecvMfmSync	;18 cycles, 2.250 us, 1.102 bit cells
	btfsc	INTCON,INTF	;19 cycles, 2.375 us, 1.163 bit cells
	goto	RecvMfmSync	;20 cycles, 2.500 us, 1.224 bit cells
	btfsc	INTCON,INTF	;21 cycles, 2.625 us, 1.285 bit cells
	goto	RecvMfmSync	;22 cycles, 2.750 us, 1.346 bit cells
	goto	RecvMfmRestart	;Too long between transitions, start over

RecvMfmSynced
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	btfsc	INTCON,INTF	;06 cycles, 0.750 us, 0.367 bit cells
	goto	RecvMfmSynced	;07 cycles, 0.875 us, 0.428 bit cells
	btfsc	INTCON,INTF	;08 cycles, 1.000 us, 0.490 bit cells
	goto	RecvMfmSynced	;09 cycles, 1.125 us, 0.551 bit cells
RcvMGot	btfsc	INTCON,INTF	;10 cycles, 1.250 us, 0.612 bit cells
	goto	RecvMfmSynced	;11 cycles, 1.375 us, 0.673 bit cells
	btfsc	INTCON,INTF	;12 cycles, 1.500 us, 0.734 bit cells
	goto	RecvMfmSynced	;13 cycles, 1.625 us, 0.796 bit cells
	btfsc	INTCON,INTF	;14 cycles, 1.750 us, 0.857 bit cells
	goto	RecvMfmSynced	;15 cycles, 1.875 us, 0.918 bit cells
	btfsc	INTCON,INTF	;16 cycles, 2.000 us, 0.979 bit cells
	goto	RecvMfmSynced	;17 cycles, 2.125 us, 1.040 bit cells
	btfsc	INTCON,INTF	;18 cycles, 2.250 us, 1.102 bit cells
	goto	RecvMfmSynced	;19 cycles, 2.375 us, 1.163 bit cells
	btfsc	INTCON,INTF	;20 cycles, 2.500 us, 1.224 bit cells
	goto	RecvMfmSynced	;21 cycles, 2.625 us, 1.285 bit cells
	btfsc	INTCON,INTF	;22 cycles, 2.750 us, 1.346 bit cells
	goto	RecvMfm0_1	;23 cycles, 2.875 us, 1.408 bit cells
	btfsc	INTCON,INTF	;24 cycles, 3.000 us, 1.469 bit cells
	goto	RecvMfm0_1	;25 cycles, 3.125 us, 1.530 bit cells
	btfsc	INTCON,INTF	;26 cycles, 3.250 us, 1.591 bit cells
	goto	RecvMfm0_1	;27 cycles, 3.375 us, 1.652 bit cells
	btfsc	INTCON,INTF	;28 cycles, 3.500 us, 1.714 bit cells
	goto	RecvMfm0_1	;29 cycles, 3.625 us, 1.775 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm0_0
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	movlw	B'00000000'	;06 cycles, 0.750 us, 0.367 bit cells
	btfsc	INTCON,INTF	;07 cycles, 0.875 us, 0.428 bit cells
	goto	RecvMfm1_0	;08 cycles, 1.000 us, 0.490 bit cells
	btfsc	INTCON,INTF	;09 cycles, 1.125 us, 0.551 bit cells
	goto	RecvMfm1_0	;10 cycles, 1.250 us, 0.612 bit cells
	btfsc	INTCON,INTF	;11 cycles, 1.375 us, 0.673 bit cells
	goto	RecvMfm1_0	;12 cycles, 1.500 us, 0.734 bit cells
	btfsc	INTCON,INTF	;13 cycles, 1.625 us, 0.796 bit cells
	goto	RecvMfm1_0	;14 cycles, 1.750 us, 0.857 bit cells
	btfsc	INTCON,INTF	;15 cycles, 1.875 us, 0.918 bit cells
	goto	RecvMfm1_0	;16 cycles, 2.000 us, 0.979 bit cells
	btfsc	INTCON,INTF	;17 cycles, 2.125 us, 1.040 bit cells
	goto	RecvMfm1_0	;18 cycles, 2.250 us, 1.102 bit cells
	btfsc	INTCON,INTF	;19 cycles, 2.375 us, 1.163 bit cells
	goto	RecvMfm1_0	;20 cycles, 2.500 us, 1.224 bit cells
	btfsc	INTCON,INTF	;21 cycles, 2.625 us, 1.285 bit cells
	goto	RecvMfm1_0	;22 cycles, 2.750 us, 1.346 bit cells
	btfsc	INTCON,INTF	;23 cycles, 2.875 us, 1.408 bit cells
	goto	RecvMfm1_01	;24 cycles, 3.000 us, 1.469 bit cells
	btfsc	INTCON,INTF	;25 cycles, 3.125 us, 1.530 bit cells
	goto	RecvMfm1_01	;26 cycles, 3.250 us, 1.591 bit cells
	btfsc	INTCON,INTF	;27 cycles, 3.375 us, 1.652 bit cells
	goto	RecvMfm1_01	;28 cycles, 3.500 us, 1.714 bit cells
	btfsc	INTCON,INTF	;29 cycles, 3.625 us, 1.775 bit cells
	goto	RecvMfm1_01	;30 cycles, 3.750 us, 1.836 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm0_1
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	movlw	B'10000000'	;06 cycles, 0.750 us, 0.367 bit cells
	btfsc	INTCON,INTF	;07 cycles, 0.875 us, 0.428 bit cells
	goto	RecvMfm1_1	;08 cycles, 1.000 us, 0.490 bit cells
	btfsc	INTCON,INTF	;09 cycles, 1.125 us, 0.551 bit cells
	goto	RecvMfm1_1	;10 cycles, 1.250 us, 0.612 bit cells
	btfsc	INTCON,INTF	;11 cycles, 1.375 us, 0.673 bit cells
	goto	RecvMfm1_1	;12 cycles, 1.500 us, 0.734 bit cells
	btfsc	INTCON,INTF	;13 cycles, 1.625 us, 0.796 bit cells
	goto	RecvMfm1_1	;14 cycles, 1.750 us, 0.857 bit cells
	btfsc	INTCON,INTF	;15 cycles, 1.875 us, 0.918 bit cells
	goto	RecvMfm1_1	;16 cycles, 2.000 us, 0.979 bit cells
	btfsc	INTCON,INTF	;17 cycles, 2.125 us, 1.040 bit cells
	goto	RecvMfm1_1	;18 cycles, 2.250 us, 1.102 bit cells
	btfsc	INTCON,INTF	;19 cycles, 2.375 us, 1.163 bit cells
	goto	RecvMfm1_1	;20 cycles, 2.500 us, 1.224 bit cells
	btfsc	INTCON,INTF	;21 cycles, 2.625 us, 1.285 bit cells
	goto	RecvMfm1_1	;22 cycles, 2.750 us, 1.346 bit cells
	btfsc	INTCON,INTF	;23 cycles, 2.875 us, 1.408 bit cells
	goto	RecvMfm1_0	;24 cycles, 3.000 us, 1.469 bit cells
	btfsc	INTCON,INTF	;25 cycles, 3.125 us, 1.530 bit cells
	goto	RecvMfm1_0	;26 cycles, 3.250 us, 1.591 bit cells
	btfsc	INTCON,INTF	;27 cycles, 3.375 us, 1.652 bit cells
	goto	RecvMfm1_0	;28 cycles, 3.500 us, 1.714 bit cells
	btfsc	INTCON,INTF	;29 cycles, 3.625 us, 1.775 bit cells
	goto	RecvMfm1_0	;30 cycles, 3.750 us, 1.836 bit cells
	btfsc	INTCON,INTF	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfm1_01	;32 cycles, 4.000 us, 1.958 bit cells
	btfsc	INTCON,INTF	;33 cycles, 4.125 us, 2.020 bit cells
	goto	RecvMfm1_01	;34 cycles, 4.250 us, 2.081 bit cells
	btfsc	INTCON,INTF	;35 cycles, 4.375 us, 2.142 bit cells
	goto	RecvMfm1_01	;36 cycles, 4.500 us, 2.203 bit cells
	btfsc	INTCON,INTF	;37 cycles, 4.625 us, 2.264 bit cells
	goto	RecvMfm1_01	;38 cycles, 4.750 us, 2.326 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm0_01
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	movlw	B'01000000'	;06 cycles, 0.750 us, 0.367 bit cells
	btfsc	INTCON,INTF	;07 cycles, 0.875 us, 0.428 bit cells
	goto	RecvMfm2_1	;08 cycles, 1.000 us, 0.490 bit cells
	btfsc	INTCON,INTF	;09 cycles, 1.125 us, 0.551 bit cells
	goto	RecvMfm2_1	;10 cycles, 1.250 us, 0.612 bit cells
	btfsc	INTCON,INTF	;11 cycles, 1.375 us, 0.673 bit cells
	goto	RecvMfm2_1	;12 cycles, 1.500 us, 0.734 bit cells
	btfsc	INTCON,INTF	;13 cycles, 1.625 us, 0.796 bit cells
	goto	RecvMfm2_1	;14 cycles, 1.750 us, 0.857 bit cells
	btfsc	INTCON,INTF	;15 cycles, 1.875 us, 0.918 bit cells
	goto	RecvMfm2_1	;16 cycles, 2.000 us, 0.979 bit cells
	btfsc	INTCON,INTF	;17 cycles, 2.125 us, 1.040 bit cells
	goto	RecvMfm2_1	;18 cycles, 2.250 us, 1.102 bit cells
	btfsc	INTCON,INTF	;19 cycles, 2.375 us, 1.163 bit cells
	goto	RecvMfm2_1	;20 cycles, 2.500 us, 1.224 bit cells
	btfsc	INTCON,INTF	;21 cycles, 2.625 us, 1.285 bit cells
	goto	RecvMfm2_1	;22 cycles, 2.750 us, 1.346 bit cells
	btfsc	INTCON,INTF	;23 cycles, 2.875 us, 1.408 bit cells
	goto	RecvMfm2_0	;24 cycles, 3.000 us, 1.469 bit cells
	btfsc	INTCON,INTF	;25 cycles, 3.125 us, 1.530 bit cells
	goto	RecvMfm2_0	;26 cycles, 3.250 us, 1.591 bit cells
	btfsc	INTCON,INTF	;27 cycles, 3.375 us, 1.652 bit cells
	goto	RecvMfm2_0	;28 cycles, 3.500 us, 1.714 bit cells
	btfsc	INTCON,INTF	;29 cycles, 3.625 us, 1.775 bit cells
	goto	RecvMfm2_0	;30 cycles, 3.750 us, 1.836 bit cells
	btfsc	INTCON,INTF	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfm2_01	;32 cycles, 4.000 us, 1.958 bit cells
	btfsc	INTCON,INTF	;33 cycles, 4.125 us, 2.020 bit cells
	goto	RecvMfm2_01	;34 cycles, 4.250 us, 2.081 bit cells
	btfsc	INTCON,INTF	;35 cycles, 4.375 us, 2.142 bit cells
	goto	RecvMfm2_01	;36 cycles, 4.500 us, 2.203 bit cells
	btfsc	INTCON,INTF	;37 cycles, 4.625 us, 2.264 bit cells
	goto	RecvMfm2_01	;38 cycles, 4.750 us, 2.326 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm1_0
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	btfsc	INTCON,INTF	;06 cycles, 0.750 us, 0.367 bit cells
	goto	RecvMfm2_0	;07 cycles, 0.875 us, 0.428 bit cells
	btfsc	INTCON,INTF	;08 cycles, 1.000 us, 0.490 bit cells
	goto	RecvMfm2_0	;09 cycles, 1.125 us, 0.551 bit cells
	btfsc	INTCON,INTF	;10 cycles, 1.250 us, 0.612 bit cells
	goto	RecvMfm2_0	;11 cycles, 1.375 us, 0.673 bit cells
	btfsc	INTCON,INTF	;12 cycles, 1.500 us, 0.734 bit cells
	goto	RecvMfm2_0	;13 cycles, 1.625 us, 0.796 bit cells
	btfsc	INTCON,INTF	;14 cycles, 1.750 us, 0.857 bit cells
	goto	RecvMfm2_0	;15 cycles, 1.875 us, 0.918 bit cells
	btfsc	INTCON,INTF	;16 cycles, 2.000 us, 0.979 bit cells
	goto	RecvMfm2_0	;17 cycles, 2.125 us, 1.040 bit cells
	btfsc	INTCON,INTF	;18 cycles, 2.250 us, 1.102 bit cells
	goto	RecvMfm2_0	;19 cycles, 2.375 us, 1.163 bit cells
	btfsc	INTCON,INTF	;20 cycles, 2.500 us, 1.224 bit cells
	goto	RecvMfm2_0	;21 cycles, 2.625 us, 1.285 bit cells
	btfsc	INTCON,INTF	;22 cycles, 2.750 us, 1.346 bit cells
	goto	RecvMfm2_0	;23 cycles, 2.875 us, 1.408 bit cells
	btfsc	INTCON,INTF	;24 cycles, 3.000 us, 1.469 bit cells
	goto	RecvMfm2_01	;25 cycles, 3.125 us, 1.530 bit cells
	btfsc	INTCON,INTF	;26 cycles, 3.250 us, 1.591 bit cells
	goto	RecvMfm2_01	;27 cycles, 3.375 us, 1.652 bit cells
	btfsc	INTCON,INTF	;28 cycles, 3.500 us, 1.714 bit cells
	goto	RecvMfm2_01	;29 cycles, 3.625 us, 1.775 bit cells
	btfsc	INTCON,INTF	;30 cycles, 3.750 us, 1.836 bit cells
	goto	RecvMfm2_01	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm1_1
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	iorlw	B'01000000'	;06 cycles, 0.750 us, 0.367 bit cells
	btfsc	INTCON,INTF	;07 cycles, 0.875 us, 0.428 bit cells
	goto	RecvMfm2_1	;08 cycles, 1.000 us, 0.490 bit cells
	btfsc	INTCON,INTF	;09 cycles, 1.125 us, 0.551 bit cells
	goto	RecvMfm2_1	;10 cycles, 1.250 us, 0.612 bit cells
	btfsc	INTCON,INTF	;11 cycles, 1.375 us, 0.673 bit cells
	goto	RecvMfm2_1	;12 cycles, 1.500 us, 0.734 bit cells
	btfsc	INTCON,INTF	;13 cycles, 1.625 us, 0.796 bit cells
	goto	RecvMfm2_1	;14 cycles, 1.750 us, 0.857 bit cells
	btfsc	INTCON,INTF	;15 cycles, 1.875 us, 0.918 bit cells
	goto	RecvMfm2_1	;16 cycles, 2.000 us, 0.979 bit cells
	btfsc	INTCON,INTF	;17 cycles, 2.125 us, 1.040 bit cells
	goto	RecvMfm2_1	;18 cycles, 2.250 us, 1.102 bit cells
	btfsc	INTCON,INTF	;19 cycles, 2.375 us, 1.163 bit cells
	goto	RecvMfm2_1	;20 cycles, 2.500 us, 1.224 bit cells
	btfsc	INTCON,INTF	;21 cycles, 2.625 us, 1.285 bit cells
	goto	RecvMfm2_1	;22 cycles, 2.750 us, 1.346 bit cells
	btfsc	INTCON,INTF	;23 cycles, 2.875 us, 1.408 bit cells
	goto	RecvMfm2_0	;24 cycles, 3.000 us, 1.469 bit cells
	btfsc	INTCON,INTF	;25 cycles, 3.125 us, 1.530 bit cells
	goto	RecvMfm2_0	;26 cycles, 3.250 us, 1.591 bit cells
	btfsc	INTCON,INTF	;27 cycles, 3.375 us, 1.652 bit cells
	goto	RecvMfm2_0	;28 cycles, 3.500 us, 1.714 bit cells
	btfsc	INTCON,INTF	;29 cycles, 3.625 us, 1.775 bit cells
	goto	RecvMfm2_0	;30 cycles, 3.750 us, 1.836 bit cells
	btfsc	INTCON,INTF	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfm2_01	;32 cycles, 4.000 us, 1.958 bit cells
	btfsc	INTCON,INTF	;33 cycles, 4.125 us, 2.020 bit cells
	goto	RecvMfm2_01	;34 cycles, 4.250 us, 2.081 bit cells
	btfsc	INTCON,INTF	;35 cycles, 4.375 us, 2.142 bit cells
	goto	RecvMfm2_01	;36 cycles, 4.500 us, 2.203 bit cells
	btfsc	INTCON,INTF	;37 cycles, 4.625 us, 2.264 bit cells
	goto	RecvMfm2_01	;38 cycles, 4.750 us, 2.326 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm1_01
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	iorlw	B'00100000'	;06 cycles, 0.750 us, 0.367 bit cells
	btfsc	INTCON,INTF	;07 cycles, 0.875 us, 0.428 bit cells
	goto	RecvMfm3_1	;08 cycles, 1.000 us, 0.490 bit cells
	btfsc	INTCON,INTF	;09 cycles, 1.125 us, 0.551 bit cells
	goto	RecvMfm3_1	;10 cycles, 1.250 us, 0.612 bit cells
	btfsc	INTCON,INTF	;11 cycles, 1.375 us, 0.673 bit cells
	goto	RecvMfm3_1	;12 cycles, 1.500 us, 0.734 bit cells
	btfsc	INTCON,INTF	;13 cycles, 1.625 us, 0.796 bit cells
	goto	RecvMfm3_1	;14 cycles, 1.750 us, 0.857 bit cells
	btfsc	INTCON,INTF	;15 cycles, 1.875 us, 0.918 bit cells
	goto	RecvMfm3_1	;16 cycles, 2.000 us, 0.979 bit cells
	btfsc	INTCON,INTF	;17 cycles, 2.125 us, 1.040 bit cells
	goto	RecvMfm3_1	;18 cycles, 2.250 us, 1.102 bit cells
	btfsc	INTCON,INTF	;19 cycles, 2.375 us, 1.163 bit cells
	goto	RecvMfm3_1	;20 cycles, 2.500 us, 1.224 bit cells
	btfsc	INTCON,INTF	;21 cycles, 2.625 us, 1.285 bit cells
	goto	RecvMfm3_1	;22 cycles, 2.750 us, 1.346 bit cells
	btfsc	INTCON,INTF	;23 cycles, 2.875 us, 1.408 bit cells
	goto	RecvMfm3_0	;24 cycles, 3.000 us, 1.469 bit cells
	btfsc	INTCON,INTF	;25 cycles, 3.125 us, 1.530 bit cells
	goto	RecvMfm3_0	;26 cycles, 3.250 us, 1.591 bit cells
	btfsc	INTCON,INTF	;27 cycles, 3.375 us, 1.652 bit cells
	goto	RecvMfm3_0	;28 cycles, 3.500 us, 1.714 bit cells
	btfsc	INTCON,INTF	;29 cycles, 3.625 us, 1.775 bit cells
	goto	RecvMfm3_0	;30 cycles, 3.750 us, 1.836 bit cells
	btfsc	INTCON,INTF	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfm3_01	;32 cycles, 4.000 us, 1.958 bit cells
	btfsc	INTCON,INTF	;33 cycles, 4.125 us, 2.020 bit cells
	goto	RecvMfm3_01	;34 cycles, 4.250 us, 2.081 bit cells
	btfsc	INTCON,INTF	;35 cycles, 4.375 us, 2.142 bit cells
	goto	RecvMfm3_01	;36 cycles, 4.500 us, 2.203 bit cells
	btfsc	INTCON,INTF	;37 cycles, 4.625 us, 2.264 bit cells
	goto	RecvMfm3_01	;38 cycles, 4.750 us, 2.326 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm2_0
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	btfsc	INTCON,INTF	;06 cycles, 0.750 us, 0.367 bit cells
	goto	RecvMfm3_0	;07 cycles, 0.875 us, 0.428 bit cells
	btfsc	INTCON,INTF	;08 cycles, 1.000 us, 0.490 bit cells
	goto	RecvMfm3_0	;09 cycles, 1.125 us, 0.551 bit cells
	btfsc	INTCON,INTF	;10 cycles, 1.250 us, 0.612 bit cells
	goto	RecvMfm3_0	;11 cycles, 1.375 us, 0.673 bit cells
	btfsc	INTCON,INTF	;12 cycles, 1.500 us, 0.734 bit cells
	goto	RecvMfm3_0	;13 cycles, 1.625 us, 0.796 bit cells
	btfsc	INTCON,INTF	;14 cycles, 1.750 us, 0.857 bit cells
	goto	RecvMfm3_0	;15 cycles, 1.875 us, 0.918 bit cells
	btfsc	INTCON,INTF	;16 cycles, 2.000 us, 0.979 bit cells
	goto	RecvMfm3_0	;17 cycles, 2.125 us, 1.040 bit cells
	btfsc	INTCON,INTF	;18 cycles, 2.250 us, 1.102 bit cells
	goto	RecvMfm3_0	;19 cycles, 2.375 us, 1.163 bit cells
	btfsc	INTCON,INTF	;20 cycles, 2.500 us, 1.224 bit cells
	goto	RecvMfm3_0	;21 cycles, 2.625 us, 1.285 bit cells
	btfsc	INTCON,INTF	;22 cycles, 2.750 us, 1.346 bit cells
	goto	RecvMfm3_0	;23 cycles, 2.875 us, 1.408 bit cells
	btfsc	INTCON,INTF	;24 cycles, 3.000 us, 1.469 bit cells
	goto	RecvMfm3_01	;25 cycles, 3.125 us, 1.530 bit cells
	btfsc	INTCON,INTF	;26 cycles, 3.250 us, 1.591 bit cells
	goto	RecvMfm3_01	;27 cycles, 3.375 us, 1.652 bit cells
	btfsc	INTCON,INTF	;28 cycles, 3.500 us, 1.714 bit cells
	goto	RecvMfm3_01	;29 cycles, 3.625 us, 1.775 bit cells
	btfsc	INTCON,INTF	;30 cycles, 3.750 us, 1.836 bit cells
	goto	RecvMfm3_01	;31 cycles, 3.875 us, 1.897 bit cells
	btfsc	INTCON,INTF	;32 cycles, 4.000 us, 1.958 bit cells
	goto	RecvMfm3_00	;33 cycles, 4.125 us, 2.020 bit cells
	btfsc	INTCON,INTF	;34 cycles, 4.250 us, 2.081 bit cells
	goto	RecvMfm3_00	;35 cycles, 4.375 us, 2.142 bit cells
	btfsc	INTCON,INTF	;36 cycles, 4.500 us, 2.203 bit cells
	goto	RecvMfm3_00	;37 cycles, 4.625 us, 2.264 bit cells
	btfsc	INTCON,INTF	;38 cycles, 4.750 us, 2.326 bit cells
	goto	RecvMfm3_00	;39 cycles, 4.875 us, 2.387 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm2_1
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	iorlw	B'00100000'	;06 cycles, 0.750 us, 0.367 bit cells
	btfsc	INTCON,INTF	;07 cycles, 0.875 us, 0.428 bit cells
	goto	RecvMfm3_1	;08 cycles, 1.000 us, 0.490 bit cells
	btfsc	INTCON,INTF	;09 cycles, 1.125 us, 0.551 bit cells
	goto	RecvMfm3_1	;10 cycles, 1.250 us, 0.612 bit cells
	btfsc	INTCON,INTF	;11 cycles, 1.375 us, 0.673 bit cells
	goto	RecvMfm3_1	;12 cycles, 1.500 us, 0.734 bit cells
	btfsc	INTCON,INTF	;13 cycles, 1.625 us, 0.796 bit cells
	goto	RecvMfm3_1	;14 cycles, 1.750 us, 0.857 bit cells
	btfsc	INTCON,INTF	;15 cycles, 1.875 us, 0.918 bit cells
	goto	RecvMfm3_1	;16 cycles, 2.000 us, 0.979 bit cells
	btfsc	INTCON,INTF	;17 cycles, 2.125 us, 1.040 bit cells
	goto	RecvMfm3_1	;18 cycles, 2.250 us, 1.102 bit cells
	btfsc	INTCON,INTF	;19 cycles, 2.375 us, 1.163 bit cells
	goto	RecvMfm3_1	;20 cycles, 2.500 us, 1.224 bit cells
	btfsc	INTCON,INTF	;21 cycles, 2.625 us, 1.285 bit cells
	goto	RecvMfm3_1	;22 cycles, 2.750 us, 1.346 bit cells
	btfsc	INTCON,INTF	;23 cycles, 2.875 us, 1.408 bit cells
	goto	RecvMfm3_0	;24 cycles, 3.000 us, 1.469 bit cells
	btfsc	INTCON,INTF	;25 cycles, 3.125 us, 1.530 bit cells
	goto	RecvMfm3_0	;26 cycles, 3.250 us, 1.591 bit cells
	btfsc	INTCON,INTF	;27 cycles, 3.375 us, 1.652 bit cells
	goto	RecvMfm3_0	;28 cycles, 3.500 us, 1.714 bit cells
	btfsc	INTCON,INTF	;29 cycles, 3.625 us, 1.775 bit cells
	goto	RecvMfm3_0	;30 cycles, 3.750 us, 1.836 bit cells
	btfsc	INTCON,INTF	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfm3_01	;32 cycles, 4.000 us, 1.958 bit cells
	btfsc	INTCON,INTF	;33 cycles, 4.125 us, 2.020 bit cells
	goto	RecvMfm3_01	;34 cycles, 4.250 us, 2.081 bit cells
	btfsc	INTCON,INTF	;35 cycles, 4.375 us, 2.142 bit cells
	goto	RecvMfm3_01	;36 cycles, 4.500 us, 2.203 bit cells
	btfsc	INTCON,INTF	;37 cycles, 4.625 us, 2.264 bit cells
	goto	RecvMfm3_01	;38 cycles, 4.750 us, 2.326 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm2_01
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	iorlw	B'00010000'	;06 cycles, 0.750 us, 0.367 bit cells
	btfsc	INTCON,INTF	;07 cycles, 0.875 us, 0.428 bit cells
	goto	RecvMfm4_1	;08 cycles, 1.000 us, 0.490 bit cells
	btfsc	INTCON,INTF	;09 cycles, 1.125 us, 0.551 bit cells
	goto	RecvMfm4_1	;10 cycles, 1.250 us, 0.612 bit cells
	btfsc	INTCON,INTF	;11 cycles, 1.375 us, 0.673 bit cells
	goto	RecvMfm4_1	;12 cycles, 1.500 us, 0.734 bit cells
	btfsc	INTCON,INTF	;13 cycles, 1.625 us, 0.796 bit cells
	goto	RecvMfm4_1	;14 cycles, 1.750 us, 0.857 bit cells
	btfsc	INTCON,INTF	;15 cycles, 1.875 us, 0.918 bit cells
	goto	RecvMfm4_1	;16 cycles, 2.000 us, 0.979 bit cells
	btfsc	INTCON,INTF	;17 cycles, 2.125 us, 1.040 bit cells
	goto	RecvMfm4_1	;18 cycles, 2.250 us, 1.102 bit cells
	btfsc	INTCON,INTF	;19 cycles, 2.375 us, 1.163 bit cells
	goto	RecvMfm4_1	;20 cycles, 2.500 us, 1.224 bit cells
	btfsc	INTCON,INTF	;21 cycles, 2.625 us, 1.285 bit cells
	goto	RecvMfm4_1	;22 cycles, 2.750 us, 1.346 bit cells
	btfsc	INTCON,INTF	;23 cycles, 2.875 us, 1.408 bit cells
	goto	RecvMfm4_0	;24 cycles, 3.000 us, 1.469 bit cells
	btfsc	INTCON,INTF	;25 cycles, 3.125 us, 1.530 bit cells
	goto	RecvMfm4_0	;26 cycles, 3.250 us, 1.591 bit cells
	btfsc	INTCON,INTF	;27 cycles, 3.375 us, 1.652 bit cells
	goto	RecvMfm4_0	;28 cycles, 3.500 us, 1.714 bit cells
	btfsc	INTCON,INTF	;29 cycles, 3.625 us, 1.775 bit cells
	goto	RecvMfm4_0	;30 cycles, 3.750 us, 1.836 bit cells
	btfsc	INTCON,INTF	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfm4_01	;32 cycles, 4.000 us, 1.958 bit cells
	btfsc	INTCON,INTF	;33 cycles, 4.125 us, 2.020 bit cells
	goto	RecvMfm4_01	;34 cycles, 4.250 us, 2.081 bit cells
	btfsc	INTCON,INTF	;35 cycles, 4.375 us, 2.142 bit cells
	goto	RecvMfm4_01	;36 cycles, 4.500 us, 2.203 bit cells
	btfsc	INTCON,INTF	;37 cycles, 4.625 us, 2.264 bit cells
	goto	RecvMfm4_01	;38 cycles, 4.750 us, 2.326 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm3_0
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	btfsc	INTCON,INTF	;06 cycles, 0.750 us, 0.367 bit cells
	goto	RecvMfm4_0	;07 cycles, 0.875 us, 0.428 bit cells
	btfsc	INTCON,INTF	;08 cycles, 1.000 us, 0.490 bit cells
	goto	RecvMfm4_0	;09 cycles, 1.125 us, 0.551 bit cells
	btfsc	INTCON,INTF	;10 cycles, 1.250 us, 0.612 bit cells
	goto	RecvMfm4_0	;11 cycles, 1.375 us, 0.673 bit cells
	btfsc	INTCON,INTF	;12 cycles, 1.500 us, 0.734 bit cells
	goto	RecvMfm4_0	;13 cycles, 1.625 us, 0.796 bit cells
	btfsc	INTCON,INTF	;14 cycles, 1.750 us, 0.857 bit cells
	goto	RecvMfm4_0	;15 cycles, 1.875 us, 0.918 bit cells
	btfsc	INTCON,INTF	;16 cycles, 2.000 us, 0.979 bit cells
	goto	RecvMfm4_0	;17 cycles, 2.125 us, 1.040 bit cells
	btfsc	INTCON,INTF	;18 cycles, 2.250 us, 1.102 bit cells
	goto	RecvMfm4_0	;19 cycles, 2.375 us, 1.163 bit cells
	btfsc	INTCON,INTF	;20 cycles, 2.500 us, 1.224 bit cells
	goto	RecvMfm4_0	;21 cycles, 2.625 us, 1.285 bit cells
	btfsc	INTCON,INTF	;22 cycles, 2.750 us, 1.346 bit cells
	goto	RecvMfm4_0	;23 cycles, 2.875 us, 1.408 bit cells
	btfsc	INTCON,INTF	;24 cycles, 3.000 us, 1.469 bit cells
	goto	RecvMfm4_01	;25 cycles, 3.125 us, 1.530 bit cells
	btfsc	INTCON,INTF	;26 cycles, 3.250 us, 1.591 bit cells
	goto	RecvMfm4_01	;27 cycles, 3.375 us, 1.652 bit cells
	btfsc	INTCON,INTF	;28 cycles, 3.500 us, 1.714 bit cells
	goto	RecvMfm4_01	;29 cycles, 3.625 us, 1.775 bit cells
	btfsc	INTCON,INTF	;30 cycles, 3.750 us, 1.836 bit cells
	goto	RecvMfm4_01	;31 cycles, 3.875 us, 1.897 bit cells
	btfsc	INTCON,INTF	;32 cycles, 4.000 us, 1.958 bit cells
	goto	RecvMfm4_00	;33 cycles, 4.125 us, 2.020 bit cells
	btfsc	INTCON,INTF	;34 cycles, 4.250 us, 2.081 bit cells
	goto	RecvMfm4_00	;35 cycles, 4.375 us, 2.142 bit cells
	btfsc	INTCON,INTF	;36 cycles, 4.500 us, 2.203 bit cells
	goto	RecvMfm4_00	;37 cycles, 4.625 us, 2.264 bit cells
	btfsc	INTCON,INTF	;38 cycles, 4.750 us, 2.326 bit cells
	goto	RecvMfm4_00	;39 cycles, 4.875 us, 2.387 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm3_1
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	iorlw	B'00010000'	;06 cycles, 0.750 us, 0.367 bit cells
	btfsc	INTCON,INTF	;07 cycles, 0.875 us, 0.428 bit cells
	goto	RecvMfm4_1	;08 cycles, 1.000 us, 0.490 bit cells
	btfsc	INTCON,INTF	;09 cycles, 1.125 us, 0.551 bit cells
	goto	RecvMfm4_1	;10 cycles, 1.250 us, 0.612 bit cells
	btfsc	INTCON,INTF	;11 cycles, 1.375 us, 0.673 bit cells
	goto	RecvMfm4_1	;12 cycles, 1.500 us, 0.734 bit cells
	btfsc	INTCON,INTF	;13 cycles, 1.625 us, 0.796 bit cells
	goto	RecvMfm4_1	;14 cycles, 1.750 us, 0.857 bit cells
	btfsc	INTCON,INTF	;15 cycles, 1.875 us, 0.918 bit cells
	goto	RecvMfm4_1	;16 cycles, 2.000 us, 0.979 bit cells
	btfsc	INTCON,INTF	;17 cycles, 2.125 us, 1.040 bit cells
	goto	RecvMfm4_1	;18 cycles, 2.250 us, 1.102 bit cells
	btfsc	INTCON,INTF	;19 cycles, 2.375 us, 1.163 bit cells
	goto	RecvMfm4_1	;20 cycles, 2.500 us, 1.224 bit cells
	btfsc	INTCON,INTF	;21 cycles, 2.625 us, 1.285 bit cells
	goto	RecvMfm4_1	;22 cycles, 2.750 us, 1.346 bit cells
	btfsc	INTCON,INTF	;23 cycles, 2.875 us, 1.408 bit cells
	goto	RecvMfm4_0	;24 cycles, 3.000 us, 1.469 bit cells
	btfsc	INTCON,INTF	;25 cycles, 3.125 us, 1.530 bit cells
	goto	RecvMfm4_0	;26 cycles, 3.250 us, 1.591 bit cells
	btfsc	INTCON,INTF	;27 cycles, 3.375 us, 1.652 bit cells
	goto	RecvMfm4_0	;28 cycles, 3.500 us, 1.714 bit cells
	btfsc	INTCON,INTF	;29 cycles, 3.625 us, 1.775 bit cells
	goto	RecvMfm4_0	;30 cycles, 3.750 us, 1.836 bit cells
	btfsc	INTCON,INTF	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfm4_01	;32 cycles, 4.000 us, 1.958 bit cells
	btfsc	INTCON,INTF	;33 cycles, 4.125 us, 2.020 bit cells
	goto	RecvMfm4_01	;34 cycles, 4.250 us, 2.081 bit cells
	btfsc	INTCON,INTF	;35 cycles, 4.375 us, 2.142 bit cells
	goto	RecvMfm4_01	;36 cycles, 4.500 us, 2.203 bit cells
	btfsc	INTCON,INTF	;37 cycles, 4.625 us, 2.264 bit cells
	goto	RecvMfm4_01	;38 cycles, 4.750 us, 2.326 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm3_01
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	iorlw	B'00001000'	;06 cycles, 0.750 us, 0.367 bit cells
	btfsc	INTCON,INTF	;07 cycles, 0.875 us, 0.428 bit cells
	goto	RecvMfm5_1	;08 cycles, 1.000 us, 0.490 bit cells
	btfsc	INTCON,INTF	;09 cycles, 1.125 us, 0.551 bit cells
	goto	RecvMfm5_1	;10 cycles, 1.250 us, 0.612 bit cells
	btfsc	INTCON,INTF	;11 cycles, 1.375 us, 0.673 bit cells
	goto	RecvMfm5_1	;12 cycles, 1.500 us, 0.734 bit cells
	btfsc	INTCON,INTF	;13 cycles, 1.625 us, 0.796 bit cells
	goto	RecvMfm5_1	;14 cycles, 1.750 us, 0.857 bit cells
	btfsc	INTCON,INTF	;15 cycles, 1.875 us, 0.918 bit cells
	goto	RecvMfm5_1	;16 cycles, 2.000 us, 0.979 bit cells
	btfsc	INTCON,INTF	;17 cycles, 2.125 us, 1.040 bit cells
	goto	RecvMfm5_1	;18 cycles, 2.250 us, 1.102 bit cells
	btfsc	INTCON,INTF	;19 cycles, 2.375 us, 1.163 bit cells
	goto	RecvMfm5_1	;20 cycles, 2.500 us, 1.224 bit cells
	btfsc	INTCON,INTF	;21 cycles, 2.625 us, 1.285 bit cells
	goto	RecvMfm5_1	;22 cycles, 2.750 us, 1.346 bit cells
	btfsc	INTCON,INTF	;23 cycles, 2.875 us, 1.408 bit cells
	goto	RecvMfm5_0	;24 cycles, 3.000 us, 1.469 bit cells
	btfsc	INTCON,INTF	;25 cycles, 3.125 us, 1.530 bit cells
	goto	RecvMfm5_0	;26 cycles, 3.250 us, 1.591 bit cells
	btfsc	INTCON,INTF	;27 cycles, 3.375 us, 1.652 bit cells
	goto	RecvMfm5_0	;28 cycles, 3.500 us, 1.714 bit cells
	btfsc	INTCON,INTF	;29 cycles, 3.625 us, 1.775 bit cells
	goto	RecvMfm5_0	;30 cycles, 3.750 us, 1.836 bit cells
	btfsc	INTCON,INTF	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfm5_01	;32 cycles, 4.000 us, 1.958 bit cells
	btfsc	INTCON,INTF	;33 cycles, 4.125 us, 2.020 bit cells
	goto	RecvMfm5_01	;34 cycles, 4.250 us, 2.081 bit cells
	btfsc	INTCON,INTF	;35 cycles, 4.375 us, 2.142 bit cells
	goto	RecvMfm5_01	;36 cycles, 4.500 us, 2.203 bit cells
	btfsc	INTCON,INTF	;37 cycles, 4.625 us, 2.264 bit cells
	goto	RecvMfm5_01	;38 cycles, 4.750 us, 2.326 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm3_00
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	btfsc	INTCON,INTF	;06 cycles, 0.750 us, 0.367 bit cells
	goto	RecvMfm5_0	;07 cycles, 0.875 us, 0.428 bit cells
	btfsc	INTCON,INTF	;08 cycles, 1.000 us, 0.490 bit cells
	goto	RecvMfm5_0	;09 cycles, 1.125 us, 0.551 bit cells
	btfsc	INTCON,INTF	;10 cycles, 1.250 us, 0.612 bit cells
	goto	RecvMfm5_0	;11 cycles, 1.375 us, 0.673 bit cells
	btfsc	INTCON,INTF	;12 cycles, 1.500 us, 0.734 bit cells
	goto	RecvMfm5_0	;13 cycles, 1.625 us, 0.796 bit cells
	btfsc	INTCON,INTF	;14 cycles, 1.750 us, 0.857 bit cells
	goto	RecvMfm5_0	;15 cycles, 1.875 us, 0.918 bit cells
	btfsc	INTCON,INTF	;16 cycles, 2.000 us, 0.979 bit cells
	goto	RecvMfm5_0	;17 cycles, 2.125 us, 1.040 bit cells
	btfsc	INTCON,INTF	;18 cycles, 2.250 us, 1.102 bit cells
	goto	RecvMfm5_0	;19 cycles, 2.375 us, 1.163 bit cells
	btfsc	INTCON,INTF	;20 cycles, 2.500 us, 1.224 bit cells
	goto	RecvMfm5_0	;21 cycles, 2.625 us, 1.285 bit cells
	btfsc	INTCON,INTF	;22 cycles, 2.750 us, 1.346 bit cells
	goto	RecvMfm5_0	;23 cycles, 2.875 us, 1.408 bit cells
	btfsc	INTCON,INTF	;24 cycles, 3.000 us, 1.469 bit cells
	goto	RecvMfm5_01	;25 cycles, 3.125 us, 1.530 bit cells
	btfsc	INTCON,INTF	;26 cycles, 3.250 us, 1.591 bit cells
	goto	RecvMfm5_01	;27 cycles, 3.375 us, 1.652 bit cells
	btfsc	INTCON,INTF	;28 cycles, 3.500 us, 1.714 bit cells
	goto	RecvMfm5_01	;29 cycles, 3.625 us, 1.775 bit cells
	btfsc	INTCON,INTF	;30 cycles, 3.750 us, 1.836 bit cells
	goto	RecvMfm5_01	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm4_0
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	btfsc	INTCON,INTF	;06 cycles, 0.750 us, 0.367 bit cells
	goto	RecvMfm5_0	;07 cycles, 0.875 us, 0.428 bit cells
	btfsc	INTCON,INTF	;08 cycles, 1.000 us, 0.490 bit cells
	goto	RecvMfm5_0	;09 cycles, 1.125 us, 0.551 bit cells
	btfsc	INTCON,INTF	;10 cycles, 1.250 us, 0.612 bit cells
	goto	RecvMfm5_0	;11 cycles, 1.375 us, 0.673 bit cells
	btfsc	INTCON,INTF	;12 cycles, 1.500 us, 0.734 bit cells
	goto	RecvMfm5_0	;13 cycles, 1.625 us, 0.796 bit cells
	btfsc	INTCON,INTF	;14 cycles, 1.750 us, 0.857 bit cells
	goto	RecvMfm5_0	;15 cycles, 1.875 us, 0.918 bit cells
	btfsc	INTCON,INTF	;16 cycles, 2.000 us, 0.979 bit cells
	goto	RecvMfm5_0	;17 cycles, 2.125 us, 1.040 bit cells
	btfsc	INTCON,INTF	;18 cycles, 2.250 us, 1.102 bit cells
	goto	RecvMfm5_0	;19 cycles, 2.375 us, 1.163 bit cells
	btfsc	INTCON,INTF	;20 cycles, 2.500 us, 1.224 bit cells
	goto	RecvMfm5_0	;21 cycles, 2.625 us, 1.285 bit cells
	btfsc	INTCON,INTF	;22 cycles, 2.750 us, 1.346 bit cells
	goto	RecvMfm5_0	;23 cycles, 2.875 us, 1.408 bit cells
	btfsc	INTCON,INTF	;24 cycles, 3.000 us, 1.469 bit cells
	goto	RecvMfm5_01	;25 cycles, 3.125 us, 1.530 bit cells
	btfsc	INTCON,INTF	;26 cycles, 3.250 us, 1.591 bit cells
	goto	RecvMfm5_01	;27 cycles, 3.375 us, 1.652 bit cells
	btfsc	INTCON,INTF	;28 cycles, 3.500 us, 1.714 bit cells
	goto	RecvMfm5_01	;29 cycles, 3.625 us, 1.775 bit cells
	btfsc	INTCON,INTF	;30 cycles, 3.750 us, 1.836 bit cells
	goto	RecvMfm5_01	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm4_1
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	iorlw	B'00001000'	;06 cycles, 0.750 us, 0.367 bit cells
	btfsc	INTCON,INTF	;07 cycles, 0.875 us, 0.428 bit cells
	goto	RecvMfm5_1	;08 cycles, 1.000 us, 0.490 bit cells
	btfsc	INTCON,INTF	;09 cycles, 1.125 us, 0.551 bit cells
	goto	RecvMfm5_1	;10 cycles, 1.250 us, 0.612 bit cells
	btfsc	INTCON,INTF	;11 cycles, 1.375 us, 0.673 bit cells
	goto	RecvMfm5_1	;12 cycles, 1.500 us, 0.734 bit cells
	btfsc	INTCON,INTF	;13 cycles, 1.625 us, 0.796 bit cells
	goto	RecvMfm5_1	;14 cycles, 1.750 us, 0.857 bit cells
	btfsc	INTCON,INTF	;15 cycles, 1.875 us, 0.918 bit cells
	goto	RecvMfm5_1	;16 cycles, 2.000 us, 0.979 bit cells
	btfsc	INTCON,INTF	;17 cycles, 2.125 us, 1.040 bit cells
	goto	RecvMfm5_1	;18 cycles, 2.250 us, 1.102 bit cells
	btfsc	INTCON,INTF	;19 cycles, 2.375 us, 1.163 bit cells
	goto	RecvMfm5_1	;20 cycles, 2.500 us, 1.224 bit cells
	btfsc	INTCON,INTF	;21 cycles, 2.625 us, 1.285 bit cells
	goto	RecvMfm5_1	;22 cycles, 2.750 us, 1.346 bit cells
	btfsc	INTCON,INTF	;23 cycles, 2.875 us, 1.408 bit cells
	goto	RecvMfm5_0	;24 cycles, 3.000 us, 1.469 bit cells
	btfsc	INTCON,INTF	;25 cycles, 3.125 us, 1.530 bit cells
	goto	RecvMfm5_0	;26 cycles, 3.250 us, 1.591 bit cells
	btfsc	INTCON,INTF	;27 cycles, 3.375 us, 1.652 bit cells
	goto	RecvMfm5_0	;28 cycles, 3.500 us, 1.714 bit cells
	btfsc	INTCON,INTF	;29 cycles, 3.625 us, 1.775 bit cells
	goto	RecvMfm5_0	;30 cycles, 3.750 us, 1.836 bit cells
	btfsc	INTCON,INTF	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfm5_01	;32 cycles, 4.000 us, 1.958 bit cells
	btfsc	INTCON,INTF	;33 cycles, 4.125 us, 2.020 bit cells
	goto	RecvMfm5_01	;34 cycles, 4.250 us, 2.081 bit cells
	btfsc	INTCON,INTF	;35 cycles, 4.375 us, 2.142 bit cells
	goto	RecvMfm5_01	;36 cycles, 4.500 us, 2.203 bit cells
	btfsc	INTCON,INTF	;37 cycles, 4.625 us, 2.264 bit cells
	goto	RecvMfm5_01	;38 cycles, 4.750 us, 2.326 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm4_01
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	iorlw	B'00000100'	;06 cycles, 0.750 us, 0.367 bit cells
	btfsc	INTCON,INTF	;07 cycles, 0.875 us, 0.428 bit cells
	goto	RecvMfm6_1	;08 cycles, 1.000 us, 0.490 bit cells
	btfsc	INTCON,INTF	;09 cycles, 1.125 us, 0.551 bit cells
	goto	RecvMfm6_1	;10 cycles, 1.250 us, 0.612 bit cells
	btfsc	INTCON,INTF	;11 cycles, 1.375 us, 0.673 bit cells
	goto	RecvMfm6_1	;12 cycles, 1.500 us, 0.734 bit cells
	btfsc	INTCON,INTF	;13 cycles, 1.625 us, 0.796 bit cells
	goto	RecvMfm6_1	;14 cycles, 1.750 us, 0.857 bit cells
	btfsc	INTCON,INTF	;15 cycles, 1.875 us, 0.918 bit cells
	goto	RecvMfm6_1	;16 cycles, 2.000 us, 0.979 bit cells
	btfsc	INTCON,INTF	;17 cycles, 2.125 us, 1.040 bit cells
	goto	RecvMfm6_1	;18 cycles, 2.250 us, 1.102 bit cells
	btfsc	INTCON,INTF	;19 cycles, 2.375 us, 1.163 bit cells
	goto	RecvMfm6_1	;20 cycles, 2.500 us, 1.224 bit cells
	btfsc	INTCON,INTF	;21 cycles, 2.625 us, 1.285 bit cells
	goto	RecvMfm6_1	;22 cycles, 2.750 us, 1.346 bit cells
	btfsc	INTCON,INTF	;23 cycles, 2.875 us, 1.408 bit cells
	goto	RecvMfm6_0	;24 cycles, 3.000 us, 1.469 bit cells
	btfsc	INTCON,INTF	;25 cycles, 3.125 us, 1.530 bit cells
	goto	RecvMfm6_0	;26 cycles, 3.250 us, 1.591 bit cells
	btfsc	INTCON,INTF	;27 cycles, 3.375 us, 1.652 bit cells
	goto	RecvMfm6_0	;28 cycles, 3.500 us, 1.714 bit cells
	btfsc	INTCON,INTF	;29 cycles, 3.625 us, 1.775 bit cells
	goto	RecvMfm6_0	;30 cycles, 3.750 us, 1.836 bit cells
	btfsc	INTCON,INTF	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfm6_01	;32 cycles, 4.000 us, 1.958 bit cells
	btfsc	INTCON,INTF	;33 cycles, 4.125 us, 2.020 bit cells
	goto	RecvMfm6_01	;34 cycles, 4.250 us, 2.081 bit cells
	btfsc	INTCON,INTF	;35 cycles, 4.375 us, 2.142 bit cells
	goto	RecvMfm6_01	;36 cycles, 4.500 us, 2.203 bit cells
	btfsc	INTCON,INTF	;37 cycles, 4.625 us, 2.264 bit cells
	goto	RecvMfm6_01	;38 cycles, 4.750 us, 2.326 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm4_00
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	btfsc	INTCON,INTF	;06 cycles, 0.750 us, 0.367 bit cells
	goto	RecvMfm6_0	;07 cycles, 0.875 us, 0.428 bit cells
	btfsc	INTCON,INTF	;08 cycles, 1.000 us, 0.490 bit cells
	goto	RecvMfm6_0	;09 cycles, 1.125 us, 0.551 bit cells
	btfsc	INTCON,INTF	;10 cycles, 1.250 us, 0.612 bit cells
	goto	RecvMfm6_0	;11 cycles, 1.375 us, 0.673 bit cells
	btfsc	INTCON,INTF	;12 cycles, 1.500 us, 0.734 bit cells
	goto	RecvMfm6_0	;13 cycles, 1.625 us, 0.796 bit cells
	btfsc	INTCON,INTF	;14 cycles, 1.750 us, 0.857 bit cells
	goto	RecvMfm6_0	;15 cycles, 1.875 us, 0.918 bit cells
	btfsc	INTCON,INTF	;16 cycles, 2.000 us, 0.979 bit cells
	goto	RecvMfm6_0	;17 cycles, 2.125 us, 1.040 bit cells
	btfsc	INTCON,INTF	;18 cycles, 2.250 us, 1.102 bit cells
	goto	RecvMfm6_0	;19 cycles, 2.375 us, 1.163 bit cells
	btfsc	INTCON,INTF	;20 cycles, 2.500 us, 1.224 bit cells
	goto	RecvMfm6_0	;21 cycles, 2.625 us, 1.285 bit cells
	btfsc	INTCON,INTF	;22 cycles, 2.750 us, 1.346 bit cells
	goto	RecvMfm6_0	;23 cycles, 2.875 us, 1.408 bit cells
	btfsc	INTCON,INTF	;24 cycles, 3.000 us, 1.469 bit cells
	goto	RecvMfm6_01	;25 cycles, 3.125 us, 1.530 bit cells
	btfsc	INTCON,INTF	;26 cycles, 3.250 us, 1.591 bit cells
	goto	RecvMfm6_01	;27 cycles, 3.375 us, 1.652 bit cells
	btfsc	INTCON,INTF	;28 cycles, 3.500 us, 1.714 bit cells
	goto	RecvMfm6_01	;29 cycles, 3.625 us, 1.775 bit cells
	btfsc	INTCON,INTF	;30 cycles, 3.750 us, 1.836 bit cells
	goto	RecvMfm6_01	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm5_0
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	btfsc	INTCON,INTF	;06 cycles, 0.750 us, 0.367 bit cells
	goto	RecvMfm6_0	;07 cycles, 0.875 us, 0.428 bit cells
	btfsc	INTCON,INTF	;08 cycles, 1.000 us, 0.490 bit cells
	goto	RecvMfm6_0	;09 cycles, 1.125 us, 0.551 bit cells
	btfsc	INTCON,INTF	;10 cycles, 1.250 us, 0.612 bit cells
	goto	RecvMfm6_0	;11 cycles, 1.375 us, 0.673 bit cells
	btfsc	INTCON,INTF	;12 cycles, 1.500 us, 0.734 bit cells
	goto	RecvMfm6_0	;13 cycles, 1.625 us, 0.796 bit cells
	btfsc	INTCON,INTF	;14 cycles, 1.750 us, 0.857 bit cells
	goto	RecvMfm6_0	;15 cycles, 1.875 us, 0.918 bit cells
	btfsc	INTCON,INTF	;16 cycles, 2.000 us, 0.979 bit cells
	goto	RecvMfm6_0	;17 cycles, 2.125 us, 1.040 bit cells
	btfsc	INTCON,INTF	;18 cycles, 2.250 us, 1.102 bit cells
	goto	RecvMfm6_0	;19 cycles, 2.375 us, 1.163 bit cells
	btfsc	INTCON,INTF	;20 cycles, 2.500 us, 1.224 bit cells
	goto	RecvMfm6_0	;21 cycles, 2.625 us, 1.285 bit cells
	btfsc	INTCON,INTF	;22 cycles, 2.750 us, 1.346 bit cells
	goto	RecvMfm6_0	;23 cycles, 2.875 us, 1.408 bit cells
	btfsc	INTCON,INTF	;24 cycles, 3.000 us, 1.469 bit cells
	goto	RecvMfm6_01	;25 cycles, 3.125 us, 1.530 bit cells
	btfsc	INTCON,INTF	;26 cycles, 3.250 us, 1.591 bit cells
	goto	RecvMfm6_01	;27 cycles, 3.375 us, 1.652 bit cells
	btfsc	INTCON,INTF	;28 cycles, 3.500 us, 1.714 bit cells
	goto	RecvMfm6_01	;29 cycles, 3.625 us, 1.775 bit cells
	btfsc	INTCON,INTF	;30 cycles, 3.750 us, 1.836 bit cells
	goto	RecvMfm6_01	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm5_1
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	iorlw	B'00000100'	;06 cycles, 0.750 us, 0.367 bit cells
	btfsc	INTCON,INTF	;07 cycles, 0.875 us, 0.428 bit cells
	goto	RecvMfm6_1	;08 cycles, 1.000 us, 0.490 bit cells
	btfsc	INTCON,INTF	;09 cycles, 1.125 us, 0.551 bit cells
	goto	RecvMfm6_1	;10 cycles, 1.250 us, 0.612 bit cells
	btfsc	INTCON,INTF	;11 cycles, 1.375 us, 0.673 bit cells
	goto	RecvMfm6_1	;12 cycles, 1.500 us, 0.734 bit cells
	btfsc	INTCON,INTF	;13 cycles, 1.625 us, 0.796 bit cells
	goto	RecvMfm6_1	;14 cycles, 1.750 us, 0.857 bit cells
	btfsc	INTCON,INTF	;15 cycles, 1.875 us, 0.918 bit cells
	goto	RecvMfm6_1	;16 cycles, 2.000 us, 0.979 bit cells
	btfsc	INTCON,INTF	;17 cycles, 2.125 us, 1.040 bit cells
	goto	RecvMfm6_1	;18 cycles, 2.250 us, 1.102 bit cells
	btfsc	INTCON,INTF	;19 cycles, 2.375 us, 1.163 bit cells
	goto	RecvMfm6_1	;20 cycles, 2.500 us, 1.224 bit cells
	btfsc	INTCON,INTF	;21 cycles, 2.625 us, 1.285 bit cells
	goto	RecvMfm6_1	;22 cycles, 2.750 us, 1.346 bit cells
	btfsc	INTCON,INTF	;23 cycles, 2.875 us, 1.408 bit cells
	goto	RecvMfm6_0	;24 cycles, 3.000 us, 1.469 bit cells
	btfsc	INTCON,INTF	;25 cycles, 3.125 us, 1.530 bit cells
	goto	RecvMfm6_0	;26 cycles, 3.250 us, 1.591 bit cells
	btfsc	INTCON,INTF	;27 cycles, 3.375 us, 1.652 bit cells
	goto	RecvMfm6_0	;28 cycles, 3.500 us, 1.714 bit cells
	btfsc	INTCON,INTF	;29 cycles, 3.625 us, 1.775 bit cells
	goto	RecvMfm6_0	;30 cycles, 3.750 us, 1.836 bit cells
	btfsc	INTCON,INTF	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfm6_01	;32 cycles, 4.000 us, 1.958 bit cells
	btfsc	INTCON,INTF	;33 cycles, 4.125 us, 2.020 bit cells
	goto	RecvMfm6_01	;34 cycles, 4.250 us, 2.081 bit cells
	btfsc	INTCON,INTF	;35 cycles, 4.375 us, 2.142 bit cells
	goto	RecvMfm6_01	;36 cycles, 4.500 us, 2.203 bit cells
	btfsc	INTCON,INTF	;37 cycles, 4.625 us, 2.264 bit cells
	goto	RecvMfm6_01	;38 cycles, 4.750 us, 2.326 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm5_01
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	iorlw	B'00000010'	;06 cycles, 0.750 us, 0.367 bit cells
	btfsc	INTCON,INTF	;07 cycles, 0.875 us, 0.428 bit cells
	goto	RecvMfm7_1	;08 cycles, 1.000 us, 0.490 bit cells
	btfsc	INTCON,INTF	;09 cycles, 1.125 us, 0.551 bit cells
	goto	RecvMfm7_1	;10 cycles, 1.250 us, 0.612 bit cells
	btfsc	INTCON,INTF	;11 cycles, 1.375 us, 0.673 bit cells
	goto	RecvMfm7_1	;12 cycles, 1.500 us, 0.734 bit cells
	btfsc	INTCON,INTF	;13 cycles, 1.625 us, 0.796 bit cells
	goto	RecvMfm7_1	;14 cycles, 1.750 us, 0.857 bit cells
	btfsc	INTCON,INTF	;15 cycles, 1.875 us, 0.918 bit cells
	goto	RecvMfm7_1	;16 cycles, 2.000 us, 0.979 bit cells
	btfsc	INTCON,INTF	;17 cycles, 2.125 us, 1.040 bit cells
	goto	RecvMfm7_1	;18 cycles, 2.250 us, 1.102 bit cells
	btfsc	INTCON,INTF	;19 cycles, 2.375 us, 1.163 bit cells
	goto	RecvMfm7_1	;20 cycles, 2.500 us, 1.224 bit cells
	btfsc	INTCON,INTF	;21 cycles, 2.625 us, 1.285 bit cells
	goto	RecvMfm7_1	;22 cycles, 2.750 us, 1.346 bit cells
	btfsc	INTCON,INTF	;23 cycles, 2.875 us, 1.408 bit cells
	goto	RecvMfm7_0	;24 cycles, 3.000 us, 1.469 bit cells
	btfsc	INTCON,INTF	;25 cycles, 3.125 us, 1.530 bit cells
	goto	RecvMfm7_0	;26 cycles, 3.250 us, 1.591 bit cells
	btfsc	INTCON,INTF	;27 cycles, 3.375 us, 1.652 bit cells
	goto	RecvMfm7_0	;28 cycles, 3.500 us, 1.714 bit cells
	btfsc	INTCON,INTF	;29 cycles, 3.625 us, 1.775 bit cells
	goto	RecvMfm7_0	;30 cycles, 3.750 us, 1.836 bit cells
	btfsc	INTCON,INTF	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfm7_01	;32 cycles, 4.000 us, 1.958 bit cells
	btfsc	INTCON,INTF	;33 cycles, 4.125 us, 2.020 bit cells
	goto	RecvMfm7_01	;34 cycles, 4.250 us, 2.081 bit cells
	btfsc	INTCON,INTF	;35 cycles, 4.375 us, 2.142 bit cells
	goto	RecvMfm7_01	;36 cycles, 4.500 us, 2.203 bit cells
	btfsc	INTCON,INTF	;37 cycles, 4.625 us, 2.264 bit cells
	goto	RecvMfm7_01	;38 cycles, 4.750 us, 2.326 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm6_0
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	btfsc	INTCON,INTF	;06 cycles, 0.750 us, 0.367 bit cells
	goto	RecvMfm7_0	;07 cycles, 0.875 us, 0.428 bit cells
	btfsc	INTCON,INTF	;08 cycles, 1.000 us, 0.490 bit cells
	goto	RecvMfm7_0	;09 cycles, 1.125 us, 0.551 bit cells
	btfsc	INTCON,INTF	;10 cycles, 1.250 us, 0.612 bit cells
	goto	RecvMfm7_0	;11 cycles, 1.375 us, 0.673 bit cells
	btfsc	INTCON,INTF	;12 cycles, 1.500 us, 0.734 bit cells
	goto	RecvMfm7_0	;13 cycles, 1.625 us, 0.796 bit cells
	btfsc	INTCON,INTF	;14 cycles, 1.750 us, 0.857 bit cells
	goto	RecvMfm7_0	;15 cycles, 1.875 us, 0.918 bit cells
	btfsc	INTCON,INTF	;16 cycles, 2.000 us, 0.979 bit cells
	goto	RecvMfm7_0	;17 cycles, 2.125 us, 1.040 bit cells
	btfsc	INTCON,INTF	;18 cycles, 2.250 us, 1.102 bit cells
	goto	RecvMfm7_0	;19 cycles, 2.375 us, 1.163 bit cells
	btfsc	INTCON,INTF	;20 cycles, 2.500 us, 1.224 bit cells
	goto	RecvMfm7_0	;21 cycles, 2.625 us, 1.285 bit cells
	btfsc	INTCON,INTF	;22 cycles, 2.750 us, 1.346 bit cells
	goto	RecvMfm7_0	;23 cycles, 2.875 us, 1.408 bit cells
	btfsc	INTCON,INTF	;24 cycles, 3.000 us, 1.469 bit cells
	goto	RecvMfm7_01	;25 cycles, 3.125 us, 1.530 bit cells
	btfsc	INTCON,INTF	;26 cycles, 3.250 us, 1.591 bit cells
	goto	RecvMfm7_01	;27 cycles, 3.375 us, 1.652 bit cells
	btfsc	INTCON,INTF	;28 cycles, 3.500 us, 1.714 bit cells
	goto	RecvMfm7_01	;29 cycles, 3.625 us, 1.775 bit cells
	btfsc	INTCON,INTF	;30 cycles, 3.750 us, 1.836 bit cells
	goto	RecvMfm7_01	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm6_1
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	nop			;05 cycles, 0.625 us, 0.306 bit cells
	iorlw	B'00000010'	;06 cycles, 0.750 us, 0.367 bit cells
	btfsc	INTCON,INTF	;07 cycles, 0.875 us, 0.428 bit cells
	goto	RecvMfm7_1	;08 cycles, 1.000 us, 0.490 bit cells
	btfsc	INTCON,INTF	;09 cycles, 1.125 us, 0.551 bit cells
	goto	RecvMfm7_1	;10 cycles, 1.250 us, 0.612 bit cells
	btfsc	INTCON,INTF	;11 cycles, 1.375 us, 0.673 bit cells
	goto	RecvMfm7_1	;12 cycles, 1.500 us, 0.734 bit cells
	btfsc	INTCON,INTF	;13 cycles, 1.625 us, 0.796 bit cells
	goto	RecvMfm7_1	;14 cycles, 1.750 us, 0.857 bit cells
	btfsc	INTCON,INTF	;15 cycles, 1.875 us, 0.918 bit cells
	goto	RecvMfm7_1	;16 cycles, 2.000 us, 0.979 bit cells
	btfsc	INTCON,INTF	;17 cycles, 2.125 us, 1.040 bit cells
	goto	RecvMfm7_1	;18 cycles, 2.250 us, 1.102 bit cells
	btfsc	INTCON,INTF	;19 cycles, 2.375 us, 1.163 bit cells
	goto	RecvMfm7_1	;20 cycles, 2.500 us, 1.224 bit cells
	btfsc	INTCON,INTF	;21 cycles, 2.625 us, 1.285 bit cells
	goto	RecvMfm7_1	;22 cycles, 2.750 us, 1.346 bit cells
	btfsc	INTCON,INTF	;23 cycles, 2.875 us, 1.408 bit cells
	goto	RecvMfm7_0	;24 cycles, 3.000 us, 1.469 bit cells
	btfsc	INTCON,INTF	;25 cycles, 3.125 us, 1.530 bit cells
	goto	RecvMfm7_0	;26 cycles, 3.250 us, 1.591 bit cells
	btfsc	INTCON,INTF	;27 cycles, 3.375 us, 1.652 bit cells
	goto	RecvMfm7_0	;28 cycles, 3.500 us, 1.714 bit cells
	btfsc	INTCON,INTF	;29 cycles, 3.625 us, 1.775 bit cells
	goto	RecvMfm7_0	;30 cycles, 3.750 us, 1.836 bit cells
	btfsc	INTCON,INTF	;31 cycles, 3.875 us, 1.897 bit cells
	goto	RecvMfm7_01	;32 cycles, 4.000 us, 1.958 bit cells
	btfsc	INTCON,INTF	;33 cycles, 4.125 us, 2.020 bit cells
	goto	RecvMfm7_01	;34 cycles, 4.250 us, 2.081 bit cells
	btfsc	INTCON,INTF	;35 cycles, 4.375 us, 2.142 bit cells
	goto	RecvMfm7_01	;36 cycles, 4.500 us, 2.203 bit cells
	btfsc	INTCON,INTF	;37 cycles, 4.625 us, 2.264 bit cells
	goto	RecvMfm7_01	;38 cycles, 4.750 us, 2.326 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm6_01
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	iorlw	B'00000001'	;05 cycles, 0.625 us, 0.306 bit cells
	movwf	INDF0		;06 cycles, 0.750 us, 0.367 bit cells
	nop			;07 cycles, 0.875 us, 0.428 bit cells
	btfsc	INTCON,INTF	;08 cycles, 1.000 us, 0.490 bit cells
	goto	RecvMfm0_1	;09 cycles, 1.125 us, 0.551 bit cells
	btfsc	INTCON,INTF	;10 cycles, 1.250 us, 0.612 bit cells
	goto	RecvMfm0_1	;11 cycles, 1.375 us, 0.673 bit cells
	btfsc	INTCON,INTF	;12 cycles, 1.500 us, 0.734 bit cells
	goto	RecvMfm0_1	;13 cycles, 1.625 us, 0.796 bit cells
	btfsc	INTCON,INTF	;14 cycles, 1.750 us, 0.857 bit cells
	goto	RecvMfm0_1	;15 cycles, 1.875 us, 0.918 bit cells
	btfsc	INTCON,INTF	;16 cycles, 2.000 us, 0.979 bit cells
	goto	RecvMfm0_1	;17 cycles, 2.125 us, 1.040 bit cells
	btfsc	INTCON,INTF	;18 cycles, 2.250 us, 1.102 bit cells
	goto	RecvMfm0_1	;19 cycles, 2.375 us, 1.163 bit cells
	btfsc	INTCON,INTF	;20 cycles, 2.500 us, 1.224 bit cells
	goto	RecvMfm0_1	;21 cycles, 2.625 us, 1.285 bit cells
	btfsc	INTCON,INTF	;22 cycles, 2.750 us, 1.346 bit cells
	goto	RecvMfm0_1	;23 cycles, 2.875 us, 1.408 bit cells
	btfsc	INTCON,INTF	;24 cycles, 3.000 us, 1.469 bit cells
	goto	RecvMfm0_0	;25 cycles, 3.125 us, 1.530 bit cells
	btfsc	INTCON,INTF	;26 cycles, 3.250 us, 1.591 bit cells
	goto	RecvMfm0_0	;27 cycles, 3.375 us, 1.652 bit cells
	btfsc	INTCON,INTF	;28 cycles, 3.500 us, 1.714 bit cells
	goto	RecvMfm0_0	;29 cycles, 3.625 us, 1.775 bit cells
	btfsc	INTCON,INTF	;30 cycles, 3.750 us, 1.836 bit cells
	goto	RecvMfm0_0	;31 cycles, 3.875 us, 1.897 bit cells
	btfsc	INTCON,INTF	;32 cycles, 4.000 us, 1.958 bit cells
	goto	RecvMfm0_01	;33 cycles, 4.125 us, 2.020 bit cells
	btfsc	INTCON,INTF	;34 cycles, 4.250 us, 2.081 bit cells
	goto	RecvMfm0_01	;35 cycles, 4.375 us, 2.142 bit cells
	btfsc	INTCON,INTF	;36 cycles, 4.500 us, 2.203 bit cells
	goto	RecvMfm0_01	;37 cycles, 4.625 us, 2.264 bit cells
	btfsc	INTCON,INTF	;38 cycles, 4.750 us, 2.326 bit cells
	goto	RecvMfm0_01	;39 cycles, 4.875 us, 2.387 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm7_0
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	movwf	INDF0		;05 cycles, 0.625 us, 0.306 bit cells
	nop			;06 cycles, 0.750 us, 0.367 bit cells
	btfsc	INTCON,INTF	;07 cycles, 0.875 us, 0.428 bit cells
	goto	RecvMfm0_0	;08 cycles, 1.000 us, 0.490 bit cells
	btfsc	INTCON,INTF	;09 cycles, 1.125 us, 0.551 bit cells
	goto	RecvMfm0_0	;10 cycles, 1.250 us, 0.612 bit cells
	btfsc	INTCON,INTF	;11 cycles, 1.375 us, 0.673 bit cells
	goto	RecvMfm0_0	;12 cycles, 1.500 us, 0.734 bit cells
	btfsc	INTCON,INTF	;13 cycles, 1.625 us, 0.796 bit cells
	goto	RecvMfm0_0	;14 cycles, 1.750 us, 0.857 bit cells
	btfsc	INTCON,INTF	;15 cycles, 1.875 us, 0.918 bit cells
	goto	RecvMfm0_0	;16 cycles, 2.000 us, 0.979 bit cells
	btfsc	INTCON,INTF	;17 cycles, 2.125 us, 1.040 bit cells
	goto	RecvMfm0_0	;18 cycles, 2.250 us, 1.102 bit cells
	btfsc	INTCON,INTF	;19 cycles, 2.375 us, 1.163 bit cells
	goto	RecvMfm0_0	;20 cycles, 2.500 us, 1.224 bit cells
	btfsc	INTCON,INTF	;21 cycles, 2.625 us, 1.285 bit cells
	goto	RecvMfm0_0	;22 cycles, 2.750 us, 1.346 bit cells
	btfsc	INTCON,INTF	;23 cycles, 2.875 us, 1.408 bit cells
	goto	RecvMfm0_01	;24 cycles, 3.000 us, 1.469 bit cells
	btfsc	INTCON,INTF	;25 cycles, 3.125 us, 1.530 bit cells
	goto	RecvMfm0_01	;26 cycles, 3.250 us, 1.591 bit cells
	btfsc	INTCON,INTF	;27 cycles, 3.375 us, 1.652 bit cells
	goto	RecvMfm0_01	;28 cycles, 3.500 us, 1.714 bit cells
	btfsc	INTCON,INTF	;29 cycles, 3.625 us, 1.775 bit cells
	goto	RecvMfm0_01	;30 cycles, 3.750 us, 1.836 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm7_1
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	iorlw	B'00000001'	;05 cycles, 0.625 us, 0.306 bit cells
	movwf	INDF0		;06 cycles, 0.750 us, 0.367 bit cells
	nop			;07 cycles, 0.875 us, 0.428 bit cells
	btfsc	INTCON,INTF	;08 cycles, 1.000 us, 0.490 bit cells
	goto	RecvMfm0_1	;09 cycles, 1.125 us, 0.551 bit cells
	btfsc	INTCON,INTF	;10 cycles, 1.250 us, 0.612 bit cells
	goto	RecvMfm0_1	;11 cycles, 1.375 us, 0.673 bit cells
	btfsc	INTCON,INTF	;12 cycles, 1.500 us, 0.734 bit cells
	goto	RecvMfm0_1	;13 cycles, 1.625 us, 0.796 bit cells
	btfsc	INTCON,INTF	;14 cycles, 1.750 us, 0.857 bit cells
	goto	RecvMfm0_1	;15 cycles, 1.875 us, 0.918 bit cells
	btfsc	INTCON,INTF	;16 cycles, 2.000 us, 0.979 bit cells
	goto	RecvMfm0_1	;17 cycles, 2.125 us, 1.040 bit cells
	btfsc	INTCON,INTF	;18 cycles, 2.250 us, 1.102 bit cells
	goto	RecvMfm0_1	;19 cycles, 2.375 us, 1.163 bit cells
	btfsc	INTCON,INTF	;20 cycles, 2.500 us, 1.224 bit cells
	goto	RecvMfm0_1	;21 cycles, 2.625 us, 1.285 bit cells
	btfsc	INTCON,INTF	;22 cycles, 2.750 us, 1.346 bit cells
	goto	RecvMfm0_1	;23 cycles, 2.875 us, 1.408 bit cells
	btfsc	INTCON,INTF	;24 cycles, 3.000 us, 1.469 bit cells
	goto	RecvMfm0_0	;25 cycles, 3.125 us, 1.530 bit cells
	btfsc	INTCON,INTF	;26 cycles, 3.250 us, 1.591 bit cells
	goto	RecvMfm0_0	;27 cycles, 3.375 us, 1.652 bit cells
	btfsc	INTCON,INTF	;28 cycles, 3.500 us, 1.714 bit cells
	goto	RecvMfm0_0	;29 cycles, 3.625 us, 1.775 bit cells
	btfsc	INTCON,INTF	;30 cycles, 3.750 us, 1.836 bit cells
	goto	RecvMfm0_0	;31 cycles, 3.875 us, 1.897 bit cells
	btfsc	INTCON,INTF	;32 cycles, 4.000 us, 1.958 bit cells
	goto	RecvMfm0_01	;33 cycles, 4.125 us, 2.020 bit cells
	btfsc	INTCON,INTF	;34 cycles, 4.250 us, 2.081 bit cells
	goto	RecvMfm0_01	;35 cycles, 4.375 us, 2.142 bit cells
	btfsc	INTCON,INTF	;36 cycles, 4.500 us, 2.203 bit cells
	goto	RecvMfm0_01	;37 cycles, 4.625 us, 2.264 bit cells
	btfsc	INTCON,INTF	;38 cycles, 4.750 us, 2.326 bit cells
	goto	RecvMfm0_01	;39 cycles, 4.875 us, 2.387 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync

RecvMfm7_01
	bcf	INTCON,INTF	;04 cycles, 0.500 us, 0.245 bit cells
	movwf	INDF0		;05 cycles, 0.625 us, 0.306 bit cells
	nop			;06 cycles, 0.750 us, 0.367 bit cells
	movlw	B'10000000'	;07 cycles, 0.875 us, 0.428 bit cells
	btfsc	INTCON,INTF	;08 cycles, 1.000 us, 0.490 bit cells
	goto	RecvMfm1_1	;09 cycles, 1.125 us, 0.551 bit cells
	btfsc	INTCON,INTF	;10 cycles, 1.250 us, 0.612 bit cells
	goto	RecvMfm1_1	;11 cycles, 1.375 us, 0.673 bit cells
	btfsc	INTCON,INTF	;12 cycles, 1.500 us, 0.734 bit cells
	goto	RecvMfm1_1	;13 cycles, 1.625 us, 0.796 bit cells
	btfsc	INTCON,INTF	;14 cycles, 1.750 us, 0.857 bit cells
	goto	RecvMfm1_1	;15 cycles, 1.875 us, 0.918 bit cells
	btfsc	INTCON,INTF	;16 cycles, 2.000 us, 0.979 bit cells
	goto	RecvMfm1_1	;17 cycles, 2.125 us, 1.040 bit cells
	btfsc	INTCON,INTF	;18 cycles, 2.250 us, 1.102 bit cells
	goto	RecvMfm1_1	;19 cycles, 2.375 us, 1.163 bit cells
	btfsc	INTCON,INTF	;20 cycles, 2.500 us, 1.224 bit cells
	goto	RecvMfm1_1	;21 cycles, 2.625 us, 1.285 bit cells
	btfsc	INTCON,INTF	;22 cycles, 2.750 us, 1.346 bit cells
	goto	RecvMfm1_1	;23 cycles, 2.875 us, 1.408 bit cells
	btfsc	INTCON,INTF	;24 cycles, 3.000 us, 1.469 bit cells
	goto	RecvMfm1_0	;25 cycles, 3.125 us, 1.530 bit cells
	btfsc	INTCON,INTF	;26 cycles, 3.250 us, 1.591 bit cells
	goto	RecvMfm1_0	;27 cycles, 3.375 us, 1.652 bit cells
	btfsc	INTCON,INTF	;28 cycles, 3.500 us, 1.714 bit cells
	goto	RecvMfm1_0	;29 cycles, 3.625 us, 1.775 bit cells
	btfsc	INTCON,INTF	;30 cycles, 3.750 us, 1.836 bit cells
	goto	RecvMfm1_0	;31 cycles, 3.875 us, 1.897 bit cells
	btfsc	INTCON,INTF	;32 cycles, 4.000 us, 1.958 bit cells
	goto	RecvMfm1_01	;33 cycles, 4.125 us, 2.020 bit cells
	btfsc	INTCON,INTF	;34 cycles, 4.250 us, 2.081 bit cells
	goto	RecvMfm1_01	;35 cycles, 4.375 us, 2.142 bit cells
	btfsc	INTCON,INTF	;36 cycles, 4.500 us, 2.203 bit cells
	goto	RecvMfm1_01	;37 cycles, 4.625 us, 2.264 bit cells
	btfsc	INTCON,INTF	;38 cycles, 4.750 us, 2.326 bit cells
	goto	RecvMfm1_01	;39 cycles, 4.875 us, 2.387 bit cells
	goto	RecvMfmRestart	;Too long between transitions, lose sync


;;; End of Program ;;;
	end
