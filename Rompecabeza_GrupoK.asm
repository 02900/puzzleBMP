# Rompecabeza Deslizante
# By Edwin Franco 12-10630 
#	& Juan Ortiz 13-11021

# Instrucciones: 
# 1. Abir Keyboard and Display MMIO SImulator y conectar a MIPS
# 1. Abrir bitmap display.
# 2. Establecer direccion base del mismo a 0x10040000 (heap).
# 3. Conectar Bitmap Display a MIPS
# 3. Compilar.
# 4. Ejecutar.

# SPIM S20 MIPS simulator.
# The default exception handler for spim.
#
# Copyright (C) 1990-2004 James Larus, larus@cs.wisc.edu.
# ALL RIGHTS RESERVED.
#
# SPIM is distributed under the following conditions:
#
# You may make copies of SPIM for your own use and modify those copies.
#
# All copies of SPIM must retain my name and copyright notice.
#
# You may not sell SPIM or distributed SPIM in conjunction with a commerical
# product or service without the expressed written consent of James Larus.
#
# THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE.
#

########################################################################
# NOTE: Comments added and expanded by Neal Wagner, April 4, 1999
#       and by Matthew Patitz, October 21, 2008
#   ("Text" below refers to Patterson and Hennessy, _Computer
#    Organization and Design_, Morgan Kaufmann.)
#
# INTERRUPT HANDLING IN MIPS:
# Coprocessor 0 has extra registers useful in handling exceptions
# There are four useful coprocessor 0 registers:
#-------------------------------------------------------------------|
#  REG NAME | NUMBER |   USAGE                                      |
#-------------------------------------------------------------------|
#  BadVAddr |   8    | Memory addr at which addr exception occurred |
#  Status   |  12    | Interrupt mask and enable bits               |
#  Cause    |  13    | Exception type and pending interrupt bits    |
#  EPC      |  14    | Address of instruction that caused exception |
#-----------|--------|----------------------------------------------|
# Details:
#   Status register: has an interrupt mask with a bit for each of
#      five interrupt levels.  If a bit is one, interrupts at that
#      level are allowed.  If a bit is zero, interrupts at that level
#      are disabled.  The low order 6 bits of the Status register
#      implement a three-level stack for the "kernel/user" and
#      "interrupt enable" bits.  The "kernel/user" bit is 0 if the
#      program was running in the kernel when the interrupt occurred
#      and 1 if it was in user mode.  If the "interrupt enable" bit is 1,
#      interrupts are allowed.  If it is 0, they are disabled.  At an
#      interrupt, these six bits are shifted left by two bits.
#   Cause register: The value in bits 2-5 of the Cause register
#      describes the particular type of exception.  The error messages
#      below describe these values.  Thus a 7 in bits 2-5 corresponds
#      to message __e7_ below, or a "bad address in data/stack read".
#
# There are special machine instructions for accessing these
# coprocessor 0 registers:
#      mfc0  Rdest, CPsrc: "move from coprocessor 0" moves data 
#         from the special coprocessor 0 register CPsrc into the
#         general purpose register Rdest.
#      mtc0  Rsrc, CPdest: "move to coprocessor 0" moves data 
#         from the general purpose register Rsrc into the special
#         coprocessor 0 register CPdest.
# (There are also coprocessor load and store instructions.)
#
# ACTIONS BY THE TRAP HANDLER CODE BELOW:
#  Branch to address 0x80000180 and execute handler there:
#  1. Save $a0 and $v0 in s0 and s1 and $at in $k1.
#  2. Move Cause into register $k0.
#  3. Do action such as print an error message.
#  4. Increment EPC value so offending instruction is skipped after
#     return from exception.
#  5. Restore $a0, $v0, and $at.
#  6. Clear the Cause register and re-enable interrupts in the Status
#     register.
#  6. Execute "eret" instruction to return execution to the instruction
#     at EPC.
#
########################################################################

# Define the exception handling code.  This must go first!
	.data
	.globl LockFlag
	LockFlag:.word 0
	
	.kdata
__m1_:	.asciiz "  Exception "
__m2_:	.asciiz " occurred and ignored\n"
__e0_:	.asciiz "  [Interrupt] "
__e1_:	.asciiz	"  [TLB]"
__e2_:	.asciiz	"  [TLB]"
__e3_:	.asciiz	"  [TLB]"
__e4_:	.asciiz	"  [Address error in inst/data fetch] "
__e5_:	.asciiz	"  [Address error in store] "
__e6_:	.asciiz	"  [Bad instruction address] "
__e7_:	.asciiz	"  [Bad data address] "
__e8_:	.asciiz	"  [Error in syscall] "
__e9_:	.asciiz	"  [Breakpoint] "
__e10_:	.asciiz	"  [Reserved instruction] "
__e11_:	.asciiz	""
__e12_:	.asciiz	"  [Arithmetic overflow] "
__e13_:	.asciiz	"  [Trap] "
__e14_:	.asciiz	""
__e15_:	.asciiz	"  [Floating point] "
__e16_:	.asciiz	""
__e17_:	.asciiz	""
__e18_:	.asciiz	"  [Coproc 2]"
__e19_:	.asciiz	""
__e20_:	.asciiz	""
__e21_:	.asciiz	""
__e22_:	.asciiz	"  [MDMX]"
__e23_:	.asciiz	"  [Watch]"
__e24_:	.asciiz	"  [Machine check]"
__e25_:	.asciiz	""
__e26_:	.asciiz	""
__e27_:	.asciiz	""
__e28_:	.asciiz	""
__e29_:	.asciiz	""
__e30_:	.asciiz	"  [Cache]"
__e31_:	.asciiz	""
__excp:	.word __e0_, __e1_, __e2_, __e3_, __e4_, __e5_, __e6_, __e7_, __e8_, __e9_
	.word __e10_, __e11_, __e12_, __e13_, __e14_, __e15_, __e16_, __e17_, __e18_,
	.word __e19_, __e20_, __e21_, __e22_, __e23_, __e24_, __e25_, __e26_, __e27_,
	.word __e28_, __e29_, __e30_, __e31_
s1:	.word 0
s2:	.word 0

.eqv key 0xffff0004 # Tecla presionada
#####################################################
# This is the exception handler code that the processor runs when
# an exception occurs. It only prints some information about the
# exception, but can serve as a model of how to write a handler.
#
# Because we are running in the kernel, we can use $k0/$k1 without
# saving their old values.

# This is the exception vector address for MIPS32:
	.ktext 0x80000180

#####################################################
# Save $at, $v0, and $a0
#
	#.set noat
	move $k1 $at            # Save $at
	#.set at

	sw $v0 s1               # Not re-entrant and we can't trust $sp
	sw $a0 s2               # But we need to use these registers


#####################################################
# Print information about exception
#
	li $v0 4                # syscall 4 (print_str)
	la $a0 __m1_
	syscall

	li $v0 1                # syscall 1 (print_int)
	mfc0 $k0 $13            # Get Cause register
	srl $a0 $k0 2           # Extract ExcCode Field
	andi $a0 $a0 0x1f
	syscall

	li $v0 4                # syscall 4 (print_str)
	andi $a0 $k0 0x3c
	lw $a0 __excp($a0)      # $a0 has the index into
	                        # the __excp array (exception
	                        # number * 4)
	nop
	syscall

#####################################################
# Bad PC exception requires special checks
#
	bne $k0 0x18 ok_pc
	nop

	mfc0 $a0 $14            # EPC
	andi $a0 $a0 0x3        # Is EPC word-aligned?
	beq $a0 0 ok_pc
	nop

	li $v0 10               # Exit on really bad PC
	syscall

#####################################################
#  PC is alright to continue
#
ok_pc:

	li $v0 4                # syscall 4 (print_str)
	la $a0 __m2_            # "occurred and ignored" message
	syscall

	srl $a0 $k0 2           # Extract ExcCode Field
	andi $a0 $a0 0x1f
	bne $a0 0 ret           # 0 means exception was an interrupt
	nop

#####################################################
# Interrupt-specific code goes here!
# Don't skip instruction at EPC since it has not executed.
#  -> not implemented
#
	mfc0 $k0, $13
	srl $a0, $k0, 2
	andi $a0, $a0, 0x10
	bnez $a0, regresar

# Accion segunTecla presionada
keyboard:
	lbu $a0, key
	beq $a0, 0x41, key_A
	beq $a0, 0x44, key_D
	beq $a0, 0x53, key_S
	beq $a0, 0x57, key_W
	beq $a0, 0x61, key_a
	beq $a0, 0x64, key_d
	beq $a0, 0x73, key_s
	beq $a0, 0x77, key_w
	beq $a0, 0x48, key_H
	beq $a0, 0x68, key_h
	beq $a0, 0x1B, key_ESC
	b regresar

key_D:
	li $a0, 2    # Move Left
	b saveKey

key_A:
	li $a0, 3   # Move Right
	b saveKey

key_W:
	li $a0, 4    # Move Down
	b saveKey

key_S:
	li $a0, 1    # Move Up
	b saveKey
	
key_d:
	li $a0, 2    # Move Left
	b saveKey

key_a:
	li $a0, 3   # Move Right
	b saveKey

key_w:
	li $a0, 4    # Move Down
	b saveKey

key_s:
	li $a0, 1    # Move Up
	b saveKey
	
key_H:
	li $a0, 6    # help message
	b saveKey

key_h:
	li $a0, 6    # help message
	b saveKey
	
key_ESC:
	li $a0, 5    # Exit

# asigna valor a $a0 segun tecla presionada
saveKey:
	sb $a0, movement
	b regresar

#####################################################
# Return from (non-interrupt) exception. Skip offending
# instruction at EPC to avoid infinite loop.
#
ret:

	mfc0 $k0 $14            # Get EPC register value
	addiu $k0 $k0 4         # Skip faulting instruction by skipping
	                        # forward by one instruction
                          # (Need to handle delayed branch case here)
	mtc0 $k0 $14            # Reset the EPC register

regresar:
#####################################################
# Restore registers and reset procesor state
#
	lw $v0 s1               # Restore $v0 and $a0
	lw $a0 s2

	#.set noat
	move $at $k1            # Restore $at
	#.set at

	mtc0 $0 $13             # Clear Cause register

	mfc0 $k0 $12            # Set Status register
	ori  $k0 0x1            # Interrupts enabled
	mtc0 $k0 $12


#####################################################
# Return from exception on MIPS32
#
	eret

# End of exception handling
#####################################################

.data
	buffer: .word 0
	display:.space 4
	msg0:	.asciiz "\n"
	msg1: 	.asciiz "\nIngrese la ruta donde se encuentra alojada la imagen: "
	msg2: 	.asciiz "\nHa ocurrido un error al abrir el archivo."
	msg3:	.asciiz "\nHa ocurrido un error al cargar el archivo."
	msg4:	.asciiz "\nQuiere cargar un rompecabezas de 128x128? Presiones 1.\nQuiere cargar un rompecabezas de 256x256? Presiones 2.\n"
	msg5:	.asciiz "\nIndique a donde se desea desplazar: \nPresione s para mover cuadro negro hacia arriba.\nPresione w para mover cuadro negro hacia abajo. \nPresione a para mover cuadro negro hacia la derecha. \nPresione d para mover cuadro negro hacia la izquierda.\nPresione h para mostrar ayuda.\nPresione ESC para salir."
	msg9:	.asciiz "\nAjuste las dimensiones del Bitmap Display: unidad de altura/anchura por pixeles y altura/anchura del mismo. "
	msg10:	.asciiz "\nRompecabezas Deslizante\nPara mover una casilla presione alguna tecla de direccion: w, s, a, d. \nPara salir presione escape.\nDescripcion: Rompecabezas Deslizante es un juego de accion y emocion,\ndesarrollado en un tablero de 16 casillas, en el que se reta al jugador \na ubicar cada pieza de una imagen en su posicion correcta. "
	msg11:	.asciiz "\nBien Jugado!\nGood Bye."
	
	path:	.space 4 			# direccion inicio ruta del archivo
	delay:	.space 1			# Se usa para esperar a que el usuario ajuste las dimensiones del bitmap display
	movement: .byte -1			# Guarda el valor de la tecla presionada, -1 indica es que no es una tecla valida

#-------------------------------->-------------------------------->-------------------------------->
# Macro para imprimir cadena
.macro print_str (%str)
	li		$v0, 4
	la		$a0, %str
	syscall
.end_macro

# Macro para imprimir entero
.macro print_int(%int)
	li		$v0, 1
	add		$a0, $zero, %int
	syscall
.end_macro

# Recorrer el codigo hexadecimal de la imagen a traves de palabras
.macro getColor (%int)
	lw 		$t3, buffer 			# Direccion de los bytes leidos
	add 	$t3, $t3, %int			# desplazamiento en codgio hex
	lw 		$t4, 0($t3)				# guarda color en $t4
.end_macro

# Almacena pixel en Bitmap Display
.macro	paintalo (%int)
	add 	$a2, $a1, %int			# $a2 es la direccion del pixel a pintar
	sw 		$t4, 0 ($a2)			# guarda el color $t4 en la direccion $a2
.end_macro

# Almacena pixel en Bitmap Display
.macro	paintaloTwo ()
	add 	$a2, $a1, $s5			# $a2 es la direccion del pixel a pintar
	lw 		$t3, 0 ($a2)			# get color $s5 in $t3

	add 	$a2, $a1, $s6			# $a2 es la direccion del pixel a pintar
	lw 		$t4, 0 ($a2)			# get color $s6 in $t4

	sw 		$t3, 0 ($a2)			# set color in $s5 with $t3
	add 	$a2, $a1, $s5			# $a2 es la direccion del pixel a pintar
	sw 		$t4, 0 ($a2)			# set color in $s6 with $t4
	
.end_macro

#-------------------------------->-------------------------------->-------------------------------->
.text
# Standard startup code.
lw $a0 0($sp)       # argc
addiu $a1 $sp 4     # argv
addiu $a2 $a1 4     # envp
sll $v0 $a0 2
addu $a2 $a2 $v0
jal main
nop

li $v0 10
syscall         # syscall 10 (exit)

main:
	jal		inic
	j		endProgram

inic:
	li		$t0, 256
# Pregunta al usuario que tamano de rompecabeza desea abrir
top:
	print_str (msg4)
	li 		$v0, 5
	syscall
	blez 	$v0, top
	li 		$t1, 2
	bgt 	$v0, $t1, top
	li 		$t1, 1
	beq 	$v0, $t1, tamano1
	li 		$t1, 2
	beq 	$v0, $t1, tamano2
	
tamano1:
	li		$t0, 128
tamano2:
	# Memoria Dinamica 1
	li 		$v0, 9				# allocate memory
	mul		$t1, $t0, $t0
	sll		$a0, $t1, 2			# ancho * alto * 4 bytes
	move 	$t5, $a0
	syscall						# $v0 <-- address
	sw  	$v0, display

	# Reserva Dinamica 2
	li 		$v0, 9				# allocate memory
	sll		$a0, $t1, 2			# ancho * alto * 4 bytes
	syscall						# $v0 <-- address
	sw  	$v0, buffer 		# Se guarda la direccion donde se colocaran los bytes a leer

	# Ajustar Bitmap Display de acuerdo a las dimensiones del archivo
	print_str (msg9)
	li 		$v0, 8
	la 		$a0, delay
	li 		$a1, 16
	syscall

# Solicitar ruta archivo
inputFile:
	print_str (msg1)
	li 		$v0, 8
	la 		$a0, path
	li 		$a1, 25
	syscall

	#Encontrar salto de linea
	li 		$t1, 0
	findSL:
	lb	 	$t2, path($t1)
	beq 	$t2, 10, delSL
	addi 	$t1, $t1, 1
	b findSL
	
delSL:
	sb 		$zero, path ($t1)		#Sustituir salto de linea por caracter nulo	

openFile:
	# Abir archivo
	li 		$v0, 13
	la	 	$a0, path
	li 		$a1, 0
	li 		$a2, 0
	syscall
	bltz 	$v0, openError		# si ocurre un error al abrir el archivo, finaliza programa
	move 	$v1, $v0

	# Read input from file
	li	 	$v0, 14
	move 	$a0, $v1			# file descriptor
	lw 		$a1, buffer
	add 	$a2, $t5, $zero
	syscall
	bltz 	$v0, readError		# si ocurre un error al leer, finaliza programa

	# Calculamos pixel posterior al de la esquina inferior derecha.
	# el cual viene dado por (anchura * 4) * (altura)
	sll 	$t5, $t0, 2
	mul 	$t1, $t5, $t0
	move 	$s1, $t1

#-------------------------------->-------------------------------->-------------------------------->
# Pintamos el rompecabeza en el bitmap display
	li  	$a1, 0x10040000		# direccion base bitmap display
	li 		$t1, 0 				# posicion actual dentro del archivo
	li 		$t2, 0				# pixel a pintar en iteracion actual, 

loop:
	bge   	$t2, $s1, iniMove
	getColor ($t1)				# Consigue el color actual dentro del archivo leido
	paintalo ($t2)				# pinta el pixel actual
	addi 	$t1, $t1, 4			# ve hacia el siguiente color
	addi 	$t2, $t2, 4			# avanza una palabra en el bitmap display
	b 		loop
#-------------------------------->-------------------------------->-------------------------------->
# Calculemos el pixel de la esquina inferior derecha
# La cual viene dada por $s1-4
iniMove:
	subi 	$s7, $s1, 4			# $s7 es la posicion de la esquina inferior derecha 
								# de la casilla sobre la que estoy situado en el rompecabezas
	mul		$s2, $t0, $t0		# ancho * alto

	print_str (msg5)
interrupciones:
	# Activar las interrupciones
	mfc0 $s0, $12
	ori $s0, $s0, 0x301
	mtc0 $s0, $12

	# Encender las interrupciones
	lw $s0, 0xffff0000
	ori $s0, $s0, 2
	sw $s0, 0xffff0000

# Menu para mover casillas
waitingMove:
	move	$s3, $s7
	lb 	$t9, movement
	beq 	$t9, -1, waitingMove
	# Movimiento Invalido
		blez 	$t9, waitingMove
		li 		$t1, 6
		bgt 	$t9, $t1, waitingMove
		li 		$t1, 1
	# Moverse hacia:	
		beq 	$t9, $t1, up
		li 		$t1, 2
		beq 	$t9, $t1, left
		li		$t1, 3
		beq 	$t9, $t1, right
		li		$t1, 4
		beq 	$t9, $t1, down
	# Otras Opciones
		li		$t1, 5
		beq 	$t9, $t1, bye
		li		$t1, 6
		beq 	$t9, $t1, help
	
# Mover una casilla del rompecabeza	
exchange:
	print_str (msg5)
	# Indicar que se ha presionado una tecla
		li $a0, -1
		sb $a0, movement
	move	$s7, $s4			# actualiza el valor de $s7 para la casilla a la que nos movemos
	li		$t1, 4				# contador
	li		$t7, 0				# contador
	mul		$t2, $t0, $t0		# t2 es ancho por alto, capaz esta demas
	
swap:
	bge 	$t1, $t2, waitingMove	# condicion de parada: si contador $t1 es mayor igual a el anchoXalto go to waitingMove
	paintaloTwo ()					# Intercambiar colores $s3 con $s4
	# ahora desplazate una columna hacia la izquierda en ambas casillas
		sub		$s5, $s3, $t1			
		sub		$s6, $s4, $t1
	addi 	$t1, $t1, 4				# aumenta $t1 en 4
	addi 	$t7, $t7, 4				# aumenta $t7 en 4
	beq 	$t7, $t0, condition		# si $t7 es mayor al ancho del rompecabeza entonces sube una fila 
									# dentro de esta casilla y desplazate hacia su ultima columna columna
	b 		swap

condition:
	sub		$t1, $t1, $t0			# reinicia columna inicial
	add		$t1, $t1, $t5			# sube una fila dentro de la casilla acutal
	li		$t7, 0					# reinicia contador
	b		swap	
	
up:
	# Verificacion de movimiento valido
		add		$t8, $s2, $t0
		sub		$t8, $t8, $t5
		subi	$t8, $t8, 4
		beq 	$s3, $t8, waitingMove
		add		$t8, $t8, $t0 
		beq 	$s3, $t8, waitingMove
		add		$t8, $t8, $t0 
		beq 	$s3, $t8, waitingMove
		add		$t8, $t8, $t0 
		beq 	$s3, $t8, waitingMove
	
	# nos desplazamos al cuadro de arriba en la misma esquina
	sub		$s4, $s3, $s2
	b		exchange
	
left:
	# Verificacion de movimiento valido
		add		$t8, $s2, $t0
		sub		$t8, $t8, $t5
		subi	$t8, $t8, 4
		beq 	$s3, $t8, waitingMove
		add		$t8, $t8, $s2
		beq 	$s3, $t8, waitingMove
		add		$t8, $t8, $s2
		beq 	$s3, $t8, waitingMove
		add		$t8, $t8, $s2
		beq 	$s3, $t8, waitingMove
	
	# nos desplazamos al cuadro izquierda en la misma esquina	
	sub		$s4, $s3, $t0
	b		exchange
	
right:
	# Verificacion de movimiento valido
		subi	$t8, $s1, 4
		beq 	$s3, $t8, waitingMove
		sub		$t8, $t8, $s2
		beq 	$s3, $t8, waitingMove
		sub		$t8, $t8, $s2
		beq 	$s3, $t8, waitingMove
		sub		$t8, $t8, $s2
		beq 	$s3, $t8, waitingMove

	# nos desplazamos al cuadro derecha en la misma esquina
	add		$s4, $s3, $t0
	b		exchange
	
down:
	# Verificacion de movimiento valido
		add		$t8, $s1, $t0
		sub		$t8, $t8, $t5 
		subi	$t8, $t8, 4 
		beq 	$s3, $t8, waitingMove
		add		$t8, $t8, $t0 
		beq 	$s3, $t8, waitingMove
		add		$t8, $t8, $t0 
		beq 	$s3, $t8, waitingMove
		add		$t8, $t8, $t0 
		beq 	$s3, $t8, waitingMove
	
	# nos desplazamos al cuadro de abajo en la misma esquina
	add		$s4, $s3, $s2
	b		exchange
#-------------------------------->-------------------------------->-------------------------------->
# Muestra informacion del juego al usuario si se presiona la tecla h
help:
	# Indicar que se ha presionado una tecla
		li $a0, -1
		sb $a0, movement
	print_str (msg10)
	b 		waitingMove

#-------------------------------->-------------------------------->-------------------------------->
# Cerrar el archivo
bye:
	print_str (msg11)
	li 		$v0, 16
	move 	$a0, $v1			# file descriptor to close
	syscall
	jr 	$ra	
	
# Cerrar programa si falla al abrir imagen		
openError:
	print_str (msg2)
	j 	endProgram

# Cerrar programa si falla al leer imagen		
readError:
	print_str (msg3)
	j 	endProgram

# Cerrar programa si la imagen no es bmp		
fileNotAllow:
	print_str (msg4)
	j 	endProgram

# Finalizar Programa
endProgram: 
	li 	$v0, 10
	syscall
