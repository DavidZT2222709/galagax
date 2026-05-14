@ ============================================================
@ space_ship.s
@ Nave espacial con GALAXIAS REALISTAS, PROPULSORES ANIMADOS
@ y MOVIMIENTO DE TURBULENCIA / INGRAVIDEZ.
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

@ Tamaño del sprite
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

    @ ---- Pantalla de inicio: esperar ESPACIO ---------------
    BL   DRAW_SPLASH
    BL   WAIT_FOR_SPACE         @ bloquea hasta que se presione espacio

    @ ---- Inicializar posición (lógica y visual) -----------
    LDR  R0, =logical_x
    MOV  R1, #144
    STR  R1, [R0]
    LDR  R0, =logical_y
    MOV  R1, #204
    STR  R1, [R0]

    LDR  R0, =ship_x
    MOV  R1, #144
    STR  R1, [R0]
    LDR  R0, =ship_y
    MOV  R1, #204
    STR  R1, [R0]

    @ Estado de banderas y teclas en 0
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
    LDR  R0, =turb_tick
    STR  R1, [R0]
    LDR  R0, =turb_phase
    STR  R1, [R0]
    LDR  R0, =warp_flag
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
    @ ---- Calcular dx del usuario ----
    LDR  R0, =key_right
    LDR  R0, [R0]
    LDR  R1, =key_left
    LDR  R1, [R1]
    SUB  R6, R0, R1             @ R6 = dir_x  (-1, 0, +1)
    LSL  R6, R6, #2             @ * STEP(4)

    @ ---- Calcular dy del usuario ----
    LDR  R0, =key_down
    LDR  R0, [R0]
    LDR  R1, =key_up
    LDR  R1, [R1]
    SUB  R7, R0, R1             @ R7 = dir_y  (-1, 0, +1)
    LSL  R7, R7, #2             @ * STEP(4)

    @ ---- Actualizar Posición LÓGICA ------------------------
    LDR  R0, =logical_x
    LDR  R4, [R0]
    ADD  R4, R4, R6
    CMP  R4, #0
    MOVLT R4, #0
    LDR  R5, =320-SHIP_W
    CMP  R4, R5
    MOVGT R4, R5
    STR  R4, [R0]

    LDR  R0, =logical_y
    LDR  R4, [R0]
    ADD  R4, R4, R7
    CMP  R4, #0
    MOVLT R4, #0
    LDR  R5, =240-SHIP_H
    CMP  R4, R5
    MOVGT R4, R5
    STR  R4, [R0]

    @ ---- Calcular Posición VISUAL (Lógica + Turbulencia) ---
    LDR  R0, =turb_phase
    LDR  R0, [R0]
    LSL  R0, R0, #2             @ Offset de 4 bytes para tabla

    LDR  R1, =turb_off_x
    LDR  R1, [R1, R0]
    LDR  R2, =logical_x
    LDR  R2, [R2]
    ADD  R8, R2, R1             @ R8 = new_ship_x

    LDR  R1, =turb_off_y
    LDR  R1, [R1, R0]
    LDR  R2, =logical_y
    LDR  R2, [R2]
    ADD  R9, R2, R1             @ R9 = new_ship_y

    @ ---- Clamping de seguridad para evitar desbordes visuales
    CMP  R8, #0
    MOVLT R8, #0
    LDR  R5, =320-SHIP_W
    CMP  R8, R5
    MOVGT R8, R5

    CMP  R9, #0
    MOVLT R9, #0
    LDR  R5, =240-SHIP_H
    CMP  R9, R5
    MOVGT R9, R5

    @ ---- Comprobar si la posición visual ha cambiado -------
    LDR  R0, =ship_x
    LDR  R4, [R0]
    CMP  R4, R8
    BNE  DO_REDRAW_MOVE

    LDR  R0, =ship_y
    LDR  R5, [R0]
    CMP  R5, R9
    BNE  DO_REDRAW_MOVE

    @ ---- Si no hay movimiento, revisar bandera de animación -
    LDR  R0, =redraw_flag
    LDR  R1, [R0]
    CMP  R1, #1
    BEQ  DO_REDRAW_STATIC

    B    DO_WARP_SCROLL

DO_REDRAW_MOVE:
    @ 1. Borrar nave en posición vieja
    BL   RESTORE_BG

    @ 2. Si hay warp pendiente, aprovechar que la nave ya está borrada
    LDR  R0, =warp_flag
    LDR  R1, [R0]
    CMP  R1, #1
    BNE  DRM_NO_WARP
    MOV  R1, #0
    STR  R1, [R0]
    BL   UPDATE_WARP        @ mover rayos mientras nave está borrada
DRM_NO_WARP:
    @ 3. Actualizar posición visual
    LDR  R0, =ship_x
    STR  R8, [R0]
    LDR  R0, =ship_y
    STR  R9, [R0]

    @ 4. Guardar fondo (con rayos, sin nave)
    BL   SAVE_BG

    @ 5. Limpiar flag animación y dibujar nave
    LDR  R0, =redraw_flag
    MOV  R1, #0
    STR  R1, [R0]
    BL   DRAW_SHIP
    B    MAIN_WAIT

DO_REDRAW_STATIC:
    @ 1. Borrar nave
    MOV  R1, #0
    STR  R1, [R0]               @ Limpiar flag de redibujo
    BL   RESTORE_BG

    @ 2. Si hay warp pendiente, aprovechamos
    LDR  R0, =warp_flag
    LDR  R1, [R0]
    CMP  R1, #1
    BNE  DRS_NO_WARP
    MOV  R1, #0
    STR  R1, [R0]
    BL   UPDATE_WARP
DRS_NO_WARP:
    @ 3. Guardar fondo y redibujar nave
    BL   SAVE_BG
    BL   DRAW_SHIP
    B    MAIN_WAIT

DO_WARP_SCROLL:
    @ Solo warp (sin movimiento de nave ni animación)
    LDR  R0, =warp_flag
    LDR  R1, [R0]
    CMP  R1, #1
    BNE  MAIN_WAIT
    MOV  R1, #0
    STR  R1, [R0]
    @ Borrar nave → rayos → guardar fondo → redibujar nave
    BL   RESTORE_BG
    BL   UPDATE_WARP
    BL   SAVE_BG
    BL   DRAW_SHIP

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
@ ============================================================
DRAW_SHIP:
    PUSH {R4-R10, LR}
    LDR  R4, =FB_BASE
    LDR  R5, =ship_x
    LDR  R5, [R5]               @ x visual real
    LDR  R6, =ship_y
    LDR  R6, [R6]               @ y visual real

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
    ADD  R7, R7, R4             @ R7 = puntero FB inicio

    LDR  R8, =bg_buffer
    MOV  R9, #SHIP_H            @ filas restantes
SB_ROW:
    CMP  R9, #0
    BEQ  SB_DONE
    MOV  R10, #SHIP_W           @ cols restantes
    MOV  R0, R7                 @ puntero a fila actual
SB_COL:
    CMP  R10, #0
    BEQ  SB_NEXT
    LDRH R1, [R0], #2
    STRH R1, [R8], #2
    SUB  R10, R10, #1
    B    SB_COL
SB_NEXT:
    ADD  R7, R7, #1024          @ siguiente fila de la pantalla
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
    LDR  R1, =0x4B40            @ Timer a 20Hz (0.05s) para buen parpadeo
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
@ Actualiza la animación de fuego y calcula la fase de turbulencia
@ ============================================================
.global TIMER_ISR
TIMER_ISR:
    PUSH {R0-R2, LR}
    LDR  R0, =0xFF202000
    MOV  R1, #0
    STR  R1, [R0]               @ Limpiar IRQ Timer

    @ 1) Actualizar frame de propulsor
    LDR  R0, =anim_frame
    LDR  R1, [R0]
    ADD  R1, R1, #1
    CMP  R1, #2
    MOVGE R1, #0
    STR  R1, [R0]

    @ 2) Solicitar redibujo al loop principal
    LDR  R0, =redraw_flag
    MOV  R1, #1
    STR  R1, [R0]

    @ 3) Temporizador de turbulencia (cambia cada 3 ticks)
    LDR  R0, =turb_tick
    LDR  R1, [R0]
    ADD  R1, R1, #1
    CMP  R1, #3
    BGE  TI_DO_TURB
    STR  R1, [R0]
    B    TI_END

TI_DO_TURB:
    MOV  R1, #0
    STR  R1, [R0]               @ Reset turb_tick

    LDR  R0, =turb_phase
    LDR  R1, [R0]
    ADD  R1, R1, #1
    CMP  R1, #8
    MOVGE R1, #0
    STR  R1, [R0]

TI_END:
    @ 4) Pedir al main loop que actualice el warp
    LDR  R0, =warp_flag
    MOV  R1, #1
    STR  R1, [R0]

    POP  {R0-R2, LR}
    BX   LR


@ ============================================================
@ UPDATE_WARP  -  Efecto Velocidad de la Luz
@ ============================================================
@ 24 rayos de warp se mueven desde el centro hacia los bordes.
@ Cada rayo: struct de 5 words en warp_streaks:
@   [0] x       posición actual X  (0..319)
@   [1] y       posición actual Y  (0..239)
@   [2] dx      velocidad X (puede ser negativa)
@   [3] dy      velocidad Y (puede ser negativa)
@   [4] age     cuántos pasos lleva (para calcular longitud de cola)
@
@ Algoritmo por rayo:
@   1. Borrar extremo de cola (pintar negro)
@   2. x += dx, y += dy
@   3. Si fuera de pantalla -> resetear al centro
@   4. Pintar cabeza (blanco) y dos píxeles de cola (gris)
@
@ Registros usados:
@   R4 = puntero al rayo actual en la tabla
@   R5 = FB_BASE
@   R6 = x
@   R7 = y
@   R8 = dx
@   R9 = dy
@   R10 = age / temp
@   R11 = límite tabla (warp_streaks_end)
@   R12 = temp
@ ============================================================

@ Constantes auxiliares
.equ W_STRIDE,  1024    @ bytes por fila
.equ W_WIDTH,   320
.equ W_HEIGHT,  240
.equ W_CX,      160     @ centro X
.equ W_CY,      120     @ centro Y
.equ C_WGRAY,   0x632C  @ gris azulado para cola

UPDATE_WARP:
    PUSH {R4-R12, LR}

    LDR  R5, =FB_BASE
    LDR  R4, =warp_streaks
    LDR  R11, =warp_streaks_end

UW_LOOP:
    CMP  R4, R11
    BGE  UW_DONE

    @ Cargar rayo actual
    LDR  R6,  [R4, #0]     @ x
    LDR  R7,  [R4, #4]     @ y
    LDR  R8,  [R4, #8]     @ dx
    LDR  R9,  [R4, #12]    @ dy
    LDR  R10, [R4, #16]    @ age

    @ --- 1. Borrar cola (pintar negro en x-dx*tail, y-dy*tail) ---
    @ tail_len = min(age, 6)
    MOV  R12, R10
    CMP  R12, #6
    MOVGT R12, #6          @ R12 = tail_len

    @ tail_x = x - dx*tail_len,  tail_y = y - dy*tail_len
    MUL  R0, R8, R12       @ R0 = dx * tail_len
    SUB  R0, R6, R0        @ R0 = tail_x
    MUL  R1, R9, R12       @ R1 = dy * tail_len
    SUB  R1, R7, R1        @ R1 = tail_y

    @ Solo borrar si tail está en pantalla
    CMP  R0, #0
    BLT  UW_NO_ERASE
    MOVW R12, #319
    CMP  R0, R12
    BGT  UW_NO_ERASE
    CMP  R1, #0
    BLT  UW_NO_ERASE
    MOVW R12, #239
    CMP  R1, R12
    BGT  UW_NO_ERASE
    @ Pintar negro: addr = FB_BASE + tail_y*1024 + tail_x*2
    LSL  R2, R1, #10       @ tail_y * 1024
    ADD  R2, R2, R0, LSL #1 @ + tail_x * 2
    ADD  R2, R2, R5
    MOV  R3, #0
    STRH R3, [R2]
UW_NO_ERASE:

    @ --- 2. Avanzar posición ---
    ADD  R6, R6, R8        @ x += dx
    ADD  R7, R7, R9        @ y += dy
    ADD  R10, R10, #1      @ age++

    @ --- 3. Verificar límites; si fuera, resetear al centro ---
    CMP  R6, #2
    BLT  UW_RESET
    MOVW R12, #317
    CMP  R6, R12
    BGT  UW_RESET
    CMP  R7, #2
    BLT  UW_RESET
    MOVW R12, #237
    CMP  R7, R12
    BGT  UW_RESET
    B    UW_DRAW

UW_RESET:
    @ Resetear: volver al centro con una pequeña variación
    @ Usamos age como semilla de pseudo-aleatoriedad
    LDR  R6, =W_CX
    LDR  R7, =W_CY
    @ Offset pequeño: (age*3) mod 20 - 10  en cada eje
    MOV  R0, R10
    MOV  R2, #7
    MUL  R3, R0, R2
    MOV  R2, #21
    @ R3 mod 21 - 10 -> simple: AND con 15, resta 8
    AND  R3, R3, #15
    SUB  R3, R3, #8
    ADD  R6, R6, R3
    MOV  R0, R10
    MOV  R2, #11
    MUL  R3, R0, R2
    AND  R3, R3, #15
    SUB  R3, R3, #8
    ADD  R7, R7, R3
    MOV  R10, #0           @ reset age

UW_DRAW:
    @ --- 4a. Pintar cola media (gris, 1 paso atrás) ---
    SUB  R0, R6, R8        @ x - dx
    SUB  R1, R7, R9        @ y - dy
    CMP  R0, #0
    BLT  UW_DRAW_HEAD
    MOVW R12, #319
    CMP  R0, R12
    BGT  UW_DRAW_HEAD
    CMP  R1, #0
    BLT  UW_DRAW_HEAD
    MOVW R12, #239
    CMP  R1, R12
    BGT  UW_DRAW_HEAD
    LSL  R2, R1, #10
    ADD  R2, R2, R0, LSL #1
    ADD  R2, R2, R5
    LDR  R3, =C_WGRAY
    STRH R3, [R2]

    @ --- 4b. Pintar cola lejana (gris oscuro, 2 pasos atrás) ---
    SUB  R0, R6, R8, LSL #1  @ x - dx*2
    SUB  R1, R7, R9, LSL #1  @ y - dy*2
    CMP  R0, #0
    BLT  UW_DRAW_HEAD
    MOVW R12, #319
    CMP  R0, R12
    BGT  UW_DRAW_HEAD
    CMP  R1, #0
    BLT  UW_DRAW_HEAD
    MOVW R12, #239
    CMP  R1, R12
    BGT  UW_DRAW_HEAD
    LSL  R2, R1, #10
    ADD  R2, R2, R0, LSL #1
    ADD  R2, R2, R5
    MOV  R3, #C_GRAY
    STRH R3, [R2]

UW_DRAW_HEAD:
    @ --- 4c. Pintar cabeza (blanco brillante) ---
    CMP  R6, #0
    BLT  UW_SAVE
    MOVW R12, #319
    CMP  R6, R12
    BGT  UW_SAVE
    CMP  R7, #0
    BLT  UW_SAVE
    MOVW R12, #239
    CMP  R7, R12
    BGT  UW_SAVE
    LSL  R2, R7, #10
    ADD  R2, R2, R6, LSL #1
    ADD  R2, R2, R5
    MOV  R3, #C_WHITE
    STRH R3, [R2]

UW_SAVE:
    @ Guardar estado actualizado
    STR  R6,  [R4, #0]
    STR  R7,  [R4, #4]
    STR  R10, [R4, #16]    @ age (dx, dy no cambian)

    ADD  R4, R4, #20       @ siguiente rayo (5 words * 4 bytes)
    B    UW_LOOP

UW_DONE:
    POP  {R4-R12, LR}
    BX   LR


@ ============================================================
@ DRAW_SPLASH  -  Dibuja la pantalla de inicio sobre el fondo
@ ============================================================
DRAW_SPLASH:
    PUSH {R0-R4, LR}
    LDR  R4, =FB_BASE
    LDR  R0, =splash_text
    LDR  R1, =splash_text_end
DS_SPLASH_LOOP:
    CMP  R0, R1
    BGE  DS_SPLASH_DONE
    LDR  R2, [R0], #4           @ offset en FB
    LDR  R3, [R0], #4           @ color
    ADD  R2, R2, R4
    STRH R3, [R2]
    B    DS_SPLASH_LOOP
DS_SPLASH_DONE:
    POP  {R0-R4, LR}
    BX   LR


@ ============================================================
@ WAIT_FOR_SPACE  -  Espera a que se presione la barra espaciadora
@ PS/2 scancode del espacio: 0x29
@ Lee el puerto PS/2 directamente (polling, sin IRQ)
@ ============================================================
WAIT_FOR_SPACE:
    PUSH {R0-R3, LR}
    LDR  R0, =0xFF200100        @ PS/2 base address
WFS_LOOP:
    LDR  R1, [R0]               @ leer PS/2 data register
    TST  R1, #0x8000            @ bit15 = RVALID
    BEQ  WFS_LOOP               @ si no hay dato, seguir esperando
    AND  R2, R1, #0xFF          @ byte recibido
    CMP  R2, #0xF0              @ ¿es break code?
    BEQ  WFS_LOOP               @ ignorar break codes
    CMP  R2, #0xE0              @ ¿es extended?
    BEQ  WFS_LOOP               @ ignorar E0
    CMP  R2, #0x29              @ ¿es espacio?
    BNE  WFS_LOOP               @ no -> seguir esperando
    @ Espacio presionado! Limpiar el texto de splash
    BL   CLEAR_SPLASH
    POP  {R0-R3, LR}
    BX   LR

@ ============================================================
@ CLEAR_SPLASH  -  Borra el texto de la pantalla de inicio
@ ============================================================
CLEAR_SPLASH:
    PUSH {R0-R4, LR}
    LDR  R4, =FB_BASE
    LDR  R0, =splash_text
    LDR  R1, =splash_text_end
CS_LOOP:
    CMP  R0, R1
    BGE  CS_DONE
    LDR  R2, [R0], #4           @ offset en FB
    ADD  R0, R0, #4             @ saltar color
    ADD  R2, R2, R4
    MOV  R3, #0                 @ negro
    STRH R3, [R2]
    B    CS_LOOP
CS_DONE:
    POP  {R0-R4, LR}
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

@ ---- Variables Lógicas de Posición -------------------------
logical_x:     .word 144
logical_y:     .word 204

@ ---- Variables Visuales de Posición (Lógica + Turbulencia) -
ship_x:        .word 144
ship_y:        .word 204

@ ---- Flags del Teclado y Control de Tiempos ----------------
key_up:        .word 0
key_down:      .word 0
key_left:      .word 0
key_right:     .word 0
e0_flag_ps2:   .word 0
break_flag:    .word 0
anim_frame:    .word 0
redraw_flag:   .word 0
turb_tick:     .word 0
turb_phase:    .word 0
warp_flag:     .word 0          @ 1 = actualizar warp este tick

@ ============================================================
@ TABLA DE RAYOS WARP  (24 rayos × 5 words)
@ Formato por entrada: x, y, dx, dy, age
@ ============================================================
.align 2
warp_streaks:
    .word 175, 120, 9, 0, 3
    .word 220, 132, 6, 1, 7
    .word 201, 146, 5, 3, 6
    .word 171, 131, 5, 4, 3
    .word 188, 164, 3, 5, 6
    .word 177, 173, 4, 13, 5
    .word 162, 171, 0, 9, 8
    .word 139, 179, -2, 7, 7
    .word 144, 147, -3, 6, 3
    .word 132, 143, -5, 4, 2
    .word 128, 139, -9, 5, 6
    .word 143, 125, -12, 3, 6
    .word 121, 122, -6, 0, 6
    .word 106, 107, -10, -2, 6
    .word 142, 111, -5, -2, 7
    .word 135, 97, -5, -4, 8
    .word 148, 102, -6, -10, 4
    .word 141, 54, -2, -10, 3
    .word 159, 92, 0, -9, 7
    .word 179, 67, 2, -6, 6
    .word 185, 78, 4, -7, 3
    .word 182, 97, 9, -9, 3
    .word 220, 88, 5, -2, 3
    .word 224, 107, 10, -2, 5
warp_streaks_end:

@ ============================================================
@ TEXTO PANTALLA DE INICIO (píxeles precalculados)
@ ============================================================
.align 2
splash_text:
    .word 0x00016100, 0x07FF
    .word 0x00016102, 0x07FF
    .word 0x00016104, 0x07FF
    .word 0x00016106, 0x07FF
    .word 0x00016500, 0x07FF
    .word 0x00016508, 0x07FF
    .word 0x00016900, 0x07FF
    .word 0x00016908, 0x07FF
    .word 0x00016D00, 0x07FF
    .word 0x00016D02, 0x07FF
    .word 0x00016D04, 0x07FF
    .word 0x00016D06, 0x07FF
    .word 0x00017100, 0x07FF
    .word 0x00017500, 0x07FF
    .word 0x00017900, 0x07FF
    .word 0x0001610C, 0x07FF
    .word 0x0001610E, 0x07FF
    .word 0x00016110, 0x07FF
    .word 0x00016112, 0x07FF
    .word 0x0001650C, 0x07FF
    .word 0x00016514, 0x07FF
    .word 0x0001690C, 0x07FF
    .word 0x00016914, 0x07FF
    .word 0x00016D0C, 0x07FF
    .word 0x00016D0E, 0x07FF
    .word 0x00016D10, 0x07FF
    .word 0x00016D12, 0x07FF
    .word 0x0001710C, 0x07FF
    .word 0x00017110, 0x07FF
    .word 0x0001750C, 0x07FF
    .word 0x00017512, 0x07FF
    .word 0x0001790C, 0x07FF
    .word 0x00017914, 0x07FF
    .word 0x00016118, 0x07FF
    .word 0x0001611A, 0x07FF
    .word 0x0001611C, 0x07FF
    .word 0x0001611E, 0x07FF
    .word 0x00016120, 0x07FF
    .word 0x00016518, 0x07FF
    .word 0x00016918, 0x07FF
    .word 0x00016D18, 0x07FF
    .word 0x00016D1A, 0x07FF
    .word 0x00016D1C, 0x07FF
    .word 0x00016D1E, 0x07FF
    .word 0x00017118, 0x07FF
    .word 0x00017518, 0x07FF
    .word 0x00017918, 0x07FF
    .word 0x0001791A, 0x07FF
    .word 0x0001791C, 0x07FF
    .word 0x0001791E, 0x07FF
    .word 0x00017920, 0x07FF
    .word 0x00016126, 0x07FF
    .word 0x00016128, 0x07FF
    .word 0x0001612A, 0x07FF
    .word 0x0001612C, 0x07FF
    .word 0x00016524, 0x07FF
    .word 0x00016924, 0x07FF
    .word 0x00016D26, 0x07FF
    .word 0x00016D28, 0x07FF
    .word 0x00016D2A, 0x07FF
    .word 0x0001712C, 0x07FF
    .word 0x0001752C, 0x07FF
    .word 0x00017924, 0x07FF
    .word 0x00017926, 0x07FF
    .word 0x00017928, 0x07FF
    .word 0x0001792A, 0x07FF
    .word 0x00016132, 0x07FF
    .word 0x00016134, 0x07FF
    .word 0x00016136, 0x07FF
    .word 0x00016138, 0x07FF
    .word 0x00016530, 0x07FF
    .word 0x00016930, 0x07FF
    .word 0x00016D32, 0x07FF
    .word 0x00016D34, 0x07FF
    .word 0x00016D36, 0x07FF
    .word 0x00017138, 0x07FF
    .word 0x00017538, 0x07FF
    .word 0x00017930, 0x07FF
    .word 0x00017932, 0x07FF
    .word 0x00017934, 0x07FF
    .word 0x00017936, 0x07FF
    .word 0x0001614A, 0x07FF
    .word 0x0001614C, 0x07FF
    .word 0x0001614E, 0x07FF
    .word 0x00016150, 0x07FF
    .word 0x00016548, 0x07FF
    .word 0x00016948, 0x07FF
    .word 0x00016D4A, 0x07FF
    .word 0x00016D4C, 0x07FF
    .word 0x00016D4E, 0x07FF
    .word 0x00017150, 0x07FF
    .word 0x00017550, 0x07FF
    .word 0x00017948, 0x07FF
    .word 0x0001794A, 0x07FF
    .word 0x0001794C, 0x07FF
    .word 0x0001794E, 0x07FF
    .word 0x00016154, 0x07FF
    .word 0x00016156, 0x07FF
    .word 0x00016158, 0x07FF
    .word 0x0001615A, 0x07FF
    .word 0x00016554, 0x07FF
    .word 0x0001655C, 0x07FF
    .word 0x00016954, 0x07FF
    .word 0x0001695C, 0x07FF
    .word 0x00016D54, 0x07FF
    .word 0x00016D56, 0x07FF
    .word 0x00016D58, 0x07FF
    .word 0x00016D5A, 0x07FF
    .word 0x00017154, 0x07FF
    .word 0x00017554, 0x07FF
    .word 0x00017954, 0x07FF
    .word 0x00016162, 0x07FF
    .word 0x00016164, 0x07FF
    .word 0x00016166, 0x07FF
    .word 0x00016560, 0x07FF
    .word 0x00016568, 0x07FF
    .word 0x00016960, 0x07FF
    .word 0x00016968, 0x07FF
    .word 0x00016D60, 0x07FF
    .word 0x00016D62, 0x07FF
    .word 0x00016D64, 0x07FF
    .word 0x00016D66, 0x07FF
    .word 0x00016D68, 0x07FF
    .word 0x00017160, 0x07FF
    .word 0x00017168, 0x07FF
    .word 0x00017560, 0x07FF
    .word 0x00017568, 0x07FF
    .word 0x00017960, 0x07FF
    .word 0x00017968, 0x07FF
    .word 0x0001616E, 0x07FF
    .word 0x00016170, 0x07FF
    .word 0x00016172, 0x07FF
    .word 0x00016174, 0x07FF
    .word 0x0001656C, 0x07FF
    .word 0x0001696C, 0x07FF
    .word 0x00016D6C, 0x07FF
    .word 0x0001716C, 0x07FF
    .word 0x0001756C, 0x07FF
    .word 0x0001796E, 0x07FF
    .word 0x00017970, 0x07FF
    .word 0x00017972, 0x07FF
    .word 0x00017974, 0x07FF
    .word 0x00016178, 0x07FF
    .word 0x0001617A, 0x07FF
    .word 0x0001617C, 0x07FF
    .word 0x0001617E, 0x07FF
    .word 0x00016180, 0x07FF
    .word 0x00016578, 0x07FF
    .word 0x00016978, 0x07FF
    .word 0x00016D78, 0x07FF
    .word 0x00016D7A, 0x07FF
    .word 0x00016D7C, 0x07FF
    .word 0x00016D7E, 0x07FF
    .word 0x00017178, 0x07FF
    .word 0x00017578, 0x07FF
    .word 0x00017978, 0x07FF
    .word 0x0001797A, 0x07FF
    .word 0x0001797C, 0x07FF
    .word 0x0001797E, 0x07FF
    .word 0x00017980, 0x07FF
    .word 0x0001B112, 0xFFFF
    .word 0x0001B114, 0xFFFF
    .word 0x0001B116, 0xFFFF
    .word 0x0001B118, 0xFFFF
    .word 0x0001B11A, 0xFFFF
    .word 0x0001B516, 0xFFFF
    .word 0x0001B916, 0xFFFF
    .word 0x0001BD16, 0xFFFF
    .word 0x0001C116, 0xFFFF
    .word 0x0001C516, 0xFFFF
    .word 0x0001C916, 0xFFFF
    .word 0x0001B120, 0xFFFF
    .word 0x0001B122, 0xFFFF
    .word 0x0001B124, 0xFFFF
    .word 0x0001B51E, 0xFFFF
    .word 0x0001B526, 0xFFFF
    .word 0x0001B91E, 0xFFFF
    .word 0x0001B926, 0xFFFF
    .word 0x0001BD1E, 0xFFFF
    .word 0x0001BD26, 0xFFFF
    .word 0x0001C11E, 0xFFFF
    .word 0x0001C126, 0xFFFF
    .word 0x0001C51E, 0xFFFF
    .word 0x0001C526, 0xFFFF
    .word 0x0001C920, 0xFFFF
    .word 0x0001C922, 0xFFFF
    .word 0x0001C924, 0xFFFF
    .word 0x0001B138, 0xFFFF
    .word 0x0001B13A, 0xFFFF
    .word 0x0001B13C, 0xFFFF
    .word 0x0001B13E, 0xFFFF
    .word 0x0001B536, 0xFFFF
    .word 0x0001B936, 0xFFFF
    .word 0x0001BD38, 0xFFFF
    .word 0x0001BD3A, 0xFFFF
    .word 0x0001BD3C, 0xFFFF
    .word 0x0001C13E, 0xFFFF
    .word 0x0001C53E, 0xFFFF
    .word 0x0001C936, 0xFFFF
    .word 0x0001C938, 0xFFFF
    .word 0x0001C93A, 0xFFFF
    .word 0x0001C93C, 0xFFFF
    .word 0x0001B142, 0xFFFF
    .word 0x0001B144, 0xFFFF
    .word 0x0001B146, 0xFFFF
    .word 0x0001B148, 0xFFFF
    .word 0x0001B14A, 0xFFFF
    .word 0x0001B546, 0xFFFF
    .word 0x0001B946, 0xFFFF
    .word 0x0001BD46, 0xFFFF
    .word 0x0001C146, 0xFFFF
    .word 0x0001C546, 0xFFFF
    .word 0x0001C946, 0xFFFF
    .word 0x0001B150, 0xFFFF
    .word 0x0001B152, 0xFFFF
    .word 0x0001B154, 0xFFFF
    .word 0x0001B54E, 0xFFFF
    .word 0x0001B556, 0xFFFF
    .word 0x0001B94E, 0xFFFF
    .word 0x0001B956, 0xFFFF
    .word 0x0001BD4E, 0xFFFF
    .word 0x0001BD50, 0xFFFF
    .word 0x0001BD52, 0xFFFF
    .word 0x0001BD54, 0xFFFF
    .word 0x0001BD56, 0xFFFF
    .word 0x0001C14E, 0xFFFF
    .word 0x0001C156, 0xFFFF
    .word 0x0001C54E, 0xFFFF
    .word 0x0001C556, 0xFFFF
    .word 0x0001C94E, 0xFFFF
    .word 0x0001C956, 0xFFFF
    .word 0x0001B15A, 0xFFFF
    .word 0x0001B15C, 0xFFFF
    .word 0x0001B15E, 0xFFFF
    .word 0x0001B160, 0xFFFF
    .word 0x0001B55A, 0xFFFF
    .word 0x0001B562, 0xFFFF
    .word 0x0001B95A, 0xFFFF
    .word 0x0001B962, 0xFFFF
    .word 0x0001BD5A, 0xFFFF
    .word 0x0001BD5C, 0xFFFF
    .word 0x0001BD5E, 0xFFFF
    .word 0x0001BD60, 0xFFFF
    .word 0x0001C15A, 0xFFFF
    .word 0x0001C15E, 0xFFFF
    .word 0x0001C55A, 0xFFFF
    .word 0x0001C560, 0xFFFF
    .word 0x0001C95A, 0xFFFF
    .word 0x0001C962, 0xFFFF
    .word 0x0001B166, 0xFFFF
    .word 0x0001B168, 0xFFFF
    .word 0x0001B16A, 0xFFFF
    .word 0x0001B16C, 0xFFFF
    .word 0x0001B16E, 0xFFFF
    .word 0x0001B56A, 0xFFFF
    .word 0x0001B96A, 0xFFFF
    .word 0x0001BD6A, 0xFFFF
    .word 0x0001C16A, 0xFFFF
    .word 0x0001C56A, 0xFFFF
    .word 0x0001C96A, 0xFFFF
    .word 0x000208C4, 0x4208
    .word 0x000208CC, 0x4208
    .word 0x00020CC4, 0x4208
    .word 0x00020CCC, 0x4208
    .word 0x000210C4, 0x4208
    .word 0x000210CC, 0x4208
    .word 0x000214C4, 0x4208
    .word 0x000214C8, 0x4208
    .word 0x000214CC, 0x4208
    .word 0x000218C4, 0x4208
    .word 0x000218C8, 0x4208
    .word 0x000218CC, 0x4208
    .word 0x00021CC4, 0x4208
    .word 0x00021CC6, 0x4208
    .word 0x00021CCA, 0x4208
    .word 0x00021CCC, 0x4208
    .word 0x000220C4, 0x4208
    .word 0x000220CC, 0x4208
    .word 0x000208D2, 0x4208
    .word 0x000208D4, 0x4208
    .word 0x000208D6, 0x4208
    .word 0x00020CD0, 0x4208
    .word 0x00020CD8, 0x4208
    .word 0x000210D0, 0x4208
    .word 0x000210D8, 0x4208
    .word 0x000214D0, 0x4208
    .word 0x000214D2, 0x4208
    .word 0x000214D4, 0x4208
    .word 0x000214D6, 0x4208
    .word 0x000214D8, 0x4208
    .word 0x000218D0, 0x4208
    .word 0x000218D8, 0x4208
    .word 0x00021CD0, 0x4208
    .word 0x00021CD8, 0x4208
    .word 0x000220D0, 0x4208
    .word 0x000220D8, 0x4208
    .word 0x000208DC, 0x4208
    .word 0x000208DE, 0x4208
    .word 0x000208E0, 0x4208
    .word 0x000208E2, 0x4208
    .word 0x00020CDC, 0x4208
    .word 0x00020CE4, 0x4208
    .word 0x000210DC, 0x4208
    .word 0x000210E4, 0x4208
    .word 0x000214DC, 0x4208
    .word 0x000214DE, 0x4208
    .word 0x000214E0, 0x4208
    .word 0x000214E2, 0x4208
    .word 0x000218DC, 0x4208
    .word 0x000218E0, 0x4208
    .word 0x00021CDC, 0x4208
    .word 0x00021CE2, 0x4208
    .word 0x000220DC, 0x4208
    .word 0x000220E4, 0x4208
    .word 0x000208E8, 0x4208
    .word 0x000208EA, 0x4208
    .word 0x000208EC, 0x4208
    .word 0x000208EE, 0x4208
    .word 0x00020CE8, 0x4208
    .word 0x00020CF0, 0x4208
    .word 0x000210E8, 0x4208
    .word 0x000210F0, 0x4208
    .word 0x000214E8, 0x4208
    .word 0x000214EA, 0x4208
    .word 0x000214EC, 0x4208
    .word 0x000214EE, 0x4208
    .word 0x000218E8, 0x4208
    .word 0x00021CE8, 0x4208
    .word 0x000220E8, 0x4208
    .word 0x00020900, 0x4208
    .word 0x00020902, 0x4208
    .word 0x00020904, 0x4208
    .word 0x00020906, 0x4208
    .word 0x00020908, 0x4208
    .word 0x00020D00, 0x4208
    .word 0x00021100, 0x4208
    .word 0x00021500, 0x4208
    .word 0x00021502, 0x4208
    .word 0x00021504, 0x4208
    .word 0x00021506, 0x4208
    .word 0x00021900, 0x4208
    .word 0x00021D00, 0x4208
    .word 0x00022100, 0x4208
    .word 0x0002090C, 0x4208
    .word 0x00020D0C, 0x4208
    .word 0x0002110C, 0x4208
    .word 0x0002150C, 0x4208
    .word 0x0002190C, 0x4208
    .word 0x00021D0C, 0x4208
    .word 0x0002210C, 0x4208
    .word 0x0002210E, 0x4208
    .word 0x00022110, 0x4208
    .word 0x00022112, 0x4208
    .word 0x00022114, 0x4208
    .word 0x0002091A, 0x4208
    .word 0x0002091C, 0x4208
    .word 0x0002091E, 0x4208
    .word 0x00020D1C, 0x4208
    .word 0x0002111C, 0x4208
    .word 0x0002151C, 0x4208
    .word 0x0002191C, 0x4208
    .word 0x00021D1C, 0x4208
    .word 0x0002211A, 0x4208
    .word 0x0002211C, 0x4208
    .word 0x0002211E, 0x4208
    .word 0x00020926, 0x4208
    .word 0x00020928, 0x4208
    .word 0x0002092A, 0x4208
    .word 0x0002092C, 0x4208
    .word 0x00020D24, 0x4208
    .word 0x00021124, 0x4208
    .word 0x00021524, 0x4208
    .word 0x00021528, 0x4208
    .word 0x0002152A, 0x4208
    .word 0x0002152C, 0x4208
    .word 0x00021924, 0x4208
    .word 0x0002192C, 0x4208
    .word 0x00021D24, 0x4208
    .word 0x00021D2C, 0x4208
    .word 0x00022126, 0x4208
    .word 0x00022128, 0x4208
    .word 0x0002212A, 0x4208
    .word 0x0002212C, 0x4208
    .word 0x00020930, 0x4208
    .word 0x00020938, 0x4208
    .word 0x00020D30, 0x4208
    .word 0x00020D38, 0x4208
    .word 0x00021130, 0x4208
    .word 0x00021138, 0x4208
    .word 0x00021530, 0x4208
    .word 0x00021532, 0x4208
    .word 0x00021534, 0x4208
    .word 0x00021536, 0x4208
    .word 0x00021538, 0x4208
    .word 0x00021930, 0x4208
    .word 0x00021938, 0x4208
    .word 0x00021D30, 0x4208
    .word 0x00021D38, 0x4208
    .word 0x00022130, 0x4208
    .word 0x00022138, 0x4208
    .word 0x0002093C, 0x4208
    .word 0x0002093E, 0x4208
    .word 0x00020940, 0x4208
    .word 0x00020942, 0x4208
    .word 0x00020944, 0x4208
    .word 0x00020D40, 0x4208
    .word 0x00021140, 0x4208
    .word 0x00021540, 0x4208
    .word 0x00021940, 0x4208
    .word 0x00021D40, 0x4208
    .word 0x00022140, 0x4208
    .word 0x00020956, 0x4208
    .word 0x00020958, 0x4208
    .word 0x0002095A, 0x4208
    .word 0x0002095C, 0x4208
    .word 0x00020D54, 0x4208
    .word 0x00021154, 0x4208
    .word 0x00021556, 0x4208
    .word 0x00021558, 0x4208
    .word 0x0002155A, 0x4208
    .word 0x0002195C, 0x4208
    .word 0x00021D5C, 0x4208
    .word 0x00022154, 0x4208
    .word 0x00022156, 0x4208
    .word 0x00022158, 0x4208
    .word 0x0002215A, 0x4208
    .word 0x00020962, 0x4208
    .word 0x00020964, 0x4208
    .word 0x00020966, 0x4208
    .word 0x00020D64, 0x4208
    .word 0x00021164, 0x4208
    .word 0x00021564, 0x4208
    .word 0x00021964, 0x4208
    .word 0x00021D64, 0x4208
    .word 0x00022162, 0x4208
    .word 0x00022164, 0x4208
    .word 0x00022166, 0x4208
    .word 0x0002096C, 0x4208
    .word 0x00020974, 0x4208
    .word 0x00020D6C, 0x4208
    .word 0x00020D6E, 0x4208
    .word 0x00020D72, 0x4208
    .word 0x00020D74, 0x4208
    .word 0x0002116C, 0x4208
    .word 0x00021170, 0x4208
    .word 0x00021174, 0x4208
    .word 0x0002156C, 0x4208
    .word 0x00021574, 0x4208
    .word 0x0002196C, 0x4208
    .word 0x00021974, 0x4208
    .word 0x00021D6C, 0x4208
    .word 0x00021D74, 0x4208
    .word 0x0002216C, 0x4208
    .word 0x00022174, 0x4208
    .word 0x00020978, 0x4208
    .word 0x00020980, 0x4208
    .word 0x00020D78, 0x4208
    .word 0x00020D80, 0x4208
    .word 0x00021178, 0x4208
    .word 0x00021180, 0x4208
    .word 0x00021578, 0x4208
    .word 0x00021580, 0x4208
    .word 0x00021978, 0x4208
    .word 0x00021980, 0x4208
    .word 0x00021D78, 0x4208
    .word 0x00021D80, 0x4208
    .word 0x0002217A, 0x4208
    .word 0x0002217C, 0x4208
    .word 0x0002217E, 0x4208
    .word 0x00020984, 0x4208
    .word 0x00020D84, 0x4208
    .word 0x00021184, 0x4208
    .word 0x00021584, 0x4208
    .word 0x00021984, 0x4208
    .word 0x00021D84, 0x4208
    .word 0x00022184, 0x4208
    .word 0x00022186, 0x4208
    .word 0x00022188, 0x4208
    .word 0x0002218A, 0x4208
    .word 0x0002218C, 0x4208
    .word 0x00020992, 0x4208
    .word 0x00020994, 0x4208
    .word 0x00020996, 0x4208
    .word 0x00020D90, 0x4208
    .word 0x00020D98, 0x4208
    .word 0x00021190, 0x4208
    .word 0x00021198, 0x4208
    .word 0x00021590, 0x4208
    .word 0x00021592, 0x4208
    .word 0x00021594, 0x4208
    .word 0x00021596, 0x4208
    .word 0x00021598, 0x4208
    .word 0x00021990, 0x4208
    .word 0x00021998, 0x4208
    .word 0x00021D90, 0x4208
    .word 0x00021D98, 0x4208
    .word 0x00022190, 0x4208
    .word 0x00022198, 0x4208
    .word 0x0002099C, 0x4208
    .word 0x0002099E, 0x4208
    .word 0x000209A0, 0x4208
    .word 0x000209A2, 0x4208
    .word 0x000209A4, 0x4208
    .word 0x00020DA0, 0x4208
    .word 0x000211A0, 0x4208
    .word 0x000215A0, 0x4208
    .word 0x000219A0, 0x4208
    .word 0x00021DA0, 0x4208
    .word 0x000221A0, 0x4208
    .word 0x000209AA, 0x4208
    .word 0x000209AC, 0x4208
    .word 0x000209AE, 0x4208
    .word 0x00020DA8, 0x4208
    .word 0x00020DB0, 0x4208
    .word 0x000211A8, 0x4208
    .word 0x000211B0, 0x4208
    .word 0x000215A8, 0x4208
    .word 0x000215B0, 0x4208
    .word 0x000219A8, 0x4208
    .word 0x000219B0, 0x4208
    .word 0x00021DA8, 0x4208
    .word 0x00021DB0, 0x4208
    .word 0x000221AA, 0x4208
    .word 0x000221AC, 0x4208
    .word 0x000221AE, 0x4208
    .word 0x000209B4, 0x4208
    .word 0x000209B6, 0x4208
    .word 0x000209B8, 0x4208
    .word 0x000209BA, 0x4208
    .word 0x00020DB4, 0x4208
    .word 0x00020DBC, 0x4208
    .word 0x000211B4, 0x4208
    .word 0x000211BC, 0x4208
    .word 0x000215B4, 0x4208
    .word 0x000215B6, 0x4208
    .word 0x000215B8, 0x4208
    .word 0x000215BA, 0x4208
    .word 0x000219B4, 0x4208
    .word 0x000219B8, 0x4208
    .word 0x00021DB4, 0x4208
    .word 0x00021DBA, 0x4208
    .word 0x000221B4, 0x4208
    .word 0x000221BC, 0x4208
splash_text_end:

@ ---- Tabla de Órbita de Turbulencia (8 pasos, valores ±1) --
@ Produce un leve movimiento oscilante tipo "flote espacial"
turb_off_x:    .word 0,  1,  1,  0, -1, -1, -1,  0
turb_off_y:    .word -1, -1,  0,  1,  1,  0, -1, -1

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
    .word 0x0000801A, 0xFD20; .word 0x00008024, 0xFD20
    .word 0x0000841A, 0xF800; .word 0x00008424, 0xF800
thruster_2_end:

thruster_3:
    @ Frame 3: Fuego largo e intenso
    .word 0x00007818, 0xFFC8; .word 0x00007826, 0xFFC8
    .word 0x00007C18, 0xFD20; .word 0x00007C1A, 0xFD20
    .word 0x00007C24, 0xFD20; .word 0x00007C26, 0xFD20
    .word 0x00008018, 0xFFE0; .word 0x0000801A, 0xFFE0
    .word 0x00008024, 0xFFE0; .word 0x00008026, 0xFFE0
    .word 0x0000841A, 0xFD20; .word 0x00008424, 0xFD20
    .word 0x0000881A, 0xF800; .word 0x00008824, 0xF800
thruster_3_end:

@ ============================================================
@ DATOS DE GALAXIAS LEJANAS (Fondo)
@ ============================================================
galaxies_data:
    @ --- Galaxia 1: Espiral Púrpura Densa (Arriba Izquierda) ---
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