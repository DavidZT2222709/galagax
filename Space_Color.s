@ ============================================================
@ space_ship.s
@ Nave espacial con GALAXIAS REALISTAS y PROPULSORES ANIMADOS
@ Movimiento con flechas del teclado (PS/2) por interrupciones
@ ARMv7 - DE1-SoC / CPUlator
@ ============================================================

.equ FB_BASE,  0xC8000000

@ Colores fondo
.equ C_BLACK,  0x0000
.equ C_WHITE,  0xFFFF
.equ C_BLUE_P, 0x9CF3
.equ C_YELLOW, 0xFFE0
.equ C_GRAY,   0x4208

@ Tamaño del sprite (aumentado el alto para el fuego)
.equ SHIP_W,  32
.equ SHIP_H,  36

@ ============================================================
@ TABLA DE VECTORES
@ ============================================================
.section .vectors, "ax"
    B   _start
    B   SERVICE_UND
    B   SERVICE_SVC
    B   SERVICE_ABT_INST
    B   SERVICE_ABT_DATA
    .word 0
    B   SERVICE_IRQ
    B   SERVICE_FIQ

@ ============================================================
.text
.global _start
_start:
    @ ---- Pilas para modos IRQ y SVC ------------------------
    MOV  R1, #0b11010010        @ modo IRQ, IRQ/FIQ deshab.
    MSR  CPSR_c, R1
    LDR  SP, =0xFFFFEFFC

    MOV  R0, #0b11010011        @ modo SVC, IRQ/FIQ deshab.
    MSR  CPSR_c, R0
    LDR  SP, =0xFFFFFFFC

    @ ---- Pintar fondo (una sola vez) -----------------------
    BL   DRAW_BACKGROUND

    @ ---- Inicializar posición y estados -------------------
    LDR  R0, =ship_x
    MOV  R1, #144
    STR  R1, [R0]
    LDR  R0, =ship_y
    MOV  R1, #204               @ Ajustado por el nuevo SHIP_H
    STR  R1, [R0]

    MOV  R1, #0
    LDR  R0, =key_up
    STR  R1, [R0]
    LDR  R0, =key_down
    STR  R1, [R0]
    LDR  R0, =key_left
    STR  R1, [R0]
    LDR  R0, =key_right
    STR  R1, [R0]
    LDR  R0, =e0_flag_ps2
    STR  R1, [R0]
    LDR  R0, =break_flag
    STR  R1, [R0]
    LDR  R0, =anim_frame
    STR  R1, [R0]
    LDR  R0, =redraw_flag
    STR  R1, [R0]

    @ ---- Guardar fondo y pintar nave por primera vez -------
    BL   SAVE_BG
    BL   DRAW_SHIP

    @ ---- Configurar interrupciones -------------------------
    BL   SET_IRQs
    BL   CONFIG_INTERVAL_TIMER
    BL   CONFIG_PS2

    @ Habilitar IRQs en CPSR (modo SVC con IRQ habilitado)
    MOV  R1, #0b01010011
    MSR  CPSR_c, R1

@ ============================================================
@ MAIN LOOP
@ ============================================================
MAIN_LOOP:
    @ ---- Calcular dx ---------------------------------------
    LDR  R0, =key_right
    LDR  R0, [R0]
    LDR  R1, =key_left
    LDR  R1, [R1]
    SUB  R6, R0, R1             @ R6 = dir_x  (-1, 0, +1)
    LSL  R6, R6, #2             @ * STEP(4)

    @ ---- Calcular dy ---------------------------------------
    LDR  R0, =key_down
    LDR  R0, [R0]
    LDR  R1, =key_up
    LDR  R1, [R1]
    SUB  R7, R0, R1             @ R7 = dir_y  (-1, 0, +1)
    LSL  R7, R7, #2             @ * STEP(4)

    @ ---- Si hay movimiento ---------------------------------
    ORRS R0, R6, R7
    BNE  DO_MOVE

    @ ---- Si no hay movimiento, revisar bandera del TIMER ---
    LDR  R0, =redraw_flag
    LDR  R1, [R0]
    CMP  R1, #1
    BEQ  DO_REDRAW_STATIC
    B    MAIN_WAIT

DO_MOVE:
    @ Restaurar fondo viejo ANTES de mover variables
    BL   RESTORE_BG

    @ ---- Aplicar dx con clamping --------------------------
    LDR  R0, =ship_x
    LDR  R4, [R0]
    ADD  R4, R4, R6
    CMP  R4, #0
    MOVLT R4, #0
    LDR  R5, =320-SHIP_W
    CMP  R4, R5
    MOVGT R4, R5
    STR  R4, [R0]

    @ ---- Aplicar dy con clamping --------------------------
    LDR  R0, =ship_y
    LDR  R4, [R0]
    ADD  R4, R4, R7
    CMP  R4, #0
    MOVLT R4, #0
    LDR  R5, =240-SHIP_H
    CMP  R4, R5
    MOVGT R4, R5
    STR  R4, [R0]

    @ Guardar fondo nuevo y repintar
    BL   SAVE_BG
    LDR  R0, =redraw_flag       @ Limpiamos flag porque ya repintamos
    MOV  R1, #0
    STR  R1, [R0]
    BL   DRAW_SHIP
    B    MAIN_WAIT

DO_REDRAW_STATIC:
    @ Repintar solo para animar el fuego en el sitio actual
    MOV  R1, #0
    STR  R1, [R0]               @ Limpiar flag de redibujo
    BL   RESTORE_BG             @ Borrar nave (recuperando fondo limpio)
    BL   DRAW_SHIP              @ Dibujar nave con nuevo propulsor
    B    MAIN_WAIT

MAIN_WAIT:
    BL   DELAY
    B    MAIN_LOOP

@ ============================================================
@ DELAY
@ ============================================================
DELAY:
    PUSH {R0, LR}
    LDR  R0, =200000
DELAY_LOOP:
    SUBS R0, R0, #1
    BNE  DELAY_LOOP
    POP  {R0, LR}
    BX   LR

@ ============================================================
@ DRAW_SHIP
@ Dibuja la carcasa base de la nave, y luego escoge el frame
@ del fuego dependiendo de anim_frame.
@ ============================================================
DRAW_SHIP:
    PUSH {R4-R10, LR}
    LDR  R4, =FB_BASE
    LDR  R5, =ship_x
    LDR  R5, [R5]               @ x
    LDR  R6, =ship_y
    LDR  R6, [R6]               @ y

    LSL  R7, R6, #10
    ADD  R7, R7, R5, LSL #1     @ R7 = base_offset
    ADD  R7, R7, R4             @ R7 = puntero FB

    @ --- 1) Dibujar cuerpo de la nave ---
    LDR  R8, =ship_base_sprite
    LDR  R9, =ship_base_end
DS_LOOP1:
    CMP  R8, R9
    BGE  DS_SEL_THRUSTER
    LDR  R10, [R8], #4          @ offset
    LDR  R0,  [R8], #4          @ color
    ADD  R10, R10, R7
    STRH R0,  [R10]
    B    DS_LOOP1

DS_SEL_THRUSTER:
    @ --- 2) Dibujar fuego animado ---
    LDR  R0, =anim_frame
    LDR  R0, [R0]
    CMP  R0, #0
    BNE  DS_CHK_T2
    LDR  R8, =thruster_1
    LDR  R9, =thruster_1_end
    B    DS_LOOP2
DS_CHK_T2:
    CMP  R0, #1
    BNE  DS_CHK_T3
    LDR  R8, =thruster_2
    LDR  R9, =thruster_2_end
    B    DS_LOOP2
DS_CHK_T3:
    LDR  R8, =thruster_3
    LDR  R9, =thruster_3_end

DS_LOOP2:
    CMP  R8, R9
    BGE  DS_DONE
    LDR  R10, [R8], #4          @ offset
    LDR  R0,  [R8], #4          @ color
    ADD  R10, R10, R7
    STRH R0,  [R10]
    B    DS_LOOP2

DS_DONE:
    POP  {R4-R10, LR}
    BX   LR

@ ============================================================
@ SAVE_BG / RESTORE_BG
@ Modificados para SHIP_H = 36
@ ============================================================
SAVE_BG:
    PUSH {R4-R10, LR}
    LDR  R4, =FB_BASE
    LDR  R5, =ship_x
    LDR  R5, [R5]
    LDR  R6, =ship_y
    LDR  R6, [R6]

    LSL  R7, R6, #10
    ADD  R7, R7, R5, LSL #1
    ADD  R7, R7, R4

    LDR  R8, =bg_buffer
    MOV  R9, #SHIP_H
SB_ROW:
    CMP  R9, #0
    BEQ  SB_DONE
    MOV  R10, #SHIP_W
    MOV  R0, R7
SB_COL:
    CMP  R10, #0
    BEQ  SB_NEXT
    LDRH R1, [R0], #2
    STRH R1, [R8], #2
    SUB  R10, R10, #1
    B    SB_COL
SB_NEXT:
    ADD  R7, R7, #1024
    SUB  R9, R9, #1
    B    SB_ROW
SB_DONE:
    POP  {R4-R10, LR}
    BX   LR

RESTORE_BG:
    PUSH {R4-R10, LR}
    LDR  R4, =FB_BASE
    LDR  R5, =ship_x
    LDR  R5, [R5]
    LDR  R6, =ship_y
    LDR  R6, [R6]

    LSL  R7, R6, #10
    ADD  R7, R7, R5, LSL #1
    ADD  R7, R7, R4

    LDR  R8, =bg_buffer
    MOV  R9, #SHIP_H
RB_ROW:
    CMP  R9, #0
    BEQ  RB_DONE
    MOV  R10, #SHIP_W
    MOV  R0, R7
RB_COL:
    CMP  R10, #0
    BEQ  RB_NEXT
    LDRH R1, [R8], #2
    STRH R1, [R0], #2
    SUB  R10, R10, #1
    B    RB_COL
RB_NEXT:
    ADD  R7, R7, #1024
    SUB  R9, R9, #1
    B    RB_ROW
RB_DONE:
    POP  {R4-R10, LR}
    BX   LR

@ ============================================================
@ DRAW_BACKGROUND
@ ============================================================
DRAW_BACKGROUND:
    PUSH {R0-R12, LR}
    LDR  R4, =FB_BASE
    MOV  R5, #0
    LDR  R6, =131072
DB_CLEAR:
    SUBS R6, R6, #1
    BMI  DB_CLEAR_DONE
    STRH R5, [R4], #2
    B    DB_CLEAR
DB_CLEAR_DONE:

    LDR  R6, =FB_BASE
    LDR  R7, =galaxies_data
    LDR  R8, =galaxies_data_end
DB_GALAXIES_LOOP:
    CMP  R7, R8
    BGE  DB_WHITE_INIT       
    LDR  R4, [R7], #4        
    LDR  R5, [R7], #4        
    ADD  R3, R4, R6
    STRH R5, [R3]
    B    DB_GALAXIES_LOOP

DB_WHITE_INIT:
    LDR  R6, =FB_BASE
    LDR  R7, =stars_white
    LDR  R8, =stars_white_end
    MOV  R5, #C_WHITE
DB_WHITE:
    CMP  R7, R8
    BGE  DB_BLUE
    LDR  R4, [R7], #4
    ADD  R3, R4, R6
    STRH R5, [R3]
    B    DB_WHITE

DB_BLUE:
    LDR  R7, =stars_blue
    LDR  R8, =stars_blue_end
    LDR  R5, val_blue
DB_BLUE_LOOP:
    CMP  R7, R8
    BGE  DB_YELLOW
    LDR  R4, [R7], #4
    ADD  R3, R4, R6
    STRH R5, [R3]
    B    DB_BLUE_LOOP

DB_YELLOW:
    LDR  R7, =stars_yellow
    LDR  R8, =stars_yellow_end
    LDR  R5, val_yellow
DB_YELLOW_LOOP:
    CMP  R7, R8
    BGE  DB_MED
    LDR  R4, [R7], #4
    ADD  R3, R4, R6
    STRH R5, [R3]
    B    DB_YELLOW_LOOP

DB_MED:
    LDR  R7,  =stars_med
    LDR  R8,  =stars_med_end
    LDR  R11, val_stride
DB_MED_LOOP:
    CMP  R7, R8
    BGE  DB_LARGE
    LDR  R4, [R7], #4
    LDR  R9, [R7], #4
    ADD  R3, R4, R6
    STRH R9, [R3]
    MOV  R5, #C_GRAY
    SUB  R3, R4, #2 ; ADD R3, R3, R6 ; STRH R5, [R3]
    ADD  R3, R4, #2 ; ADD R3, R3, R6 ; STRH R5, [R3]
    SUB  R3, R4, R11; ADD R3, R3, R6 ; STRH R5, [R3]
    ADD  R3, R4, R11; ADD R3, R3, R6 ; STRH R5, [R3]
    B    DB_MED_LOOP

DB_LARGE:
    LDR  R7,  =stars_large
    LDR  R8,  =stars_large_end
    LDR  R11, val_stride
    LSL  R12, R11, #1
    MOV  R5,  #C_WHITE
    MOV  R10, #C_GRAY
DB_LARGE_LOOP:
    CMP  R7, R8
    BGE  DB_DONE
    LDR  R4, [R7], #4
    ADD  R3, R4, R6 ; STRH R5, [R3]
    SUB  R3, R4, #2 ; ADD R3, R3, R6 ; STRH R5, [R3]
    ADD  R3, R4, #2 ; ADD R3, R3, R6 ; STRH R5, [R3]
    SUB  R3, R4, R11; ADD R3, R3, R6 ; STRH R5, [R3]
    ADD  R3, R4, R11; ADD R3, R3, R6 ; STRH R5, [R3]
    SUB  R3, R4, #4 ; ADD R3, R3, R6 ; STRH R10,[R3]
    ADD  R3, R4, #4 ; ADD R3, R3, R6 ; STRH R10,[R3]
    SUB  R3, R4, R12; ADD R3, R3, R6 ; STRH R10,[R3]
    ADD  R3, R4, R12; ADD R3, R3, R6 ; STRH R10,[R3]
    B    DB_LARGE_LOOP

DB_DONE:
    POP  {R0-R12, LR}
    BX   LR

@ ============================================================
@ SET_IRQs / CONFIG_GIC
@ ============================================================
SET_IRQs:
    PUSH {LR}
    MOV  R0, #72
    BL   CONFIG_GIC
    MOV  R0, #79
    BL   CONFIG_GIC
    POP  {PC}

CONFIG_INTERVAL_TIMER:
    PUSH {LR}
    LDR  R0, =0xFF202000
    @ Configurar para 5,000,000 ciclos = 0.05s (20 Hz) para buen parpadeo de fuego
    @ 5,000,000 = 0x004C4B40
    LDR  R1, =0x4B40
    STR  R1, [R0, #0x08]
    LDR  R1, =0x004C
    STR  R1, [R0, #0x0C]
    MOV  R1, #7
    STR  R1, [R0, #0x04]
    POP  {PC}

CONFIG_PS2:
    PUSH {LR}
    LDR  R0, =0xFF200100
    MOV  R1, #1
    STR  R1, [R0, #0x04]
    POP  {PC}

.global CONFIG_GIC
CONFIG_GIC:
    PUSH {LR}
    MOV  R1, #1
    BL   CONFIG_INTERRUPT
    LDR  R0, =0xFFFEC100
    LDR  R1, =0xFFFF
    STR  R1, [R0, #0x04]
    MOV  R1, #1
    STR  R1, [R0]
    LDR  R0, =0xFFFED000
    STR  R1, [R0]
    POP  {PC}

CONFIG_INTERRUPT:
    PUSH {R4-R5, LR}
    LSR  R4, R0, #3
    BIC  R4, R4, #3
    LDR  R2, =0xFFFED100
    ADD  R4, R2, R4
    AND  R2, R0, #0x1F
    MOV  R5, #1
    LSL  R2, R5, R2
    LDR  R3, [R4]
    ORR  R3, R3, R2
    STR  R3, [R4]
    BIC  R4, R0, #3
    LDR  R2, =0xFFFED800
    ADD  R4, R2, R4
    AND  R2, R0, #0x3
    ADD  R4, R2, R4
    STRB R1, [R4]
    POP  {R4-R5, PC}

@ ============================================================
@ SERVICE_IRQ
@ ============================================================
.global SERVICE_IRQ
SERVICE_IRQ:
    PUSH {R0-R7, LR}
    LDR  R4, =0xFFFEC100
    LDR  R5, [R4, #0x0C]

    CMP  R5, #72
    BNE  IRQ_CHK_PS2
    BL   TIMER_ISR
    B    EXIT_IRQ
IRQ_CHK_PS2:
    CMP  R5, #79
    BNE  IRQ_OTHER
    BL   PS2_ISR
    B    EXIT_IRQ
IRQ_OTHER:
EXIT_IRQ:
    STR  R5, [R4, #0x10]
    POP  {R0-R7, LR}
    SUBS PC, LR, #4

@ ============================================================
@ TIMER_ISR
@ Actualiza el frame de animación y solicita un redibujo.
@ ============================================================
.global TIMER_ISR
TIMER_ISR:
    PUSH {R0-R2, LR}
    LDR  R0, =0xFF202000
    MOV  R1, #0
    STR  R1, [R0]               @ Limpiar IRQ

    @ Avanzar anim_frame (0 -> 1 -> 2 -> 0)
    LDR  R0, =anim_frame
    LDR  R1, [R0]
    ADD  R1, R1, #1
    CMP  R1, #3
    MOVGE R1, #0
    STR  R1, [R0]

    @ Notificar al MAIN_LOOP que hay que repintar
    LDR  R0, =redraw_flag
    MOV  R2, #1
    STR  R2, [R0]

    POP  {R0-R2, LR}
    BX   LR

@ ============================================================
@ PS2_ISR 
@ ============================================================
.equ STEP, 4

.global PS2_ISR
PS2_ISR:
    PUSH {R0-R5, LR}
    LDR  R0, =0xFF200100
    LDR  R1, [R0]
    TST  R1, #0x8000
    BEQ  PS2_END

    AND  R0, R1, #0xFF
    LDR  R1, =break_flag
    LDR  R2, [R1]
    CMP  R2, #1
    BNE  PS2_NO_BREAK

    MOV  R2, #0
    STR  R2, [R1]
    LDR  R1, =e0_flag_ps2
    STR  R2, [R1]
    BL   SET_KEY_FLAG_ZERO
    B    PS2_END

PS2_NO_BREAK:
    CMP  R0, #0xF0
    BNE  PS2_NO_F0
    MOV  R2, #1
    STR  R2, [R1]
    B    PS2_END

PS2_NO_F0:
    LDR  R1, =e0_flag_ps2
    LDR  R2, [R1]
    CMP  R2, #1
    BEQ  PS2_EXT_MAKE

    CMP  R0, #0xE0
    BNE  PS2_END
    MOV  R2, #1
    STR  R2, [R1]
    B    PS2_END

PS2_EXT_MAKE:
    MOV  R2, #0
    STR  R2, [R1]
    BL   SET_KEY_FLAG_ONE
    B    PS2_END

PS2_END:
    POP  {R0-R5, LR}
    BX   LR

@ ============================================================
@ Helpers PS2
@ ============================================================
SET_KEY_FLAG_ONE:
    PUSH {R3-R4, LR}
    MOV  R4, #1
    B    SKF_DISPATCH

SET_KEY_FLAG_ZERO:
    PUSH {R3-R4, LR}
    MOV  R4, #0

SKF_DISPATCH:
    CMP  R0, #0x75              @ UP
    BNE  SKF_TRY_DOWN
    LDR  R3, =key_up
    STR  R4, [R3]
    B    SKF_END
SKF_TRY_DOWN:
    CMP  R0, #0x72              @ DOWN
    BNE  SKF_TRY_LEFT
    LDR  R3, =key_down
    STR  R4, [R3]
    B    SKF_END
SKF_TRY_LEFT:
    CMP  R0, #0x6B              @ LEFT
    BNE  SKF_TRY_RIGHT
    LDR  R3, =key_left
    STR  R4, [R3]
    B    SKF_END
SKF_TRY_RIGHT:
    CMP  R0, #0x74              @ RIGHT
    BNE  SKF_END
    LDR  R3, =key_right
    STR  R4, [R3]
SKF_END:
    POP  {R3-R4, LR}
    BX   LR

@ ============================================================
@ MANEJADORES DE EXCEPCIONES NO USADOS
@ ============================================================
.global SERVICE_UND
SERVICE_UND:      B SERVICE_UND
.global SERVICE_SVC
SERVICE_SVC:      B SERVICE_SVC
.global SERVICE_ABT_DATA
SERVICE_ABT_DATA: B SERVICE_ABT_DATA
.global SERVICE_ABT_INST
SERVICE_ABT_INST: B SERVICE_ABT_INST
.global SERVICE_FIQ
SERVICE_FIQ:      B SERVICE_FIQ

@ ============================================================
@ Literales
@ ============================================================
val_stride: .word 1024
val_blue:   .word C_BLUE_P
val_yellow: .word C_YELLOW

@ ============================================================
@ DATA
@ ============================================================
.data
.align 2

@ ---- Variables de la nave / IRQ ----------------------------
ship_x:        .word 144
ship_y:        .word 204
key_up:        .word 0
key_down:      .word 0
key_left:      .word 0
key_right:     .word 0
e0_flag_ps2:   .word 0
break_flag:    .word 0
anim_frame:    .word 0
redraw_flag:   .word 0

@ ---- Buffer del fondo (32 W * 36 H * 2 bytes = 2304) -------
.align 2
bg_buffer:
    .skip 3000

@ ============================================================
@ TABLAS DE ESTRELLAS
@ ============================================================
stars_white:
    .word  (3<<10)  + (12 <<1); .word  (3<<10)  + (288<<1)
    .word  (7<<10)  + (55 <<1); .word  (7<<10)  + (155<<1); .word  (7<<10)  + (255<<1)
    .word  (12<<10) + (90 <<1); .word  (12<<10) + (200<<1); .word  (12<<10) + (312<<1)
    .word  (17<<10) + (35 <<1); .word  (17<<10) + (175<<1)
    .word  (22<<10) + (275<<1)
    .word  (28<<10) + (68 <<1); .word  (28<<10) + (195<<1)
    .word  (33<<10) + (310<<1)
    .word  (38<<10) + (22 <<1); .word  (38<<10) + (138<<1)
    .word  (43<<10) + (248<<1)
    .word  (48<<10) + (78 <<1)
    .word  (55<<10) + (302<<1)
    .word  (60<<10) + (172<<1)
    .word  (65<<10) + (12 <<1)
    .word  (70<<10) + (225<<1)
    .word  (75<<10) + (92 <<1)
    .word  (80<<10) + (318<<1)
    .word  (85<<10) + (148<<1)
    .word  (90<<10) + (38 <<1)
    .word  (95<<10) + (268<<1)
    .word  (100<<10)+ (108<<1)
    .word  (108<<10)+ (222<<1)
    .word  (115<<10)+ (52 <<1)
    .word  (120<<10)+ (285<<1)
    .word  (125<<10)+ (165<<1)
    .word  (130<<10)+ (28 <<1)
    .word  (135<<10)+ (298<<1)
    .word  (140<<10)+ (118<<1)
    .word  (145<<10)+ (238<<1)
    .word  (150<<10)+ (75 <<1)
    .word  (155<<10)+ (192<<1)
    .word  (162<<10)+ (312<<1)
    .word  (170<<10)+ (48 <<1)
    .word  (175<<10)+ (218<<1)
    .word  (180<<10)+ (138<<1)
    .word  (185<<10)+ (18 <<1)
    .word  (190<<10)+ (268<<1)
    .word  (196<<10)+ (98 <<1)
    .word  (202<<10)+ (188<<1)
    .word  (210<<10)+ (58 <<1)
    .word  (216<<10)+ (278<<1)
    .word  (222<<10)+ (155<<1)
    .word  (228<<10)+ (42 <<1)
    .word  (234<<10)+ (300<<1)
stars_white_end:

stars_blue:
    .word  (5 <<10) + (168<<1); .word  (14<<10) + (308<<1)
    .word  (25<<10) + (228<<1); .word  (37<<10) + (108<<1)
    .word  (50<<10) + (282<<1); .word  (62<<10) + (42 <<1)
    .word  (74<<10) + (205<<1); .word  (86<<10) + (128<<1)
    .word  (98<<10) + (318<<1); .word  (110<<10)+ (18 <<1)
    .word  (122<<10)+ (258<<1); .word  (135<<10)+ (88 <<1)
    .word  (148<<10)+ (308<<1); .word  (160<<10)+ (148<<1)
    .word  (172<<10)+ (22 <<1); .word  (184<<10)+ (202<<1)
    .word  (196<<10)+ (68 <<1); .word  (208<<10)+ (248<<1)
    .word  (220<<10)+ (118<<1); .word  (232<<10)+ (38 <<1)
stars_blue_end:

stars_yellow:
    .word  (10<<10) + (42 <<1); .word  (32<<10) + (268<<1)
    .word  (58<<10) + (155<<1); .word  (82<<10) + (62 <<1)
    .word  (105<<10)+ (188<<1); .word  (128<<10)+ (32 <<1)
    .word  (152<<10)+ (252<<1); .word  (175<<10)+ (112<<1)
    .word  (198<<10)+ (298<<1); .word  (220<<10)+ (78 <<1)
stars_yellow_end:

stars_med:
    .word (22 <<10)+(148<<1), 0x0000FFFF
    .word (50 <<10)+(35 <<1), 0x0000FFE0
    .word (78 <<10)+(295<<1), 0x0000FFFF
    .word (105<<10)+(82 <<1), 0x0000FFE0
    .word (132<<10)+(218<<1), 0x0000FFFF
    .word (158<<10)+(52 <<1), 0x0000FFE0
    .word (185<<10)+(272<<1), 0x0000FFFF
    .word (212<<10)+(138<<1), 0x0000FFE0
    .word (238<<10)+(305<<1), 0x0000FFFF
stars_med_end:

stars_large:
    .word (15 <<10)+(245<<1); .word (58 <<10)+(98 <<1)
    .word (105<<10)+(298<<1); .word (152<<10)+(48 <<1)
    .word (195<<10)+(198<<1); .word (230<<10)+(82 <<1)
    .word (68 <<10)+(175<<1)
stars_large_end:

@ ============================================================
@ CUERPO BASE DE LA NAVE (Sin fuego)
@ ============================================================
ship_base_sprite:
    .word 0x0000081E, 0x18C3; .word 0x00000820, 0x18C3
    .word 0x00000C1C, 0x18C3; .word 0x00000C1E, 0x9CD3; .word 0x00000C20, 0x9CD3; .word 0x00000C22, 0x18C3
    .word 0x0000101C, 0x18C3; .word 0x0000101E, 0x9CD3; .word 0x00001020, 0x9CD3; .word 0x00001022, 0x18C3
    .word 0x0000141A, 0x18C3; .word 0x0000141C, 0x18C3; .word 0x0000141E, 0x9CD3; .word 0x00001420, 0x9CD3; .word 0x00001422, 0x18C3; .word 0x00001424, 0x18C3
    .word 0x0000181A, 0x18C3; .word 0x0000181C, 0x9CD3; .word 0x0000181E, 0xDEDB; .word 0x00001820, 0xDEDB; .word 0x00001822, 0x9CD3; .word 0x00001824, 0x18C3
    .word 0x00001C1A, 0x18C3; .word 0x00001C1C, 0x9CD3; .word 0x00001C1E, 0x05B6; .word 0x00001C20, 0x05B6; .word 0x00001C22, 0x9CD3; .word 0x00001C24, 0x18C3
    .word 0x0000201A, 0x18C3; .word 0x0000201C, 0x9CD3; .word 0x0000201E, 0x07FF; .word 0x00002020, 0x07FF; .word 0x00002022, 0x9CD3; .word 0x00002024, 0x18C3
    .word 0x00002418, 0x18C3; .word 0x0000241A, 0x18C3; .word 0x0000241C, 0x9CD3; .word 0x0000241E, 0x07FF; .word 0x00002420, 0x07FF; .word 0x00002422, 0x9CD3; .word 0x00002424, 0x18C3; .word 0x00002426, 0x18C3
    .word 0x00002816, 0x18C3; .word 0x00002818, 0x18C3; .word 0x0000281A, 0x9CD3; .word 0x0000281C, 0x9CD3; .word 0x0000281E, 0x07FF; .word 0x00002820, 0x07FF; .word 0x00002822, 0x9CD3; .word 0x00002824, 0x9CD3; .word 0x00002826, 0x18C3; .word 0x00002828, 0x18C3
    .word 0x00002C16, 0x18C3; .word 0x00002C18, 0x9CD3; .word 0x00002C1A, 0x9CD3; .word 0x00002C1C, 0x9CD3; .word 0x00002C1E, 0x07FF; .word 0x00002C20, 0x07FF; .word 0x00002C22, 0x9CD3; .word 0x00002C24, 0x9CD3; .word 0x00002C26, 0x9CD3; .word 0x00002C28, 0x18C3
    .word 0x00003014, 0x18C3; .word 0x00003016, 0x18C3; .word 0x00003018, 0x9CD3; .word 0x0000301A, 0x6B6D; .word 0x0000301C, 0x9CD3; .word 0x0000301E, 0x07FF; .word 0x00003020, 0x07FF; .word 0x00003022, 0x9CD3; .word 0x00003024, 0x6B6D; .word 0x00003026, 0x9CD3; .word 0x00003028, 0x18C3; .word 0x0000302A, 0x18C3
    .word 0x00003412, 0x18C3; .word 0x00003414, 0x18C3; .word 0x00003416, 0x9CD3; .word 0x00003418, 0x6B6D; .word 0x0000341A, 0xDEDB; .word 0x0000341C, 0xDEDB; .word 0x0000341E, 0x9CD3; .word 0x00003420, 0x9CD3; .word 0x00003422, 0xDEDB; .word 0x00003424, 0xDEDB; .word 0x00003426, 0x6B6D; .word 0x00003428, 0x9CD3; .word 0x0000342A, 0x18C3; .word 0x0000342C, 0x18C3
    .word 0x00003810, 0x18C3; .word 0x00003812, 0x9CD3; .word 0x00003814, 0x6B6D; .word 0x00003816, 0x6B6D; .word 0x00003818, 0xDEDB; .word 0x0000381A, 0xDEDB; .word 0x0000381C, 0xDEDB; .word 0x0000381E, 0x6B6D; .word 0x00003820, 0x6B6D; .word 0x00003822, 0xDEDB; .word 0x00003824, 0xDEDB; .word 0x00003826, 0xDEDB; .word 0x00003828, 0x6B6D; .word 0x0000382A, 0x6B6D; .word 0x0000382C, 0x9CD3; .word 0x0000382E, 0x18C3
    .word 0x00003C0E, 0x18C3; .word 0x00003C10, 0x9CD3; .word 0x00003C12, 0x39E7; .word 0x00003C14, 0x6B6D; .word 0x00003C16, 0x6B6D; .word 0x00003C18, 0xDEDB; .word 0x00003C1A, 0xDEDB; .word 0x00003C1C, 0xDEDB; .word 0x00003C1E, 0x6B6D; .word 0x00003C20, 0x6B6D; .word 0x00003C22, 0xDEDB; .word 0x00003C24, 0xDEDB; .word 0x00003C26, 0xDEDB; .word 0x00003C28, 0x6B6D; .word 0x00003C2A, 0x6B6D; .word 0x00003C2C, 0x39E7; .word 0x00003C2E, 0x9CD3; .word 0x00003C30, 0x18C3
    .word 0x0000400C, 0x18C3; .word 0x0000400E, 0x9CD3; .word 0x00004010, 0x39E7; .word 0x00004012, 0x39E7; .word 0x00004014, 0x6B6D; .word 0x00004016, 0x6B6D; .word 0x00004018, 0x6B6D; .word 0x0000401A, 0xDEDB; .word 0x0000401C, 0xDEDB; .word 0x0000401E, 0x6B6D; .word 0x00004020, 0x6B6D; .word 0x00004022, 0xDEDB; .word 0x00004024, 0xDEDB; .word 0x00004026, 0x6B6D; .word 0x00004028, 0x6B6D; .word 0x0000402A, 0x6B6D; .word 0x0000402C, 0x39E7; .word 0x0000402E, 0x39E7; .word 0x00004030, 0x9CD3; .word 0x00004032, 0x18C3
    .word 0x0000440A, 0x18C3; .word 0x0000440C, 0x9CD3; .word 0x0000440E, 0x39E7; .word 0x00004410, 0x39E7; .word 0x00004412, 0x39E7; .word 0x00004414, 0x9CD3; .word 0x00004416, 0x6B6D; .word 0x00004418, 0x6B6D; .word 0x0000441A, 0x6B6D; .word 0x0000441C, 0x6B6D; .word 0x0000441E, 0x6B6D; .word 0x00004420, 0x6B6D; .word 0x00004422, 0x6B6D; .word 0x00004424, 0x6B6D; .word 0x00004426, 0x6B6D; .word 0x00004428, 0x6B6D; .word 0x0000442A, 0x9CD3; .word 0x0000442C, 0x39E7; .word 0x0000442E, 0x39E7; .word 0x00004430, 0x39E7; .word 0x00004432, 0x9CD3; .word 0x00004434, 0x18C3
    .word 0x00004808, 0x18C3; .word 0x0000480A, 0x18C3; .word 0x0000480C, 0x39E7; .word 0x0000480E, 0x39E7; .word 0x00004810, 0x9CD3; .word 0x00004812, 0x9CD3; .word 0x00004814, 0x9CD3; .word 0x00004816, 0x6B6D; .word 0x00004818, 0x6B6D; .word 0x0000481A, 0xDEDB; .word 0x0000481C, 0xDEDB; .word 0x0000481E, 0xDEDB; .word 0x00004820, 0xDEDB; .word 0x00004822, 0xDEDB; .word 0x00004824, 0xDEDB; .word 0x00004826, 0x6B6D; .word 0x00004828, 0x6B6D; .word 0x0000482A, 0x9CD3; .word 0x0000482C, 0x9CD3; .word 0x0000482E, 0x9CD3; .word 0x00004830, 0x39E7; .word 0x00004832, 0x39E7; .word 0x00004834, 0x18C3; .word 0x00004836, 0x18C3
    .word 0x00004C08, 0x18C3; .word 0x00004C0A, 0x39E7; .word 0x00004C0C, 0x39E7; .word 0x00004C0E, 0x9CD3; .word 0x00004C10, 0x9CD3; .word 0x00004C12, 0x9CD3; .word 0x00004C14, 0x9CD3; .word 0x00004C16, 0x6B6D; .word 0x00004C18, 0x6B6D; .word 0x00004C1A, 0xDEDB; .word 0x00004C1C, 0xDEDB; .word 0x00004C1E, 0xDEDB; .word 0x00004C20, 0xDEDB; .word 0x00004C22, 0xDEDB; .word 0x00004C24, 0xDEDB; .word 0x00004C26, 0x6B6D; .word 0x00004C28, 0x6B6D; .word 0x00004C2A, 0x9CD3; .word 0x00004C2C, 0x9CD3; .word 0x00004C2E, 0x9CD3; .word 0x00004C30, 0x9CD3; .word 0x00004C32, 0x39E7; .word 0x00004C34, 0x39E7; .word 0x00004C36, 0x18C3
    .word 0x0000500A, 0x18C3; .word 0x0000500C, 0x18C3; .word 0x0000500E, 0x39E7; .word 0x00005010, 0x39E7; .word 0x00005012, 0x39E7; .word 0x00005014, 0x39E7; .word 0x00005016, 0x6B6D; .word 0x00005018, 0x6B6D; .word 0x0000501A, 0x6B6D; .word 0x0000501C, 0x39E7; .word 0x0000501E, 0x39E7; .word 0x00005020, 0x39E7; .word 0x00005022, 0x39E7; .word 0x00005024, 0x6B6D; .word 0x00005026, 0x6B6D; .word 0x00005028, 0x6B6D; .word 0x0000502A, 0x39E7; .word 0x0000502C, 0x39E7; .word 0x0000502E, 0x39E7; .word 0x00005030, 0x39E7; .word 0x00005032, 0x18C3; .word 0x00005034, 0x18C3
    .word 0x00005410, 0x18C3; .word 0x00005412, 0x18C3; .word 0x00005414, 0x39E7; .word 0x00005416, 0x6B6D; .word 0x00005418, 0x6B6D; .word 0x0000541A, 0x6B6D; .word 0x0000541C, 0x6B6D; .word 0x0000541E, 0x39E7; .word 0x00005420, 0x39E7; .word 0x00005422, 0x6B6D; .word 0x00005424, 0x6B6D; .word 0x00005426, 0x6B6D; .word 0x00005428, 0x6B6D; .word 0x0000542A, 0x39E7; .word 0x0000542C, 0x18C3; .word 0x0000542E, 0x18C3
    .word 0x00005814, 0x18C3; .word 0x00005816, 0x6B6D; .word 0x00005818, 0x6B6D; .word 0x0000581A, 0x6B6D; .word 0x0000581C, 0x6B6D; .word 0x0000581E, 0x39E7; .word 0x00005820, 0x39E7; .word 0x00005822, 0x6B6D; .word 0x00005824, 0x6B6D; .word 0x00005826, 0x6B6D; .word 0x00005828, 0x6B6D; .word 0x0000582A, 0x18C3
    .word 0x00005C14, 0x18C3; .word 0x00005C16, 0x6B6D; .word 0x00005C18, 0x6B6D; .word 0x00005C1A, 0x9CD3; .word 0x00005C1C, 0x9CD3; .word 0x00005C1E, 0x39E7; .word 0x00005C20, 0x39E7; .word 0x00005C22, 0x9CD3; .word 0x00005C24, 0x9CD3; .word 0x00005C26, 0x6B6D; .word 0x00005C28, 0x6B6D; .word 0x00005C2A, 0x18C3
    .word 0x00006010, 0x18C3; .word 0x00006012, 0x18C3; .word 0x00006014, 0x6B6D; .word 0x00006016, 0x6B6D; .word 0x00006018, 0x39E7; .word 0x0000601A, 0x39E7; .word 0x0000601C, 0x39E7; .word 0x0000601E, 0x39E7; .word 0x00006020, 0x39E7; .word 0x00006022, 0x39E7; .word 0x00006024, 0x39E7; .word 0x00006026, 0x39E7; .word 0x00006028, 0x6B6D; .word 0x0000602A, 0x6B6D; .word 0x0000602C, 0x18C3; .word 0x0000602E, 0x18C3
    .word 0x00006410, 0x18C3; .word 0x00006412, 0x6B6D; .word 0x00006414, 0x39E7; .word 0x00006416, 0x9CD3; .word 0x00006418, 0x9CD3; .word 0x0000641A, 0x9CD3; .word 0x0000641C, 0x39E7; .word 0x0000641E, 0x39E7; .word 0x00006420, 0x39E7; .word 0x00006422, 0x39E7; .word 0x00006424, 0x9CD3; .word 0x00006426, 0x9CD3; .word 0x00006428, 0x9CD3; .word 0x0000642A, 0x39E7; .word 0x0000642C, 0x6B6D; .word 0x0000642E, 0x18C3
    .word 0x00006810, 0x18C3; .word 0x00006812, 0x6B6D; .word 0x00006814, 0x39E7; .word 0x00006816, 0x9CD3; .word 0x00006818, 0xDEDB; .word 0x0000681A, 0xDEDB; .word 0x0000681C, 0x9CD3; .word 0x0000681E, 0x39E7; .word 0x00006820, 0x39E7; .word 0x00006822, 0x9CD3; .word 0x00006824, 0xDEDB; .word 0x00006826, 0xDEDB; .word 0x00006828, 0x9CD3; .word 0x0000682A, 0x39E7; .word 0x0000682C, 0x6B6D; .word 0x0000682E, 0x18C3
    .word 0x00006C10, 0x18C3; .word 0x00006C12, 0x6B6D; .word 0x00006C14, 0x39E7; .word 0x00006C16, 0x9CD3; .word 0x00006C18, 0xDEDB; .word 0x00006C1A, 0xDEDB; .word 0x00006C1C, 0x9CD3; .word 0x00006C1E, 0x39E7; .word 0x00006C20, 0x39E7; .word 0x00006C22, 0x9CD3; .word 0x00006C24, 0xDEDB; .word 0x00006C26, 0xDEDB; .word 0x00006C28, 0x9CD3; .word 0x00006C2A, 0x39E7; .word 0x00006C2C, 0x6B6D; .word 0x00006C2E, 0x18C3
    .word 0x00007010, 0x18C3; .word 0x00007012, 0x18C3; .word 0x00007014, 0x6B6D; .word 0x00007016, 0x6B6D; .word 0x00007018, 0x39E7; .word 0x0000701A, 0x39E7; .word 0x0000701C, 0x6B6D; .word 0x0000701E, 0x6B6D; .word 0x00007020, 0x6B6D; .word 0x00007022, 0x6B6D; .word 0x00007024, 0x39E7; .word 0x00007026, 0x39E7; .word 0x00007028, 0x6B6D; .word 0x0000702A, 0x6B6D; .word 0x0000702C, 0x18C3; .word 0x0000702E, 0x18C3
    .word 0x00007414, 0x18C3; .word 0x00007416, 0x18C3; .word 0x00007418, 0x18C3; .word 0x0000741A, 0x18C3; .word 0x0000741C, 0x18C3; .word 0x00007422, 0x18C3; .word 0x00007424, 0x18C3; .word 0x00007426, 0x18C3; .word 0x00007428, 0x18C3; .word 0x0000742A, 0x18C3
    .word 0x00007816, 0x18C3; .word 0x0000781A, 0x18C3; .word 0x00007824, 0x18C3; .word 0x00007828, 0x18C3
    .word 0x00007C18, 0x18C3; .word 0x00007C1C, 0x18C3; .word 0x00007C22, 0x18C3; .word 0x00007C26, 0x18C3
ship_base_end:

@ ============================================================
@ FRAMES DEL FUEGO DEL PROPULSOR (Flicker)
@ ============================================================
thruster_1:
    @ Frame 1: Fuego pequeño
    .word 0x00007818, 0xFD20; .word 0x00007826, 0xFD20
    .word 0x00007C1A, 0xFFC8; .word 0x00007C24, 0xFFC8
thruster_1_end:

thruster_2:
    @ Frame 2: Fuego medio
    .word 0x00007818, 0xFD20; .word 0x00007826, 0xFD20
    .word 0x00007C1A, 0xFFC8; .word 0x00007C24, 0xFFC8
    .word 0x0000801A, 0xFD20; .word 0x00008024, 0xFD20  @ Y=32 Naranja baja
    .word 0x0000841A, 0xF800; .word 0x00008424, 0xF800  @ Y=33 Punta roja
thruster_2_end:

thruster_3:
    @ Frame 3: Fuego largo e intenso
    .word 0x00007818, 0xFFC8; .word 0x00007826, 0xFFC8  @ Base más amarilla
    .word 0x00007C18, 0xFD20; .word 0x00007C1A, 0xFD20
    .word 0x00007C24, 0xFD20; .word 0x00007C26, 0xFD20
    .word 0x00008018, 0xFFE0; .word 0x0000801A, 0xFFE0  @ Amarillo brillante medio
    .word 0x00008024, 0xFFE0; .word 0x00008026, 0xFFE0
    .word 0x0000841A, 0xFD20; .word 0x00008424, 0xFD20  @ Vuelve a naranja
    .word 0x0000881A, 0xF800; .word 0x00008824, 0xF800  @ Y=34 Punta final roja
thruster_3_end:

@ ============================================================
@ DATOS DE GALAXIAS LEJANAS (Fondo)
@ Representación densa con núcleo, espiral y colores reales
@ ============================================================
galaxies_data:
    @ --- Galaxia 1: Espiral Púrpura Densa (Arriba Izquierda) ---
    @ Colores: 0xCE79 (Núcleo rosado), 0x7173 (Púrpura medio), 0x3809 (Borde)
    @ Y=57
    .word (57<<10)+(66<<1), 0x3809; .word (57<<10)+(67<<1), 0x3809; .word (57<<10)+(68<<1), 0x3809
    @ Y=58
    .word (58<<10)+(64<<1), 0x3809; .word (58<<10)+(65<<1), 0x3809
    .word (58<<10)+(66<<1), 0x7173; .word (58<<10)+(67<<1), 0x7173; .word (58<<10)+(68<<1), 0x7173; .word (58<<10)+(69<<1), 0x7173
    .word (58<<10)+(70<<1), 0x3809; .word (58<<10)+(71<<1), 0x3809
    @ Y=59
    .word (59<<10)+(62<<1), 0x3809; .word (59<<10)+(63<<1), 0x3809
    .word (59<<10)+(64<<1), 0x7173; .word (59<<10)+(65<<1), 0x7173; .word (59<<10)+(66<<1), 0x7173
    .word (59<<10)+(67<<1), 0xCE79; .word (59<<10)+(68<<1), 0xCE79; .word (59<<10)+(69<<1), 0xCE79; .word (59<<10)+(70<<1), 0xCE79
    .word (59<<10)+(71<<1), 0x7173; .word (59<<10)+(72<<1), 0x7173; .word (59<<10)+(73<<1), 0x7173
    .word (59<<10)+(74<<1), 0x3809
    @ Y=60
    .word (60<<10)+(60<<1), 0x3809; .word (60<<10)+(61<<1), 0x3809
    .word (60<<10)+(62<<1), 0x7173; .word (60<<10)+(63<<1), 0x7173; .word (60<<10)+(64<<1), 0x7173
    .word (60<<10)+(65<<1), 0xCE79; .word (60<<10)+(66<<1), 0xCE79; .word (60<<10)+(67<<1), 0xCE79; .word (60<<10)+(68<<1), 0xCE79
    .word (60<<10)+(69<<1), 0xCE79; .word (60<<10)+(70<<1), 0xCE79; .word (60<<10)+(71<<1), 0xCE79; .word (60<<10)+(72<<1), 0xCE79
    .word (60<<10)+(73<<1), 0x7173; .word (60<<10)+(74<<1), 0x7173; .word (60<<10)+(75<<1), 0x7173
    .word (60<<10)+(76<<1), 0x3809; .word (60<<10)+(77<<1), 0x3809
    @ Y=61
    .word (61<<10)+(63<<1), 0x3809
    .word (61<<10)+(64<<1), 0x7173; .word (61<<10)+(65<<1), 0x7173; .word (61<<10)+(66<<1), 0x7173
    .word (61<<10)+(67<<1), 0xCE79; .word (61<<10)+(68<<1), 0xCE79; .word (61<<10)+(69<<1), 0xCE79; .word (61<<10)+(70<<1), 0xCE79; .word (61<<10)+(71<<1), 0xCE79
    .word (61<<10)+(72<<1), 0x7173; .word (61<<10)+(73<<1), 0x7173; .word (61<<10)+(74<<1), 0x7173; .word (61<<10)+(75<<1), 0x7173
    .word (61<<10)+(76<<1), 0x3809; .word (61<<10)+(77<<1), 0x3809; .word (61<<10)+(78<<1), 0x3809
    @ Y=62
    .word (62<<10)+(66<<1), 0x3809; .word (62<<10)+(67<<1), 0x3809
    .word (62<<10)+(68<<1), 0x7173; .word (62<<10)+(69<<1), 0x7173; .word (62<<10)+(70<<1), 0x7173; .word (62<<10)+(71<<1), 0x7173
    .word (62<<10)+(72<<1), 0x3809; .word (62<<10)+(73<<1), 0x3809; .word (62<<10)+(74<<1), 0x3809; .word (62<<10)+(75<<1), 0x3809
    @ Y=63
    .word (63<<10)+(70<<1), 0x3809; .word (63<<10)+(71<<1), 0x3809; .word (63<<10)+(72<<1), 0x3809; .word (63<<10)+(73<<1), 0x3809

    @ --- Galaxia 2: Cúmulo Cyan (Centro Derecha) ---
    @ Y=178
    .word (178<<10)+(238<<1), 0x0188; .word (178<<10)+(239<<1), 0x0188; .word (178<<10)+(240<<1), 0x0188
    @ Y=179
    .word (179<<10)+(236<<1), 0x0188; .word (179<<10)+(237<<1), 0x0188
    .word (179<<10)+(238<<1), 0x03F0; .word (179<<10)+(239<<1), 0x03F0
    .word (179<<10)+(240<<1), 0x0188; .word (179<<10)+(241<<1), 0x0188
    @ Y=180
    .word (180<<10)+(234<<1), 0x0188; .word (180<<10)+(235<<1), 0x0188
    .word (180<<10)+(236<<1), 0x03F0; .word (180<<10)+(237<<1), 0x03F0
    .word (180<<10)+(238<<1), 0x07FF; .word (180<<10)+(239<<1), 0x07FF; .word (180<<10)+(240<<1), 0x07FF
    .word (180<<10)+(241<<1), 0x03F0; .word (180<<10)+(242<<1), 0x03F0
    .word (180<<10)+(243<<1), 0x0188; .word (180<<10)+(244<<1), 0x0188
    @ Y=181
    .word (181<<10)+(236<<1), 0x0188; .word (181<<10)+(237<<1), 0x0188
    .word (181<<10)+(238<<1), 0x03F0; .word (181<<10)+(239<<1), 0x03F0
    .word (181<<10)+(240<<1), 0x07FF; .word (181<<10)+(241<<1), 0x07FF; .word (181<<10)+(242<<1), 0x07FF
    .word (181<<10)+(243<<1), 0x03F0; .word (181<<10)+(244<<1), 0x03F0
    .word (181<<10)+(245<<1), 0x0188; .word (181<<10)+(246<<1), 0x0188
    @ Y=182
    .word (182<<10)+(239<<1), 0x0188; .word (182<<10)+(240<<1), 0x0188
    .word (182<<10)+(241<<1), 0x03F0; .word (182<<10)+(242<<1), 0x03F0
    .word (182<<10)+(243<<1), 0x0188; .word (182<<10)+(244<<1), 0x0188

galaxies_data_end:

.end