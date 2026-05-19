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
@ Mientras espera, anima el fondo de warp (estrellas en movimiento)
@ ============================================================
WAIT_FOR_SPACE:
    PUSH {R0-R5, LR}
    LDR  R5, =0xFF200100        @ PS/2 base address
WFS_LOOP:
    @ --- Animar el fondo warp (estrellas moviendose) ---
    BL   UPDATE_WARP
    @ --- Delay pequeño para controlar velocidad de animación ---
    LDR  R0, =300000
WFS_DELAY:
    SUBS R0, R0, #1
    BNE  WFS_DELAY
    @ --- Verificar teclado PS/2 ---
    LDR  R1, [R5]               @ leer PS/2 data register
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
    POP  {R0-R5, LR}
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
.align 2
splash_text:
    .word 0x00004024, 0xFFF2
    .word 0x0000425A, 0xFFF2
    .word 0x00004820, 0xFFF2
    .word 0x00004824, 0xFFF2
    .word 0x00004828, 0xFFF2
    .word 0x00004A56, 0xFFF2
    .word 0x00004A5A, 0xFFF2
    .word 0x00004A5E, 0xFFF2
    .word 0x00005024, 0xFFF2
    .word 0x0000525A, 0xFFF2
    .word 0x00005850, 0x03D6
    .word 0x00005852, 0x03D6
    .word 0x00005854, 0x03D6
    .word 0x00005856, 0x03D6
    .word 0x00005858, 0x03D6
    .word 0x0000585A, 0x03D6
    .word 0x0000585C, 0x03D6
    .word 0x0000585E, 0x03D6
    .word 0x00005860, 0x03D6
    .word 0x00005862, 0x03D6
    .word 0x00005864, 0x03D6
    .word 0x00005866, 0x03D6
    .word 0x00005868, 0x03D6
    .word 0x0000586A, 0x03D6
    .word 0x0000586C, 0x03D6
    .word 0x0000586E, 0x03D6
    .word 0x00005870, 0x03D6
    .word 0x00005872, 0x03D6
    .word 0x00005874, 0x03D6
    .word 0x00005876, 0x03D6
    .word 0x00005878, 0x03D6
    .word 0x0000587A, 0x03D6
    .word 0x0000587C, 0x03D6
    .word 0x0000587E, 0x03D6
    .word 0x00005880, 0x03D6
    .word 0x00005882, 0x03D6
    .word 0x00005884, 0x03D6
    .word 0x00005886, 0x03D6
    .word 0x00005888, 0x03D6
    .word 0x0000588A, 0x03D6
    .word 0x0000588C, 0x03D6
    .word 0x0000588E, 0x03D6
    .word 0x00005890, 0x03D6
    .word 0x00005892, 0x03D6
    .word 0x00005894, 0x03D6
    .word 0x00005896, 0x03D6
    .word 0x00005898, 0x03D6
    .word 0x0000589A, 0x03D6
    .word 0x0000589C, 0x03D6
    .word 0x0000589E, 0x03D6
    .word 0x000058A0, 0x03D6
    .word 0x000058A2, 0x03D6
    .word 0x000058A4, 0x03D6
    .word 0x000058A6, 0x03D6
    .word 0x000058A8, 0x03D6
    .word 0x000058AA, 0x03D6
    .word 0x000058AC, 0x03D6
    .word 0x000058AE, 0x03D6
    .word 0x000058B0, 0x03D6
    .word 0x000058B2, 0x03D6
    .word 0x000058B4, 0x03D6
    .word 0x000058B6, 0x03D6
    .word 0x000058B8, 0x03D6
    .word 0x000058BA, 0x03D6
    .word 0x000058BC, 0x03D6
    .word 0x000058BE, 0x03D6
    .word 0x000058C0, 0x03D6
    .word 0x000058C2, 0x03D6
    .word 0x000058C4, 0x03D6
    .word 0x000058C6, 0x03D6
    .word 0x000058C8, 0x03D6
    .word 0x000058CA, 0x03D6
    .word 0x000058CC, 0x03D6
    .word 0x000058CE, 0x03D6
    .word 0x000058D0, 0x03D6
    .word 0x000058D2, 0x03D6
    .word 0x000058D4, 0x03D6
    .word 0x000058D6, 0x03D6
    .word 0x000058D8, 0x03D6
    .word 0x000058DA, 0x03D6
    .word 0x000058DC, 0x03D6
    .word 0x000058DE, 0x03D6
    .word 0x000058E0, 0x03D6
    .word 0x000058E2, 0x03D6
    .word 0x000058E4, 0x03D6
    .word 0x000058E6, 0x03D6
    .word 0x000058E8, 0x03D6
    .word 0x000058EA, 0x03D6
    .word 0x000058EC, 0x03D6
    .word 0x000058EE, 0x03D6
    .word 0x000058F0, 0x03D6
    .word 0x000058F2, 0x03D6
    .word 0x000058F4, 0x03D6
    .word 0x000058F6, 0x03D6
    .word 0x000058F8, 0x03D6
    .word 0x000058FA, 0x03D6
    .word 0x000058FC, 0x03D6
    .word 0x000058FE, 0x03D6
    .word 0x00005900, 0x03D6
    .word 0x00005902, 0x03D6
    .word 0x00005904, 0x03D6
    .word 0x00005906, 0x03D6
    .word 0x00005908, 0x03D6
    .word 0x0000590A, 0x03D6
    .word 0x0000590C, 0x03D6
    .word 0x0000590E, 0x03D6
    .word 0x00005910, 0x03D6
    .word 0x00005912, 0x03D6
    .word 0x00005914, 0x03D6
    .word 0x00005916, 0x03D6
    .word 0x00005918, 0x03D6
    .word 0x0000591A, 0x03D6
    .word 0x0000591C, 0x03D6
    .word 0x0000591E, 0x03D6
    .word 0x00005920, 0x03D6
    .word 0x00005922, 0x03D6
    .word 0x00005924, 0x03D6
    .word 0x00005926, 0x03D6
    .word 0x00005928, 0x03D6
    .word 0x0000592A, 0x03D6
    .word 0x0000592C, 0x03D6
    .word 0x0000592E, 0x03D6
    .word 0x00005930, 0x03D6
    .word 0x00005932, 0x03D6
    .word 0x00005934, 0x03D6
    .word 0x00005936, 0x03D6
    .word 0x00005938, 0x03D6
    .word 0x0000593A, 0x03D6
    .word 0x0000593C, 0x03D6
    .word 0x0000593E, 0x03D6
    .word 0x00005940, 0x03D6
    .word 0x00005942, 0x03D6
    .word 0x00005944, 0x03D6
    .word 0x00005946, 0x03D6
    .word 0x00005948, 0x03D6
    .word 0x0000594A, 0x03D6
    .word 0x0000594C, 0x03D6
    .word 0x0000594E, 0x03D6
    .word 0x00005950, 0x03D6
    .word 0x00005952, 0x03D6
    .word 0x00005954, 0x03D6
    .word 0x00005956, 0x03D6
    .word 0x00005958, 0x03D6
    .word 0x0000595A, 0x03D6
    .word 0x0000595C, 0x03D6
    .word 0x0000595E, 0x03D6
    .word 0x00005960, 0x03D6
    .word 0x00005962, 0x03D6
    .word 0x00005964, 0x03D6
    .word 0x00005966, 0x03D6
    .word 0x00005968, 0x03D6
    .word 0x0000596A, 0x03D6
    .word 0x0000596C, 0x03D6
    .word 0x0000596E, 0x03D6
    .word 0x00005970, 0x03D6
    .word 0x00005972, 0x03D6
    .word 0x00005974, 0x03D6
    .word 0x00005976, 0x03D6
    .word 0x00005978, 0x03D6
    .word 0x0000597A, 0x03D6
    .word 0x0000597C, 0x03D6
    .word 0x0000597E, 0x03D6
    .word 0x00005980, 0x03D6
    .word 0x00005982, 0x03D6
    .word 0x00005984, 0x03D6
    .word 0x00005986, 0x03D6
    .word 0x00005988, 0x03D6
    .word 0x0000598A, 0x03D6
    .word 0x0000598C, 0x03D6
    .word 0x0000598E, 0x03D6
    .word 0x00005990, 0x03D6
    .word 0x00005992, 0x03D6
    .word 0x00005994, 0x03D6
    .word 0x00005996, 0x03D6
    .word 0x00005998, 0x03D6
    .word 0x0000599A, 0x03D6
    .word 0x0000599C, 0x03D6
    .word 0x0000599E, 0x03D6
    .word 0x000059A0, 0x03D6
    .word 0x000059A2, 0x03D6
    .word 0x000059A4, 0x03D6
    .word 0x000059A6, 0x03D6
    .word 0x000059A8, 0x03D6
    .word 0x000059AA, 0x03D6
    .word 0x000059AC, 0x03D6
    .word 0x000059AE, 0x03D6
    .word 0x000059B0, 0x03D6
    .word 0x000059B2, 0x03D6
    .word 0x000059B4, 0x03D6
    .word 0x000059B6, 0x03D6
    .word 0x000059B8, 0x03D6
    .word 0x000059BA, 0x03D6
    .word 0x000059BC, 0x03D6
    .word 0x000059BE, 0x03D6
    .word 0x000059C0, 0x03D6
    .word 0x000059C2, 0x03D6
    .word 0x000059C4, 0x03D6
    .word 0x000059C6, 0x03D6
    .word 0x000059C8, 0x03D6
    .word 0x000059CA, 0x03D6
    .word 0x000059CC, 0x03D6
    .word 0x000059CE, 0x03D6
    .word 0x000059D0, 0x03D6
    .word 0x000059D2, 0x03D6
    .word 0x000059D4, 0x03D6
    .word 0x000059D6, 0x03D6
    .word 0x000059D8, 0x03D6
    .word 0x000059DA, 0x03D6
    .word 0x000059DC, 0x03D6
    .word 0x000059DE, 0x03D6
    .word 0x000059E0, 0x03D6
    .word 0x000059E2, 0x03D6
    .word 0x000059E4, 0x03D6
    .word 0x000059E6, 0x03D6
    .word 0x000059E8, 0x03D6
    .word 0x000059EA, 0x03D6
    .word 0x000059EC, 0x03D6
    .word 0x000059EE, 0x03D6
    .word 0x000059F0, 0x03D6
    .word 0x000059F2, 0x03D6
    .word 0x000059F4, 0x03D6
    .word 0x000059F6, 0x03D6
    .word 0x000059F8, 0x03D6
    .word 0x000059FA, 0x03D6
    .word 0x000059FC, 0x03D6
    .word 0x000059FE, 0x03D6
    .word 0x00005A00, 0x03D6
    .word 0x00005A02, 0x03D6
    .word 0x00005A04, 0x03D6
    .word 0x00005A06, 0x03D6
    .word 0x00005A08, 0x03D6
    .word 0x00005A0A, 0x03D6
    .word 0x00005A0C, 0x03D6
    .word 0x00005A0E, 0x03D6
    .word 0x00005A10, 0x03D6
    .word 0x00005A12, 0x03D6
    .word 0x00005A14, 0x03D6
    .word 0x00005A16, 0x03D6
    .word 0x00005A18, 0x03D6
    .word 0x00005A1A, 0x03D6
    .word 0x00005A1C, 0x03D6
    .word 0x00005A1E, 0x03D6
    .word 0x00005A20, 0x03D6
    .word 0x00005A22, 0x03D6
    .word 0x00005A24, 0x03D6
    .word 0x00005A26, 0x03D6
    .word 0x00005A28, 0x03D6
    .word 0x00005A2A, 0x03D6
    .word 0x00005A2C, 0x03D6
    .word 0x00005A2E, 0x03D6
    .word 0x000078C0, 0xFA8A
    .word 0x000078C2, 0xFA8A
    .word 0x000078C4, 0xFA8A
    .word 0x000078C6, 0xFA8A
    .word 0x000078C8, 0xFA8A
    .word 0x000078CA, 0xFA8A
    .word 0x000078CC, 0xFA8A
    .word 0x000078CE, 0xFA8A
    .word 0x000078D4, 0xFD00
    .word 0x000078D6, 0xFD00
    .word 0x000078D8, 0xFD00
    .word 0x000078DA, 0xFD00
    .word 0x000078DC, 0xFD00
    .word 0x000078DE, 0xFD00
    .word 0x000078E0, 0xFD00
    .word 0x000078E2, 0xFD00
    .word 0x000078F0, 0xFFE0
    .word 0x000078F2, 0xFFE0
    .word 0x000078F4, 0xFFE0
    .word 0x000078F6, 0xFFE0
    .word 0x000078F8, 0xFFE0
    .word 0x000078FA, 0xFFE0
    .word 0x00007908, 0x07EA
    .word 0x0000790A, 0x07EA
    .word 0x0000790C, 0x07EA
    .word 0x0000790E, 0x07EA
    .word 0x00007910, 0x07EA
    .word 0x00007912, 0x07EA
    .word 0x00007914, 0x07EA
    .word 0x00007916, 0x07EA
    .word 0x0000791C, 0x06FF
    .word 0x0000791E, 0x06FF
    .word 0x00007920, 0x06FF
    .word 0x00007922, 0x06FF
    .word 0x00007924, 0x06FF
    .word 0x00007926, 0x06FF
    .word 0x00007928, 0x06FF
    .word 0x0000792A, 0x06FF
    .word 0x0000792C, 0x06FF
    .word 0x0000792E, 0x06FF
    .word 0x00007950, 0x529F
    .word 0x00007952, 0x529F
    .word 0x00007954, 0x529F
    .word 0x00007956, 0x529F
    .word 0x00007958, 0x529F
    .word 0x0000795A, 0x529F
    .word 0x0000795C, 0x529F
    .word 0x0000795E, 0x529F
    .word 0x00007968, 0xB01F
    .word 0x0000796A, 0xB01F
    .word 0x0000796C, 0xB01F
    .word 0x0000796E, 0xB01F
    .word 0x00007970, 0xB01F
    .word 0x00007972, 0xB01F
    .word 0x0000797C, 0xF819
    .word 0x0000797E, 0xF819
    .word 0x00007998, 0xFA8A
    .word 0x0000799A, 0xFA8A
    .word 0x0000799C, 0xFA8A
    .word 0x0000799E, 0xFA8A
    .word 0x000079A0, 0xFA8A
    .word 0x000079A2, 0xFA8A
    .word 0x000079AC, 0x07F6
    .word 0x000079AE, 0x07F6
    .word 0x000079B0, 0x07F6
    .word 0x000079B2, 0x07F6
    .word 0x000079B4, 0x07F6
    .word 0x000079B6, 0x07F6
    .word 0x000079B8, 0x07F6
    .word 0x000079BA, 0x07F6
    .word 0x00007CC0, 0xFA8A
    .word 0x00007CC2, 0xFA8A
    .word 0x00007CC4, 0xFA8A
    .word 0x00007CC6, 0xFA8A
    .word 0x00007CC8, 0xFA8A
    .word 0x00007CCA, 0xFA8A
    .word 0x00007CCC, 0xFA8A
    .word 0x00007CCE, 0xFA8A
    .word 0x00007CD4, 0xFD00
    .word 0x00007CD6, 0xFD00
    .word 0x00007CD8, 0xFD00
    .word 0x00007CDA, 0xFD00
    .word 0x00007CDC, 0xFD00
    .word 0x00007CDE, 0xFD00
    .word 0x00007CE0, 0xFD00
    .word 0x00007CE2, 0xFD00
    .word 0x00007CF0, 0xFFE0
    .word 0x00007CF2, 0xFFE0
    .word 0x00007CF4, 0xFFE0
    .word 0x00007CF6, 0xFFE0
    .word 0x00007CF8, 0xFFE0
    .word 0x00007CFA, 0xFFE0
    .word 0x00007D08, 0x07EA
    .word 0x00007D0A, 0x07EA
    .word 0x00007D0C, 0x07EA
    .word 0x00007D0E, 0x07EA
    .word 0x00007D10, 0x07EA
    .word 0x00007D12, 0x07EA
    .word 0x00007D14, 0x07EA
    .word 0x00007D16, 0x07EA
    .word 0x00007D1C, 0x06FF
    .word 0x00007D1E, 0x06FF
    .word 0x00007D20, 0x06FF
    .word 0x00007D22, 0x06FF
    .word 0x00007D24, 0x06FF
    .word 0x00007D26, 0x06FF
    .word 0x00007D28, 0x06FF
    .word 0x00007D2A, 0x06FF
    .word 0x00007D2C, 0x06FF
    .word 0x00007D2E, 0x06FF
    .word 0x00007D50, 0x529F
    .word 0x00007D52, 0x529F
    .word 0x00007D54, 0x529F
    .word 0x00007D56, 0x529F
    .word 0x00007D58, 0x529F
    .word 0x00007D5A, 0x529F
    .word 0x00007D5C, 0x529F
    .word 0x00007D5E, 0x529F
    .word 0x00007D68, 0xB01F
    .word 0x00007D6A, 0xB01F
    .word 0x00007D6C, 0xB01F
    .word 0x00007D6E, 0xB01F
    .word 0x00007D70, 0xB01F
    .word 0x00007D72, 0xB01F
    .word 0x00007D7C, 0xF819
    .word 0x00007D7E, 0xF819
    .word 0x00007D98, 0xFA8A
    .word 0x00007D9A, 0xFA8A
    .word 0x00007D9C, 0xFA8A
    .word 0x00007D9E, 0xFA8A
    .word 0x00007DA0, 0xFA8A
    .word 0x00007DA2, 0xFA8A
    .word 0x00007DAC, 0x07F6
    .word 0x00007DAE, 0x07F6
    .word 0x00007DB0, 0x07F6
    .word 0x00007DB2, 0x07F6
    .word 0x00007DB4, 0x07F6
    .word 0x00007DB6, 0x07F6
    .word 0x00007DB8, 0x07F6
    .word 0x00007DBA, 0x07F6
    .word 0x000080BC, 0xFA8A
    .word 0x000080BE, 0xFA8A
    .word 0x000080D4, 0xFD00
    .word 0x000080D6, 0xFD00
    .word 0x000080E4, 0xFD00
    .word 0x000080E6, 0xFD00
    .word 0x000080EC, 0xFFE0
    .word 0x000080EE, 0xFFE0
    .word 0x000080FC, 0xFFE0
    .word 0x000080FE, 0xFFE0
    .word 0x00008104, 0x07EA
    .word 0x00008106, 0x07EA
    .word 0x0000811C, 0x06FF
    .word 0x0000811E, 0x06FF
    .word 0x0000814C, 0x529F
    .word 0x0000814E, 0x529F
    .word 0x00008164, 0xB01F
    .word 0x00008166, 0xB01F
    .word 0x00008174, 0xB01F
    .word 0x00008176, 0xB01F
    .word 0x0000817C, 0xF819
    .word 0x0000817E, 0xF819
    .word 0x00008194, 0xFA8A
    .word 0x00008196, 0xFA8A
    .word 0x000081A4, 0xFA8A
    .word 0x000081A6, 0xFA8A
    .word 0x000081AC, 0x07F6
    .word 0x000081AE, 0x07F6
    .word 0x000081BC, 0x07F6
    .word 0x000081BE, 0x07F6
    .word 0x000084BC, 0xFA8A
    .word 0x000084BE, 0xFA8A
    .word 0x000084D4, 0xFD00
    .word 0x000084D6, 0xFD00
    .word 0x000084E4, 0xFD00
    .word 0x000084E6, 0xFD00
    .word 0x000084EC, 0xFFE0
    .word 0x000084EE, 0xFFE0
    .word 0x000084FC, 0xFFE0
    .word 0x000084FE, 0xFFE0
    .word 0x00008504, 0x07EA
    .word 0x00008506, 0x07EA
    .word 0x0000851C, 0x06FF
    .word 0x0000851E, 0x06FF
    .word 0x0000854C, 0x529F
    .word 0x0000854E, 0x529F
    .word 0x00008564, 0xB01F
    .word 0x00008566, 0xB01F
    .word 0x00008574, 0xB01F
    .word 0x00008576, 0xB01F
    .word 0x0000857C, 0xF819
    .word 0x0000857E, 0xF819
    .word 0x00008594, 0xFA8A
    .word 0x00008596, 0xFA8A
    .word 0x000085A4, 0xFA8A
    .word 0x000085A6, 0xFA8A
    .word 0x000085AC, 0x07F6
    .word 0x000085AE, 0x07F6
    .word 0x000085BC, 0x07F6
    .word 0x000085BE, 0x07F6
    .word 0x000088BC, 0xFA8A
    .word 0x000088BE, 0xFA8A
    .word 0x000088D4, 0xFD00
    .word 0x000088D6, 0xFD00
    .word 0x000088E4, 0xFD00
    .word 0x000088E6, 0xFD00
    .word 0x000088EC, 0xFFE0
    .word 0x000088EE, 0xFFE0
    .word 0x000088FC, 0xFFE0
    .word 0x000088FE, 0xFFE0
    .word 0x00008904, 0x07EA
    .word 0x00008906, 0x07EA
    .word 0x0000891C, 0x06FF
    .word 0x0000891E, 0x06FF
    .word 0x0000894C, 0x529F
    .word 0x0000894E, 0x529F
    .word 0x00008964, 0xB01F
    .word 0x00008966, 0xB01F
    .word 0x00008974, 0xB01F
    .word 0x00008976, 0xB01F
    .word 0x0000897C, 0xF819
    .word 0x0000897E, 0xF819
    .word 0x00008994, 0xFA8A
    .word 0x00008996, 0xFA8A
    .word 0x000089A4, 0xFA8A
    .word 0x000089A6, 0xFA8A
    .word 0x000089AC, 0x07F6
    .word 0x000089AE, 0x07F6
    .word 0x000089BC, 0x07F6
    .word 0x000089BE, 0x07F6
    .word 0x00008CBC, 0xFA8A
    .word 0x00008CBE, 0xFA8A
    .word 0x00008CD4, 0xFD00
    .word 0x00008CD6, 0xFD00
    .word 0x00008CE4, 0xFD00
    .word 0x00008CE6, 0xFD00
    .word 0x00008CEC, 0xFFE0
    .word 0x00008CEE, 0xFFE0
    .word 0x00008CFC, 0xFFE0
    .word 0x00008CFE, 0xFFE0
    .word 0x00008D04, 0x07EA
    .word 0x00008D06, 0x07EA
    .word 0x00008D1C, 0x06FF
    .word 0x00008D1E, 0x06FF
    .word 0x00008D4C, 0x529F
    .word 0x00008D4E, 0x529F
    .word 0x00008D64, 0xB01F
    .word 0x00008D66, 0xB01F
    .word 0x00008D74, 0xB01F
    .word 0x00008D76, 0xB01F
    .word 0x00008D7C, 0xF819
    .word 0x00008D7E, 0xF819
    .word 0x00008D94, 0xFA8A
    .word 0x00008D96, 0xFA8A
    .word 0x00008DA4, 0xFA8A
    .word 0x00008DA6, 0xFA8A
    .word 0x00008DAC, 0x07F6
    .word 0x00008DAE, 0x07F6
    .word 0x00008DBC, 0x07F6
    .word 0x00008DBE, 0x07F6
    .word 0x000090C0, 0xFA8A
    .word 0x000090C2, 0xFA8A
    .word 0x000090C4, 0xFA8A
    .word 0x000090C6, 0xFA8A
    .word 0x000090C8, 0xFA8A
    .word 0x000090CA, 0xFA8A
    .word 0x000090D4, 0xFD00
    .word 0x000090D6, 0xFD00
    .word 0x000090D8, 0xFD00
    .word 0x000090DA, 0xFD00
    .word 0x000090DC, 0xFD00
    .word 0x000090DE, 0xFD00
    .word 0x000090E0, 0xFD00
    .word 0x000090E2, 0xFD00
    .word 0x000090EC, 0xFFE0
    .word 0x000090EE, 0xFFE0
    .word 0x000090F0, 0xFFE0
    .word 0x000090F2, 0xFFE0
    .word 0x000090F4, 0xFFE0
    .word 0x000090F6, 0xFFE0
    .word 0x000090F8, 0xFFE0
    .word 0x000090FA, 0xFFE0
    .word 0x000090FC, 0xFFE0
    .word 0x000090FE, 0xFFE0
    .word 0x00009104, 0x07EA
    .word 0x00009106, 0x07EA
    .word 0x0000911C, 0x06FF
    .word 0x0000911E, 0x06FF
    .word 0x00009120, 0x06FF
    .word 0x00009122, 0x06FF
    .word 0x00009124, 0x06FF
    .word 0x00009126, 0x06FF
    .word 0x00009128, 0x06FF
    .word 0x0000912A, 0x06FF
    .word 0x0000914C, 0x529F
    .word 0x0000914E, 0x529F
    .word 0x00009164, 0xB01F
    .word 0x00009166, 0xB01F
    .word 0x00009174, 0xB01F
    .word 0x00009176, 0xB01F
    .word 0x0000917C, 0xF819
    .word 0x0000917E, 0xF819
    .word 0x00009194, 0xFA8A
    .word 0x00009196, 0xFA8A
    .word 0x000091A4, 0xFA8A
    .word 0x000091A6, 0xFA8A
    .word 0x000091AC, 0x07F6
    .word 0x000091AE, 0x07F6
    .word 0x000091B0, 0x07F6
    .word 0x000091B2, 0x07F6
    .word 0x000091B4, 0x07F6
    .word 0x000091B6, 0x07F6
    .word 0x000091B8, 0x07F6
    .word 0x000091BA, 0x07F6
    .word 0x000094C0, 0xFA8A
    .word 0x000094C2, 0xFA8A
    .word 0x000094C4, 0xFA8A
    .word 0x000094C6, 0xFA8A
    .word 0x000094C8, 0xFA8A
    .word 0x000094CA, 0xFA8A
    .word 0x000094D4, 0xFD00
    .word 0x000094D6, 0xFD00
    .word 0x000094D8, 0xFD00
    .word 0x000094DA, 0xFD00
    .word 0x000094DC, 0xFD00
    .word 0x000094DE, 0xFD00
    .word 0x000094E0, 0xFD00
    .word 0x000094E2, 0xFD00
    .word 0x000094EC, 0xFFE0
    .word 0x000094EE, 0xFFE0
    .word 0x000094F0, 0xFFE0
    .word 0x000094F2, 0xFFE0
    .word 0x000094F4, 0xFFE0
    .word 0x000094F6, 0xFFE0
    .word 0x000094F8, 0xFFE0
    .word 0x000094FA, 0xFFE0
    .word 0x000094FC, 0xFFE0
    .word 0x000094FE, 0xFFE0
    .word 0x00009504, 0x07EA
    .word 0x00009506, 0x07EA
    .word 0x0000951C, 0x06FF
    .word 0x0000951E, 0x06FF
    .word 0x00009520, 0x06FF
    .word 0x00009522, 0x06FF
    .word 0x00009524, 0x06FF
    .word 0x00009526, 0x06FF
    .word 0x00009528, 0x06FF
    .word 0x0000952A, 0x06FF
    .word 0x0000954C, 0x529F
    .word 0x0000954E, 0x529F
    .word 0x00009564, 0xB01F
    .word 0x00009566, 0xB01F
    .word 0x00009574, 0xB01F
    .word 0x00009576, 0xB01F
    .word 0x0000957C, 0xF819
    .word 0x0000957E, 0xF819
    .word 0x00009594, 0xFA8A
    .word 0x00009596, 0xFA8A
    .word 0x000095A4, 0xFA8A
    .word 0x000095A6, 0xFA8A
    .word 0x000095AC, 0x07F6
    .word 0x000095AE, 0x07F6
    .word 0x000095B0, 0x07F6
    .word 0x000095B2, 0x07F6
    .word 0x000095B4, 0x07F6
    .word 0x000095B6, 0x07F6
    .word 0x000095B8, 0x07F6
    .word 0x000095BA, 0x07F6
    .word 0x000098CC, 0xFA8A
    .word 0x000098CE, 0xFA8A
    .word 0x000098D4, 0xFD00
    .word 0x000098D6, 0xFD00
    .word 0x000098EC, 0xFFE0
    .word 0x000098EE, 0xFFE0
    .word 0x000098FC, 0xFFE0
    .word 0x000098FE, 0xFFE0
    .word 0x00009904, 0x07EA
    .word 0x00009906, 0x07EA
    .word 0x0000991C, 0x06FF
    .word 0x0000991E, 0x06FF
    .word 0x0000994C, 0x529F
    .word 0x0000994E, 0x529F
    .word 0x00009964, 0xB01F
    .word 0x00009966, 0xB01F
    .word 0x00009974, 0xB01F
    .word 0x00009976, 0xB01F
    .word 0x0000997C, 0xF819
    .word 0x0000997E, 0xF819
    .word 0x00009994, 0xFA8A
    .word 0x00009996, 0xFA8A
    .word 0x000099A4, 0xFA8A
    .word 0x000099A6, 0xFA8A
    .word 0x000099AC, 0x07F6
    .word 0x000099AE, 0x07F6
    .word 0x000099B4, 0x07F6
    .word 0x000099B6, 0x07F6
    .word 0x00009CCC, 0xFA8A
    .word 0x00009CCE, 0xFA8A
    .word 0x00009CD4, 0xFD00
    .word 0x00009CD6, 0xFD00
    .word 0x00009CEC, 0xFFE0
    .word 0x00009CEE, 0xFFE0
    .word 0x00009CFC, 0xFFE0
    .word 0x00009CFE, 0xFFE0
    .word 0x00009D04, 0x07EA
    .word 0x00009D06, 0x07EA
    .word 0x00009D1C, 0x06FF
    .word 0x00009D1E, 0x06FF
    .word 0x00009D4C, 0x529F
    .word 0x00009D4E, 0x529F
    .word 0x00009D64, 0xB01F
    .word 0x00009D66, 0xB01F
    .word 0x00009D74, 0xB01F
    .word 0x00009D76, 0xB01F
    .word 0x00009D7C, 0xF819
    .word 0x00009D7E, 0xF819
    .word 0x00009D94, 0xFA8A
    .word 0x00009D96, 0xFA8A
    .word 0x00009DA4, 0xFA8A
    .word 0x00009DA6, 0xFA8A
    .word 0x00009DAC, 0x07F6
    .word 0x00009DAE, 0x07F6
    .word 0x00009DB4, 0x07F6
    .word 0x00009DB6, 0x07F6
    .word 0x0000A0CC, 0xFA8A
    .word 0x0000A0CE, 0xFA8A
    .word 0x0000A0D4, 0xFD00
    .word 0x0000A0D6, 0xFD00
    .word 0x0000A0EC, 0xFFE0
    .word 0x0000A0EE, 0xFFE0
    .word 0x0000A0FC, 0xFFE0
    .word 0x0000A0FE, 0xFFE0
    .word 0x0000A104, 0x07EA
    .word 0x0000A106, 0x07EA
    .word 0x0000A11C, 0x06FF
    .word 0x0000A11E, 0x06FF
    .word 0x0000A14C, 0x529F
    .word 0x0000A14E, 0x529F
    .word 0x0000A164, 0xB01F
    .word 0x0000A166, 0xB01F
    .word 0x0000A174, 0xB01F
    .word 0x0000A176, 0xB01F
    .word 0x0000A17C, 0xF819
    .word 0x0000A17E, 0xF819
    .word 0x0000A194, 0xFA8A
    .word 0x0000A196, 0xFA8A
    .word 0x0000A1A4, 0xFA8A
    .word 0x0000A1A6, 0xFA8A
    .word 0x0000A1AC, 0x07F6
    .word 0x0000A1AE, 0x07F6
    .word 0x0000A1B8, 0x07F6
    .word 0x0000A1BA, 0x07F6
    .word 0x0000A4CC, 0xFA8A
    .word 0x0000A4CE, 0xFA8A
    .word 0x0000A4D4, 0xFD00
    .word 0x0000A4D6, 0xFD00
    .word 0x0000A4EC, 0xFFE0
    .word 0x0000A4EE, 0xFFE0
    .word 0x0000A4FC, 0xFFE0
    .word 0x0000A4FE, 0xFFE0
    .word 0x0000A504, 0x07EA
    .word 0x0000A506, 0x07EA
    .word 0x0000A51C, 0x06FF
    .word 0x0000A51E, 0x06FF
    .word 0x0000A54C, 0x529F
    .word 0x0000A54E, 0x529F
    .word 0x0000A564, 0xB01F
    .word 0x0000A566, 0xB01F
    .word 0x0000A574, 0xB01F
    .word 0x0000A576, 0xB01F
    .word 0x0000A57C, 0xF819
    .word 0x0000A57E, 0xF819
    .word 0x0000A594, 0xFA8A
    .word 0x0000A596, 0xFA8A
    .word 0x0000A5A4, 0xFA8A
    .word 0x0000A5A6, 0xFA8A
    .word 0x0000A5AC, 0x07F6
    .word 0x0000A5AE, 0x07F6
    .word 0x0000A5B8, 0x07F6
    .word 0x0000A5BA, 0x07F6
    .word 0x0000A8BC, 0xFA8A
    .word 0x0000A8BE, 0xFA8A
    .word 0x0000A8C0, 0xFA8A
    .word 0x0000A8C2, 0xFA8A
    .word 0x0000A8C4, 0xFA8A
    .word 0x0000A8C6, 0xFA8A
    .word 0x0000A8C8, 0xFA8A
    .word 0x0000A8CA, 0xFA8A
    .word 0x0000A8D4, 0xFD00
    .word 0x0000A8D6, 0xFD00
    .word 0x0000A8EC, 0xFFE0
    .word 0x0000A8EE, 0xFFE0
    .word 0x0000A8FC, 0xFFE0
    .word 0x0000A8FE, 0xFFE0
    .word 0x0000A908, 0x07EA
    .word 0x0000A90A, 0x07EA
    .word 0x0000A90C, 0x07EA
    .word 0x0000A90E, 0x07EA
    .word 0x0000A910, 0x07EA
    .word 0x0000A912, 0x07EA
    .word 0x0000A914, 0x07EA
    .word 0x0000A916, 0x07EA
    .word 0x0000A91C, 0x06FF
    .word 0x0000A91E, 0x06FF
    .word 0x0000A920, 0x06FF
    .word 0x0000A922, 0x06FF
    .word 0x0000A924, 0x06FF
    .word 0x0000A926, 0x06FF
    .word 0x0000A928, 0x06FF
    .word 0x0000A92A, 0x06FF
    .word 0x0000A92C, 0x06FF
    .word 0x0000A92E, 0x06FF
    .word 0x0000A950, 0x529F
    .word 0x0000A952, 0x529F
    .word 0x0000A954, 0x529F
    .word 0x0000A956, 0x529F
    .word 0x0000A958, 0x529F
    .word 0x0000A95A, 0x529F
    .word 0x0000A95C, 0x529F
    .word 0x0000A95E, 0x529F
    .word 0x0000A968, 0xB01F
    .word 0x0000A96A, 0xB01F
    .word 0x0000A96C, 0xB01F
    .word 0x0000A96E, 0xB01F
    .word 0x0000A970, 0xB01F
    .word 0x0000A972, 0xB01F
    .word 0x0000A97C, 0xF819
    .word 0x0000A97E, 0xF819
    .word 0x0000A980, 0xF819
    .word 0x0000A982, 0xF819
    .word 0x0000A984, 0xF819
    .word 0x0000A986, 0xF819
    .word 0x0000A988, 0xF819
    .word 0x0000A98A, 0xF819
    .word 0x0000A98C, 0xF819
    .word 0x0000A98E, 0xF819
    .word 0x0000A998, 0xFA8A
    .word 0x0000A99A, 0xFA8A
    .word 0x0000A99C, 0xFA8A
    .word 0x0000A99E, 0xFA8A
    .word 0x0000A9A0, 0xFA8A
    .word 0x0000A9A2, 0xFA8A
    .word 0x0000A9AC, 0x07F6
    .word 0x0000A9AE, 0x07F6
    .word 0x0000A9BC, 0x07F6
    .word 0x0000A9BE, 0x07F6
    .word 0x0000ACBC, 0xFA8A
    .word 0x0000ACBE, 0xFA8A
    .word 0x0000ACC0, 0xFA8A
    .word 0x0000ACC2, 0xFA8A
    .word 0x0000ACC4, 0xFA8A
    .word 0x0000ACC6, 0xFA8A
    .word 0x0000ACC8, 0xFA8A
    .word 0x0000ACCA, 0xFA8A
    .word 0x0000ACD4, 0xFD00
    .word 0x0000ACD6, 0xFD00
    .word 0x0000ACEC, 0xFFE0
    .word 0x0000ACEE, 0xFFE0
    .word 0x0000ACFC, 0xFFE0
    .word 0x0000ACFE, 0xFFE0
    .word 0x0000AD08, 0x07EA
    .word 0x0000AD0A, 0x07EA
    .word 0x0000AD0C, 0x07EA
    .word 0x0000AD0E, 0x07EA
    .word 0x0000AD10, 0x07EA
    .word 0x0000AD12, 0x07EA
    .word 0x0000AD14, 0x07EA
    .word 0x0000AD16, 0x07EA
    .word 0x0000AD1C, 0x06FF
    .word 0x0000AD1E, 0x06FF
    .word 0x0000AD20, 0x06FF
    .word 0x0000AD22, 0x06FF
    .word 0x0000AD24, 0x06FF
    .word 0x0000AD26, 0x06FF
    .word 0x0000AD28, 0x06FF
    .word 0x0000AD2A, 0x06FF
    .word 0x0000AD2C, 0x06FF
    .word 0x0000AD2E, 0x06FF
    .word 0x0000AD50, 0x529F
    .word 0x0000AD52, 0x529F
    .word 0x0000AD54, 0x529F
    .word 0x0000AD56, 0x529F
    .word 0x0000AD58, 0x529F
    .word 0x0000AD5A, 0x529F
    .word 0x0000AD5C, 0x529F
    .word 0x0000AD5E, 0x529F
    .word 0x0000AD68, 0xB01F
    .word 0x0000AD6A, 0xB01F
    .word 0x0000AD6C, 0xB01F
    .word 0x0000AD6E, 0xB01F
    .word 0x0000AD70, 0xB01F
    .word 0x0000AD72, 0xB01F
    .word 0x0000AD7C, 0xF819
    .word 0x0000AD7E, 0xF819
    .word 0x0000AD80, 0xF819
    .word 0x0000AD82, 0xF819
    .word 0x0000AD84, 0xF819
    .word 0x0000AD86, 0xF819
    .word 0x0000AD88, 0xF819
    .word 0x0000AD8A, 0xF819
    .word 0x0000AD8C, 0xF819
    .word 0x0000AD8E, 0xF819
    .word 0x0000AD98, 0xFA8A
    .word 0x0000AD9A, 0xFA8A
    .word 0x0000AD9C, 0xFA8A
    .word 0x0000AD9E, 0xFA8A
    .word 0x0000ADA0, 0xFA8A
    .word 0x0000ADA2, 0xFA8A
    .word 0x0000ADAC, 0x07F6
    .word 0x0000ADAE, 0x07F6
    .word 0x0000ADBC, 0x07F6
    .word 0x0000ADBE, 0x07F6
    .word 0x0000E850, 0x03D6
    .word 0x0000E852, 0x03D6
    .word 0x0000E854, 0x03D6
    .word 0x0000E856, 0x03D6
    .word 0x0000E858, 0x03D6
    .word 0x0000E85A, 0x03D6
    .word 0x0000E85C, 0x03D6
    .word 0x0000E85E, 0x03D6
    .word 0x0000E860, 0x03D6
    .word 0x0000E862, 0x03D6
    .word 0x0000E864, 0x03D6
    .word 0x0000E866, 0x03D6
    .word 0x0000E868, 0x03D6
    .word 0x0000E86A, 0x03D6
    .word 0x0000E86C, 0x03D6
    .word 0x0000E86E, 0x03D6
    .word 0x0000E870, 0x03D6
    .word 0x0000E872, 0x03D6
    .word 0x0000E874, 0x03D6
    .word 0x0000E876, 0x03D6
    .word 0x0000E878, 0x03D6
    .word 0x0000E87A, 0x03D6
    .word 0x0000E87C, 0x03D6
    .word 0x0000E87E, 0x03D6
    .word 0x0000E880, 0x03D6
    .word 0x0000E882, 0x03D6
    .word 0x0000E884, 0x03D6
    .word 0x0000E886, 0x03D6
    .word 0x0000E888, 0x03D6
    .word 0x0000E88A, 0x03D6
    .word 0x0000E88C, 0x03D6
    .word 0x0000E88E, 0x03D6
    .word 0x0000E890, 0x03D6
    .word 0x0000E892, 0x03D6
    .word 0x0000E894, 0x03D6
    .word 0x0000E896, 0x03D6
    .word 0x0000E898, 0x03D6
    .word 0x0000E89A, 0x03D6
    .word 0x0000E89C, 0x03D6
    .word 0x0000E89E, 0x03D6
    .word 0x0000E8A0, 0x03D6
    .word 0x0000E8A2, 0x03D6
    .word 0x0000E8A4, 0x03D6
    .word 0x0000E8A6, 0x03D6
    .word 0x0000E8A8, 0x03D6
    .word 0x0000E8AA, 0x03D6
    .word 0x0000E8AC, 0x03D6
    .word 0x0000E8AE, 0x03D6
    .word 0x0000E8B0, 0x03D6
    .word 0x0000E8B2, 0x03D6
    .word 0x0000E8B4, 0x03D6
    .word 0x0000E8B6, 0x03D6
    .word 0x0000E8B8, 0x03D6
    .word 0x0000E8BA, 0x03D6
    .word 0x0000E8BC, 0x03D6
    .word 0x0000E8BE, 0x03D6
    .word 0x0000E8C0, 0x03D6
    .word 0x0000E8C2, 0x03D6
    .word 0x0000E8C4, 0x03D6
    .word 0x0000E8C6, 0x03D6
    .word 0x0000E8C8, 0x03D6
    .word 0x0000E8CA, 0x03D6
    .word 0x0000E8CC, 0x03D6
    .word 0x0000E8CE, 0x03D6
    .word 0x0000E8D0, 0x03D6
    .word 0x0000E8D2, 0x03D6
    .word 0x0000E8D4, 0x03D6
    .word 0x0000E8D6, 0x03D6
    .word 0x0000E8D8, 0x03D6
    .word 0x0000E8DA, 0x03D6
    .word 0x0000E8DC, 0x03D6
    .word 0x0000E8DE, 0x03D6
    .word 0x0000E8E0, 0x03D6
    .word 0x0000E8E2, 0x03D6
    .word 0x0000E8E4, 0x03D6
    .word 0x0000E8E6, 0x03D6
    .word 0x0000E8E8, 0x03D6
    .word 0x0000E8EA, 0x03D6
    .word 0x0000E8EC, 0x03D6
    .word 0x0000E8EE, 0x03D6
    .word 0x0000E8F0, 0x03D6
    .word 0x0000E8F2, 0x03D6
    .word 0x0000E8F4, 0x03D6
    .word 0x0000E8F6, 0x03D6
    .word 0x0000E8F8, 0x03D6
    .word 0x0000E8FA, 0x03D6
    .word 0x0000E8FC, 0x03D6
    .word 0x0000E8FE, 0x03D6
    .word 0x0000E900, 0x03D6
    .word 0x0000E902, 0x03D6
    .word 0x0000E904, 0x03D6
    .word 0x0000E906, 0x03D6
    .word 0x0000E908, 0x03D6
    .word 0x0000E90A, 0x03D6
    .word 0x0000E90C, 0x03D6
    .word 0x0000E90E, 0x03D6
    .word 0x0000E910, 0x03D6
    .word 0x0000E912, 0x03D6
    .word 0x0000E914, 0x03D6
    .word 0x0000E916, 0x03D6
    .word 0x0000E918, 0x03D6
    .word 0x0000E91A, 0x03D6
    .word 0x0000E91C, 0x03D6
    .word 0x0000E91E, 0x03D6
    .word 0x0000E920, 0x03D6
    .word 0x0000E922, 0x03D6
    .word 0x0000E924, 0x03D6
    .word 0x0000E926, 0x03D6
    .word 0x0000E928, 0x03D6
    .word 0x0000E92A, 0x03D6
    .word 0x0000E92C, 0x03D6
    .word 0x0000E92E, 0x03D6
    .word 0x0000E930, 0x03D6
    .word 0x0000E932, 0x03D6
    .word 0x0000E934, 0x03D6
    .word 0x0000E936, 0x03D6
    .word 0x0000E938, 0x03D6
    .word 0x0000E93A, 0x03D6
    .word 0x0000E93C, 0x03D6
    .word 0x0000E93E, 0x03D6
    .word 0x0000E940, 0x03D6
    .word 0x0000E942, 0x03D6
    .word 0x0000E944, 0x03D6
    .word 0x0000E946, 0x03D6
    .word 0x0000E948, 0x03D6
    .word 0x0000E94A, 0x03D6
    .word 0x0000E94C, 0x03D6
    .word 0x0000E94E, 0x03D6
    .word 0x0000E950, 0x03D6
    .word 0x0000E952, 0x03D6
    .word 0x0000E954, 0x03D6
    .word 0x0000E956, 0x03D6
    .word 0x0000E958, 0x03D6
    .word 0x0000E95A, 0x03D6
    .word 0x0000E95C, 0x03D6
    .word 0x0000E95E, 0x03D6
    .word 0x0000E960, 0x03D6
    .word 0x0000E962, 0x03D6
    .word 0x0000E964, 0x03D6
    .word 0x0000E966, 0x03D6
    .word 0x0000E968, 0x03D6
    .word 0x0000E96A, 0x03D6
    .word 0x0000E96C, 0x03D6
    .word 0x0000E96E, 0x03D6
    .word 0x0000E970, 0x03D6
    .word 0x0000E972, 0x03D6
    .word 0x0000E974, 0x03D6
    .word 0x0000E976, 0x03D6
    .word 0x0000E978, 0x03D6
    .word 0x0000E97A, 0x03D6
    .word 0x0000E97C, 0x03D6
    .word 0x0000E97E, 0x03D6
    .word 0x0000E980, 0x03D6
    .word 0x0000E982, 0x03D6
    .word 0x0000E984, 0x03D6
    .word 0x0000E986, 0x03D6
    .word 0x0000E988, 0x03D6
    .word 0x0000E98A, 0x03D6
    .word 0x0000E98C, 0x03D6
    .word 0x0000E98E, 0x03D6
    .word 0x0000E990, 0x03D6
    .word 0x0000E992, 0x03D6
    .word 0x0000E994, 0x03D6
    .word 0x0000E996, 0x03D6
    .word 0x0000E998, 0x03D6
    .word 0x0000E99A, 0x03D6
    .word 0x0000E99C, 0x03D6
    .word 0x0000E99E, 0x03D6
    .word 0x0000E9A0, 0x03D6
    .word 0x0000E9A2, 0x03D6
    .word 0x0000E9A4, 0x03D6
    .word 0x0000E9A6, 0x03D6
    .word 0x0000E9A8, 0x03D6
    .word 0x0000E9AA, 0x03D6
    .word 0x0000E9AC, 0x03D6
    .word 0x0000E9AE, 0x03D6
    .word 0x0000E9B0, 0x03D6
    .word 0x0000E9B2, 0x03D6
    .word 0x0000E9B4, 0x03D6
    .word 0x0000E9B6, 0x03D6
    .word 0x0000E9B8, 0x03D6
    .word 0x0000E9BA, 0x03D6
    .word 0x0000E9BC, 0x03D6
    .word 0x0000E9BE, 0x03D6
    .word 0x0000E9C0, 0x03D6
    .word 0x0000E9C2, 0x03D6
    .word 0x0000E9C4, 0x03D6
    .word 0x0000E9C6, 0x03D6
    .word 0x0000E9C8, 0x03D6
    .word 0x0000E9CA, 0x03D6
    .word 0x0000E9CC, 0x03D6
    .word 0x0000E9CE, 0x03D6
    .word 0x0000E9D0, 0x03D6
    .word 0x0000E9D2, 0x03D6
    .word 0x0000E9D4, 0x03D6
    .word 0x0000E9D6, 0x03D6
    .word 0x0000E9D8, 0x03D6
    .word 0x0000E9DA, 0x03D6
    .word 0x0000E9DC, 0x03D6
    .word 0x0000E9DE, 0x03D6
    .word 0x0000E9E0, 0x03D6
    .word 0x0000E9E2, 0x03D6
    .word 0x0000E9E4, 0x03D6
    .word 0x0000E9E6, 0x03D6
    .word 0x0000E9E8, 0x03D6
    .word 0x0000E9EA, 0x03D6
    .word 0x0000E9EC, 0x03D6
    .word 0x0000E9EE, 0x03D6
    .word 0x0000E9F0, 0x03D6
    .word 0x0000E9F2, 0x03D6
    .word 0x0000E9F4, 0x03D6
    .word 0x0000E9F6, 0x03D6
    .word 0x0000E9F8, 0x03D6
    .word 0x0000E9FA, 0x03D6
    .word 0x0000E9FC, 0x03D6
    .word 0x0000E9FE, 0x03D6
    .word 0x0000EA00, 0x03D6
    .word 0x0000EA02, 0x03D6
    .word 0x0000EA04, 0x03D6
    .word 0x0000EA06, 0x03D6
    .word 0x0000EA08, 0x03D6
    .word 0x0000EA0A, 0x03D6
    .word 0x0000EA0C, 0x03D6
    .word 0x0000EA0E, 0x03D6
    .word 0x0000EA10, 0x03D6
    .word 0x0000EA12, 0x03D6
    .word 0x0000EA14, 0x03D6
    .word 0x0000EA16, 0x03D6
    .word 0x0000EA18, 0x03D6
    .word 0x0000EA1A, 0x03D6
    .word 0x0000EA1C, 0x03D6
    .word 0x0000EA1E, 0x03D6
    .word 0x0000EA20, 0x03D6
    .word 0x0000EA22, 0x03D6
    .word 0x0000EA24, 0x03D6
    .word 0x0000EA26, 0x03D6
    .word 0x0000EA28, 0x03D6
    .word 0x0000EA2A, 0x03D6
    .word 0x0000EA2C, 0x03D6
    .word 0x0000EA2E, 0x03D6
    .word 0x0001D8BC, 0x07FF
    .word 0x0001D8BE, 0x07FF
    .word 0x0001D8C0, 0x07FF
    .word 0x0001D8C2, 0x07FF
    .word 0x0001D8C4, 0x07FF
    .word 0x0001D8C6, 0x07FF
    .word 0x0001D8C8, 0x07FF
    .word 0x0001D8CA, 0x07FF
    .word 0x0001D8D4, 0x07FF
    .word 0x0001D8D6, 0x07FF
    .word 0x0001D8D8, 0x07FF
    .word 0x0001D8DA, 0x07FF
    .word 0x0001D8DC, 0x07FF
    .word 0x0001D8DE, 0x07FF
    .word 0x0001D8E0, 0x07FF
    .word 0x0001D8E2, 0x07FF
    .word 0x0001D8EC, 0x07FF
    .word 0x0001D8EE, 0x07FF
    .word 0x0001D8F0, 0x07FF
    .word 0x0001D8F2, 0x07FF
    .word 0x0001D8F4, 0x07FF
    .word 0x0001D8F6, 0x07FF
    .word 0x0001D8F8, 0x07FF
    .word 0x0001D8FA, 0x07FF
    .word 0x0001D8FC, 0x07FF
    .word 0x0001D8FE, 0x07FF
    .word 0x0001D908, 0x07FF
    .word 0x0001D90A, 0x07FF
    .word 0x0001D90C, 0x07FF
    .word 0x0001D90E, 0x07FF
    .word 0x0001D910, 0x07FF
    .word 0x0001D912, 0x07FF
    .word 0x0001D914, 0x07FF
    .word 0x0001D916, 0x07FF
    .word 0x0001D920, 0x07FF
    .word 0x0001D922, 0x07FF
    .word 0x0001D924, 0x07FF
    .word 0x0001D926, 0x07FF
    .word 0x0001D928, 0x07FF
    .word 0x0001D92A, 0x07FF
    .word 0x0001D92C, 0x07FF
    .word 0x0001D92E, 0x07FF
    .word 0x0001D950, 0x07FF
    .word 0x0001D952, 0x07FF
    .word 0x0001D954, 0x07FF
    .word 0x0001D956, 0x07FF
    .word 0x0001D958, 0x07FF
    .word 0x0001D95A, 0x07FF
    .word 0x0001D95C, 0x07FF
    .word 0x0001D95E, 0x07FF
    .word 0x0001D964, 0x07FF
    .word 0x0001D966, 0x07FF
    .word 0x0001D968, 0x07FF
    .word 0x0001D96A, 0x07FF
    .word 0x0001D96C, 0x07FF
    .word 0x0001D96E, 0x07FF
    .word 0x0001D970, 0x07FF
    .word 0x0001D972, 0x07FF
    .word 0x0001D980, 0x07FF
    .word 0x0001D982, 0x07FF
    .word 0x0001D984, 0x07FF
    .word 0x0001D986, 0x07FF
    .word 0x0001D988, 0x07FF
    .word 0x0001D98A, 0x07FF
    .word 0x0001D998, 0x07FF
    .word 0x0001D99A, 0x07FF
    .word 0x0001D99C, 0x07FF
    .word 0x0001D99E, 0x07FF
    .word 0x0001D9A0, 0x07FF
    .word 0x0001D9A2, 0x07FF
    .word 0x0001D9A4, 0x07FF
    .word 0x0001D9A6, 0x07FF
    .word 0x0001D9AC, 0x07FF
    .word 0x0001D9AE, 0x07FF
    .word 0x0001D9B0, 0x07FF
    .word 0x0001D9B2, 0x07FF
    .word 0x0001D9B4, 0x07FF
    .word 0x0001D9B6, 0x07FF
    .word 0x0001D9B8, 0x07FF
    .word 0x0001D9BA, 0x07FF
    .word 0x0001D9BC, 0x07FF
    .word 0x0001D9BE, 0x07FF
    .word 0x0001DCBC, 0x07FF
    .word 0x0001DCBE, 0x07FF
    .word 0x0001DCC0, 0x07FF
    .word 0x0001DCC2, 0x07FF
    .word 0x0001DCC4, 0x07FF
    .word 0x0001DCC6, 0x07FF
    .word 0x0001DCC8, 0x07FF
    .word 0x0001DCCA, 0x07FF
    .word 0x0001DCD4, 0x07FF
    .word 0x0001DCD6, 0x07FF
    .word 0x0001DCD8, 0x07FF
    .word 0x0001DCDA, 0x07FF
    .word 0x0001DCDC, 0x07FF
    .word 0x0001DCDE, 0x07FF
    .word 0x0001DCE0, 0x07FF
    .word 0x0001DCE2, 0x07FF
    .word 0x0001DCEC, 0x07FF
    .word 0x0001DCEE, 0x07FF
    .word 0x0001DCF0, 0x07FF
    .word 0x0001DCF2, 0x07FF
    .word 0x0001DCF4, 0x07FF
    .word 0x0001DCF6, 0x07FF
    .word 0x0001DCF8, 0x07FF
    .word 0x0001DCFA, 0x07FF
    .word 0x0001DCFC, 0x07FF
    .word 0x0001DCFE, 0x07FF
    .word 0x0001DD08, 0x07FF
    .word 0x0001DD0A, 0x07FF
    .word 0x0001DD0C, 0x07FF
    .word 0x0001DD0E, 0x07FF
    .word 0x0001DD10, 0x07FF
    .word 0x0001DD12, 0x07FF
    .word 0x0001DD14, 0x07FF
    .word 0x0001DD16, 0x07FF
    .word 0x0001DD20, 0x07FF
    .word 0x0001DD22, 0x07FF
    .word 0x0001DD24, 0x07FF
    .word 0x0001DD26, 0x07FF
    .word 0x0001DD28, 0x07FF
    .word 0x0001DD2A, 0x07FF
    .word 0x0001DD2C, 0x07FF
    .word 0x0001DD2E, 0x07FF
    .word 0x0001DD50, 0x07FF
    .word 0x0001DD52, 0x07FF
    .word 0x0001DD54, 0x07FF
    .word 0x0001DD56, 0x07FF
    .word 0x0001DD58, 0x07FF
    .word 0x0001DD5A, 0x07FF
    .word 0x0001DD5C, 0x07FF
    .word 0x0001DD5E, 0x07FF
    .word 0x0001DD64, 0x07FF
    .word 0x0001DD66, 0x07FF
    .word 0x0001DD68, 0x07FF
    .word 0x0001DD6A, 0x07FF
    .word 0x0001DD6C, 0x07FF
    .word 0x0001DD6E, 0x07FF
    .word 0x0001DD70, 0x07FF
    .word 0x0001DD72, 0x07FF
    .word 0x0001DD80, 0x07FF
    .word 0x0001DD82, 0x07FF
    .word 0x0001DD84, 0x07FF
    .word 0x0001DD86, 0x07FF
    .word 0x0001DD88, 0x07FF
    .word 0x0001DD8A, 0x07FF
    .word 0x0001DD98, 0x07FF
    .word 0x0001DD9A, 0x07FF
    .word 0x0001DD9C, 0x07FF
    .word 0x0001DD9E, 0x07FF
    .word 0x0001DDA0, 0x07FF
    .word 0x0001DDA2, 0x07FF
    .word 0x0001DDA4, 0x07FF
    .word 0x0001DDA6, 0x07FF
    .word 0x0001DDAC, 0x07FF
    .word 0x0001DDAE, 0x07FF
    .word 0x0001DDB0, 0x07FF
    .word 0x0001DDB2, 0x07FF
    .word 0x0001DDB4, 0x07FF
    .word 0x0001DDB6, 0x07FF
    .word 0x0001DDB8, 0x07FF
    .word 0x0001DDBA, 0x07FF
    .word 0x0001DDBC, 0x07FF
    .word 0x0001DDBE, 0x07FF
    .word 0x0001E0BC, 0x07FF
    .word 0x0001E0BE, 0x07FF
    .word 0x0001E0CC, 0x07FF
    .word 0x0001E0CE, 0x07FF
    .word 0x0001E0D4, 0x07FF
    .word 0x0001E0D6, 0x07FF
    .word 0x0001E0E4, 0x07FF
    .word 0x0001E0E6, 0x07FF
    .word 0x0001E0EC, 0x07FF
    .word 0x0001E0EE, 0x07FF
    .word 0x0001E104, 0x07FF
    .word 0x0001E106, 0x07FF
    .word 0x0001E11C, 0x07FF
    .word 0x0001E11E, 0x07FF
    .word 0x0001E14C, 0x07FF
    .word 0x0001E14E, 0x07FF
    .word 0x0001E164, 0x07FF
    .word 0x0001E166, 0x07FF
    .word 0x0001E174, 0x07FF
    .word 0x0001E176, 0x07FF
    .word 0x0001E17C, 0x07FF
    .word 0x0001E17E, 0x07FF
    .word 0x0001E18C, 0x07FF
    .word 0x0001E18E, 0x07FF
    .word 0x0001E194, 0x07FF
    .word 0x0001E196, 0x07FF
    .word 0x0001E1AC, 0x07FF
    .word 0x0001E1AE, 0x07FF
    .word 0x0001E4BC, 0x07FF
    .word 0x0001E4BE, 0x07FF
    .word 0x0001E4CC, 0x07FF
    .word 0x0001E4CE, 0x07FF
    .word 0x0001E4D4, 0x07FF
    .word 0x0001E4D6, 0x07FF
    .word 0x0001E4E4, 0x07FF
    .word 0x0001E4E6, 0x07FF
    .word 0x0001E4EC, 0x07FF
    .word 0x0001E4EE, 0x07FF
    .word 0x0001E504, 0x07FF
    .word 0x0001E506, 0x07FF
    .word 0x0001E51C, 0x07FF
    .word 0x0001E51E, 0x07FF
    .word 0x0001E54C, 0x07FF
    .word 0x0001E54E, 0x07FF
    .word 0x0001E564, 0x07FF
    .word 0x0001E566, 0x07FF
    .word 0x0001E574, 0x07FF
    .word 0x0001E576, 0x07FF
    .word 0x0001E57C, 0x07FF
    .word 0x0001E57E, 0x07FF
    .word 0x0001E58C, 0x07FF
    .word 0x0001E58E, 0x07FF
    .word 0x0001E594, 0x07FF
    .word 0x0001E596, 0x07FF
    .word 0x0001E5AC, 0x07FF
    .word 0x0001E5AE, 0x07FF
    .word 0x0001E8BC, 0x07FF
    .word 0x0001E8BE, 0x07FF
    .word 0x0001E8CC, 0x07FF
    .word 0x0001E8CE, 0x07FF
    .word 0x0001E8D4, 0x07FF
    .word 0x0001E8D6, 0x07FF
    .word 0x0001E8E4, 0x07FF
    .word 0x0001E8E6, 0x07FF
    .word 0x0001E8EC, 0x07FF
    .word 0x0001E8EE, 0x07FF
    .word 0x0001E904, 0x07FF
    .word 0x0001E906, 0x07FF
    .word 0x0001E91C, 0x07FF
    .word 0x0001E91E, 0x07FF
    .word 0x0001E94C, 0x07FF
    .word 0x0001E94E, 0x07FF
    .word 0x0001E964, 0x07FF
    .word 0x0001E966, 0x07FF
    .word 0x0001E974, 0x07FF
    .word 0x0001E976, 0x07FF
    .word 0x0001E97C, 0x07FF
    .word 0x0001E97E, 0x07FF
    .word 0x0001E98C, 0x07FF
    .word 0x0001E98E, 0x07FF
    .word 0x0001E994, 0x07FF
    .word 0x0001E996, 0x07FF
    .word 0x0001E9AC, 0x07FF
    .word 0x0001E9AE, 0x07FF
    .word 0x0001ECBC, 0x07FF
    .word 0x0001ECBE, 0x07FF
    .word 0x0001ECCC, 0x07FF
    .word 0x0001ECCE, 0x07FF
    .word 0x0001ECD4, 0x07FF
    .word 0x0001ECD6, 0x07FF
    .word 0x0001ECE4, 0x07FF
    .word 0x0001ECE6, 0x07FF
    .word 0x0001ECEC, 0x07FF
    .word 0x0001ECEE, 0x07FF
    .word 0x0001ED04, 0x07FF
    .word 0x0001ED06, 0x07FF
    .word 0x0001ED1C, 0x07FF
    .word 0x0001ED1E, 0x07FF
    .word 0x0001ED4C, 0x07FF
    .word 0x0001ED4E, 0x07FF
    .word 0x0001ED64, 0x07FF
    .word 0x0001ED66, 0x07FF
    .word 0x0001ED74, 0x07FF
    .word 0x0001ED76, 0x07FF
    .word 0x0001ED7C, 0x07FF
    .word 0x0001ED7E, 0x07FF
    .word 0x0001ED8C, 0x07FF
    .word 0x0001ED8E, 0x07FF
    .word 0x0001ED94, 0x07FF
    .word 0x0001ED96, 0x07FF
    .word 0x0001EDAC, 0x07FF
    .word 0x0001EDAE, 0x07FF
    .word 0x0001F0BC, 0x07FF
    .word 0x0001F0BE, 0x07FF
    .word 0x0001F0C0, 0x07FF
    .word 0x0001F0C2, 0x07FF
    .word 0x0001F0C4, 0x07FF
    .word 0x0001F0C6, 0x07FF
    .word 0x0001F0C8, 0x07FF
    .word 0x0001F0CA, 0x07FF
    .word 0x0001F0D4, 0x07FF
    .word 0x0001F0D6, 0x07FF
    .word 0x0001F0D8, 0x07FF
    .word 0x0001F0DA, 0x07FF
    .word 0x0001F0DC, 0x07FF
    .word 0x0001F0DE, 0x07FF
    .word 0x0001F0E0, 0x07FF
    .word 0x0001F0E2, 0x07FF
    .word 0x0001F0EC, 0x07FF
    .word 0x0001F0EE, 0x07FF
    .word 0x0001F0F0, 0x07FF
    .word 0x0001F0F2, 0x07FF
    .word 0x0001F0F4, 0x07FF
    .word 0x0001F0F6, 0x07FF
    .word 0x0001F0F8, 0x07FF
    .word 0x0001F0FA, 0x07FF
    .word 0x0001F108, 0x07FF
    .word 0x0001F10A, 0x07FF
    .word 0x0001F10C, 0x07FF
    .word 0x0001F10E, 0x07FF
    .word 0x0001F110, 0x07FF
    .word 0x0001F112, 0x07FF
    .word 0x0001F120, 0x07FF
    .word 0x0001F122, 0x07FF
    .word 0x0001F124, 0x07FF
    .word 0x0001F126, 0x07FF
    .word 0x0001F128, 0x07FF
    .word 0x0001F12A, 0x07FF
    .word 0x0001F150, 0x07FF
    .word 0x0001F152, 0x07FF
    .word 0x0001F154, 0x07FF
    .word 0x0001F156, 0x07FF
    .word 0x0001F158, 0x07FF
    .word 0x0001F15A, 0x07FF
    .word 0x0001F164, 0x07FF
    .word 0x0001F166, 0x07FF
    .word 0x0001F168, 0x07FF
    .word 0x0001F16A, 0x07FF
    .word 0x0001F16C, 0x07FF
    .word 0x0001F16E, 0x07FF
    .word 0x0001F170, 0x07FF
    .word 0x0001F172, 0x07FF
    .word 0x0001F17C, 0x07FF
    .word 0x0001F17E, 0x07FF
    .word 0x0001F180, 0x07FF
    .word 0x0001F182, 0x07FF
    .word 0x0001F184, 0x07FF
    .word 0x0001F186, 0x07FF
    .word 0x0001F188, 0x07FF
    .word 0x0001F18A, 0x07FF
    .word 0x0001F18C, 0x07FF
    .word 0x0001F18E, 0x07FF
    .word 0x0001F194, 0x07FF
    .word 0x0001F196, 0x07FF
    .word 0x0001F1AC, 0x07FF
    .word 0x0001F1AE, 0x07FF
    .word 0x0001F1B0, 0x07FF
    .word 0x0001F1B2, 0x07FF
    .word 0x0001F1B4, 0x07FF
    .word 0x0001F1B6, 0x07FF
    .word 0x0001F1B8, 0x07FF
    .word 0x0001F1BA, 0x07FF
    .word 0x0001F4BC, 0x07FF
    .word 0x0001F4BE, 0x07FF
    .word 0x0001F4C0, 0x07FF
    .word 0x0001F4C2, 0x07FF
    .word 0x0001F4C4, 0x07FF
    .word 0x0001F4C6, 0x07FF
    .word 0x0001F4C8, 0x07FF
    .word 0x0001F4CA, 0x07FF
    .word 0x0001F4D4, 0x07FF
    .word 0x0001F4D6, 0x07FF
    .word 0x0001F4D8, 0x07FF
    .word 0x0001F4DA, 0x07FF
    .word 0x0001F4DC, 0x07FF
    .word 0x0001F4DE, 0x07FF
    .word 0x0001F4E0, 0x07FF
    .word 0x0001F4E2, 0x07FF
    .word 0x0001F4EC, 0x07FF
    .word 0x0001F4EE, 0x07FF
    .word 0x0001F4F0, 0x07FF
    .word 0x0001F4F2, 0x07FF
    .word 0x0001F4F4, 0x07FF
    .word 0x0001F4F6, 0x07FF
    .word 0x0001F4F8, 0x07FF
    .word 0x0001F4FA, 0x07FF
    .word 0x0001F508, 0x07FF
    .word 0x0001F50A, 0x07FF
    .word 0x0001F50C, 0x07FF
    .word 0x0001F50E, 0x07FF
    .word 0x0001F510, 0x07FF
    .word 0x0001F512, 0x07FF
    .word 0x0001F520, 0x07FF
    .word 0x0001F522, 0x07FF
    .word 0x0001F524, 0x07FF
    .word 0x0001F526, 0x07FF
    .word 0x0001F528, 0x07FF
    .word 0x0001F52A, 0x07FF
    .word 0x0001F550, 0x07FF
    .word 0x0001F552, 0x07FF
    .word 0x0001F554, 0x07FF
    .word 0x0001F556, 0x07FF
    .word 0x0001F558, 0x07FF
    .word 0x0001F55A, 0x07FF
    .word 0x0001F564, 0x07FF
    .word 0x0001F566, 0x07FF
    .word 0x0001F568, 0x07FF
    .word 0x0001F56A, 0x07FF
    .word 0x0001F56C, 0x07FF
    .word 0x0001F56E, 0x07FF
    .word 0x0001F570, 0x07FF
    .word 0x0001F572, 0x07FF
    .word 0x0001F57C, 0x07FF
    .word 0x0001F57E, 0x07FF
    .word 0x0001F580, 0x07FF
    .word 0x0001F582, 0x07FF
    .word 0x0001F584, 0x07FF
    .word 0x0001F586, 0x07FF
    .word 0x0001F588, 0x07FF
    .word 0x0001F58A, 0x07FF
    .word 0x0001F58C, 0x07FF
    .word 0x0001F58E, 0x07FF
    .word 0x0001F594, 0x07FF
    .word 0x0001F596, 0x07FF
    .word 0x0001F5AC, 0x07FF
    .word 0x0001F5AE, 0x07FF
    .word 0x0001F5B0, 0x07FF
    .word 0x0001F5B2, 0x07FF
    .word 0x0001F5B4, 0x07FF
    .word 0x0001F5B6, 0x07FF
    .word 0x0001F5B8, 0x07FF
    .word 0x0001F5BA, 0x07FF
    .word 0x0001F8BC, 0x07FF
    .word 0x0001F8BE, 0x07FF
    .word 0x0001F8D4, 0x07FF
    .word 0x0001F8D6, 0x07FF
    .word 0x0001F8DC, 0x07FF
    .word 0x0001F8DE, 0x07FF
    .word 0x0001F8EC, 0x07FF
    .word 0x0001F8EE, 0x07FF
    .word 0x0001F914, 0x07FF
    .word 0x0001F916, 0x07FF
    .word 0x0001F92C, 0x07FF
    .word 0x0001F92E, 0x07FF
    .word 0x0001F95C, 0x07FF
    .word 0x0001F95E, 0x07FF
    .word 0x0001F964, 0x07FF
    .word 0x0001F966, 0x07FF
    .word 0x0001F97C, 0x07FF
    .word 0x0001F97E, 0x07FF
    .word 0x0001F98C, 0x07FF
    .word 0x0001F98E, 0x07FF
    .word 0x0001F994, 0x07FF
    .word 0x0001F996, 0x07FF
    .word 0x0001F9AC, 0x07FF
    .word 0x0001F9AE, 0x07FF
    .word 0x0001FCBC, 0x07FF
    .word 0x0001FCBE, 0x07FF
    .word 0x0001FCD4, 0x07FF
    .word 0x0001FCD6, 0x07FF
    .word 0x0001FCDC, 0x07FF
    .word 0x0001FCDE, 0x07FF
    .word 0x0001FCEC, 0x07FF
    .word 0x0001FCEE, 0x07FF
    .word 0x0001FD14, 0x07FF
    .word 0x0001FD16, 0x07FF
    .word 0x0001FD2C, 0x07FF
    .word 0x0001FD2E, 0x07FF
    .word 0x0001FD5C, 0x07FF
    .word 0x0001FD5E, 0x07FF
    .word 0x0001FD64, 0x07FF
    .word 0x0001FD66, 0x07FF
    .word 0x0001FD7C, 0x07FF
    .word 0x0001FD7E, 0x07FF
    .word 0x0001FD8C, 0x07FF
    .word 0x0001FD8E, 0x07FF
    .word 0x0001FD94, 0x07FF
    .word 0x0001FD96, 0x07FF
    .word 0x0001FDAC, 0x07FF
    .word 0x0001FDAE, 0x07FF
    .word 0x000200BC, 0x07FF
    .word 0x000200BE, 0x07FF
    .word 0x000200D4, 0x07FF
    .word 0x000200D6, 0x07FF
    .word 0x000200E0, 0x07FF
    .word 0x000200E2, 0x07FF
    .word 0x000200EC, 0x07FF
    .word 0x000200EE, 0x07FF
    .word 0x00020114, 0x07FF
    .word 0x00020116, 0x07FF
    .word 0x0002012C, 0x07FF
    .word 0x0002012E, 0x07FF
    .word 0x0002015C, 0x07FF
    .word 0x0002015E, 0x07FF
    .word 0x00020164, 0x07FF
    .word 0x00020166, 0x07FF
    .word 0x0002017C, 0x07FF
    .word 0x0002017E, 0x07FF
    .word 0x0002018C, 0x07FF
    .word 0x0002018E, 0x07FF
    .word 0x00020194, 0x07FF
    .word 0x00020196, 0x07FF
    .word 0x000201AC, 0x07FF
    .word 0x000201AE, 0x07FF
    .word 0x000204BC, 0x07FF
    .word 0x000204BE, 0x07FF
    .word 0x000204D4, 0x07FF
    .word 0x000204D6, 0x07FF
    .word 0x000204E0, 0x07FF
    .word 0x000204E2, 0x07FF
    .word 0x000204EC, 0x07FF
    .word 0x000204EE, 0x07FF
    .word 0x00020514, 0x07FF
    .word 0x00020516, 0x07FF
    .word 0x0002052C, 0x07FF
    .word 0x0002052E, 0x07FF
    .word 0x0002055C, 0x07FF
    .word 0x0002055E, 0x07FF
    .word 0x00020564, 0x07FF
    .word 0x00020566, 0x07FF
    .word 0x0002057C, 0x07FF
    .word 0x0002057E, 0x07FF
    .word 0x0002058C, 0x07FF
    .word 0x0002058E, 0x07FF
    .word 0x00020594, 0x07FF
    .word 0x00020596, 0x07FF
    .word 0x000205AC, 0x07FF
    .word 0x000205AE, 0x07FF
    .word 0x000208BC, 0x07FF
    .word 0x000208BE, 0x07FF
    .word 0x000208D4, 0x07FF
    .word 0x000208D6, 0x07FF
    .word 0x000208E4, 0x07FF
    .word 0x000208E6, 0x07FF
    .word 0x000208EC, 0x07FF
    .word 0x000208EE, 0x07FF
    .word 0x000208F0, 0x07FF
    .word 0x000208F2, 0x07FF
    .word 0x000208F4, 0x07FF
    .word 0x000208F6, 0x07FF
    .word 0x000208F8, 0x07FF
    .word 0x000208FA, 0x07FF
    .word 0x000208FC, 0x07FF
    .word 0x000208FE, 0x07FF
    .word 0x00020904, 0x07FF
    .word 0x00020906, 0x07FF
    .word 0x00020908, 0x07FF
    .word 0x0002090A, 0x07FF
    .word 0x0002090C, 0x07FF
    .word 0x0002090E, 0x07FF
    .word 0x00020910, 0x07FF
    .word 0x00020912, 0x07FF
    .word 0x0002091C, 0x07FF
    .word 0x0002091E, 0x07FF
    .word 0x00020920, 0x07FF
    .word 0x00020922, 0x07FF
    .word 0x00020924, 0x07FF
    .word 0x00020926, 0x07FF
    .word 0x00020928, 0x07FF
    .word 0x0002092A, 0x07FF
    .word 0x0002094C, 0x07FF
    .word 0x0002094E, 0x07FF
    .word 0x00020950, 0x07FF
    .word 0x00020952, 0x07FF
    .word 0x00020954, 0x07FF
    .word 0x00020956, 0x07FF
    .word 0x00020958, 0x07FF
    .word 0x0002095A, 0x07FF
    .word 0x00020964, 0x07FF
    .word 0x00020966, 0x07FF
    .word 0x0002097C, 0x07FF
    .word 0x0002097E, 0x07FF
    .word 0x0002098C, 0x07FF
    .word 0x0002098E, 0x07FF
    .word 0x00020998, 0x07FF
    .word 0x0002099A, 0x07FF
    .word 0x0002099C, 0x07FF
    .word 0x0002099E, 0x07FF
    .word 0x000209A0, 0x07FF
    .word 0x000209A2, 0x07FF
    .word 0x000209A4, 0x07FF
    .word 0x000209A6, 0x07FF
    .word 0x000209AC, 0x07FF
    .word 0x000209AE, 0x07FF
    .word 0x000209B0, 0x07FF
    .word 0x000209B2, 0x07FF
    .word 0x000209B4, 0x07FF
    .word 0x000209B6, 0x07FF
    .word 0x000209B8, 0x07FF
    .word 0x000209BA, 0x07FF
    .word 0x000209BC, 0x07FF
    .word 0x000209BE, 0x07FF
    .word 0x00020CBC, 0x07FF
    .word 0x00020CBE, 0x07FF
    .word 0x00020CD4, 0x07FF
    .word 0x00020CD6, 0x07FF
    .word 0x00020CE4, 0x07FF
    .word 0x00020CE6, 0x07FF
    .word 0x00020CEC, 0x07FF
    .word 0x00020CEE, 0x07FF
    .word 0x00020CF0, 0x07FF
    .word 0x00020CF2, 0x07FF
    .word 0x00020CF4, 0x07FF
    .word 0x00020CF6, 0x07FF
    .word 0x00020CF8, 0x07FF
    .word 0x00020CFA, 0x07FF
    .word 0x00020CFC, 0x07FF
    .word 0x00020CFE, 0x07FF
    .word 0x00020D04, 0x07FF
    .word 0x00020D06, 0x07FF
    .word 0x00020D08, 0x07FF
    .word 0x00020D0A, 0x07FF
    .word 0x00020D0C, 0x07FF
    .word 0x00020D0E, 0x07FF
    .word 0x00020D10, 0x07FF
    .word 0x00020D12, 0x07FF
    .word 0x00020D1C, 0x07FF
    .word 0x00020D1E, 0x07FF
    .word 0x00020D20, 0x07FF
    .word 0x00020D22, 0x07FF
    .word 0x00020D24, 0x07FF
    .word 0x00020D26, 0x07FF
    .word 0x00020D28, 0x07FF
    .word 0x00020D2A, 0x07FF
    .word 0x00020D4C, 0x07FF
    .word 0x00020D4E, 0x07FF
    .word 0x00020D50, 0x07FF
    .word 0x00020D52, 0x07FF
    .word 0x00020D54, 0x07FF
    .word 0x00020D56, 0x07FF
    .word 0x00020D58, 0x07FF
    .word 0x00020D5A, 0x07FF
    .word 0x00020D64, 0x07FF
    .word 0x00020D66, 0x07FF
    .word 0x00020D7C, 0x07FF
    .word 0x00020D7E, 0x07FF
    .word 0x00020D8C, 0x07FF
    .word 0x00020D8E, 0x07FF
    .word 0x00020D98, 0x07FF
    .word 0x00020D9A, 0x07FF
    .word 0x00020D9C, 0x07FF
    .word 0x00020D9E, 0x07FF
    .word 0x00020DA0, 0x07FF
    .word 0x00020DA2, 0x07FF
    .word 0x00020DA4, 0x07FF
    .word 0x00020DA6, 0x07FF
    .word 0x00020DAC, 0x07FF
    .word 0x00020DAE, 0x07FF
    .word 0x00020DB0, 0x07FF
    .word 0x00020DB2, 0x07FF
    .word 0x00020DB4, 0x07FF
    .word 0x00020DB6, 0x07FF
    .word 0x00020DB8, 0x07FF
    .word 0x00020DBA, 0x07FF
    .word 0x00020DBC, 0x07FF
    .word 0x00020DBE, 0x07FF
    .word 0x00026110, 0xFFFF
    .word 0x00026112, 0xFFFF
    .word 0x00026114, 0xFFFF
    .word 0x00026116, 0xFFFF
    .word 0x00026118, 0xFFFF
    .word 0x0002611E, 0xFFFF
    .word 0x00026120, 0xFFFF
    .word 0x00026122, 0xFFFF
    .word 0x00026136, 0xFFFF
    .word 0x00026138, 0xFFFF
    .word 0x0002613A, 0xFFFF
    .word 0x0002613C, 0xFFFF
    .word 0x00026140, 0xFFFF
    .word 0x00026142, 0xFFFF
    .word 0x00026144, 0xFFFF
    .word 0x00026146, 0xFFFF
    .word 0x00026148, 0xFFFF
    .word 0x0002614E, 0xFFFF
    .word 0x00026150, 0xFFFF
    .word 0x00026152, 0xFFFF
    .word 0x00026158, 0xFFFF
    .word 0x0002615A, 0xFFFF
    .word 0x0002615C, 0xFFFF
    .word 0x0002615E, 0xFFFF
    .word 0x00026164, 0xFFFF
    .word 0x00026166, 0xFFFF
    .word 0x00026168, 0xFFFF
    .word 0x0002616A, 0xFFFF
    .word 0x0002616C, 0xFFFF
    .word 0x00026514, 0xFFFF
    .word 0x0002651C, 0xFFFF
    .word 0x00026524, 0xFFFF
    .word 0x00026534, 0xFFFF
    .word 0x00026544, 0xFFFF
    .word 0x0002654C, 0xFFFF
    .word 0x00026554, 0xFFFF
    .word 0x00026558, 0xFFFF
    .word 0x00026560, 0xFFFF
    .word 0x00026568, 0xFFFF
    .word 0x00026914, 0xFFFF
    .word 0x0002691C, 0xFFFF
    .word 0x00026924, 0xFFFF
    .word 0x00026934, 0xFFFF
    .word 0x00026944, 0xFFFF
    .word 0x0002694C, 0xFFFF
    .word 0x00026954, 0xFFFF
    .word 0x00026958, 0xFFFF
    .word 0x00026960, 0xFFFF
    .word 0x00026968, 0xFFFF
    .word 0x00026D14, 0xFFFF
    .word 0x00026D1C, 0xFFFF
    .word 0x00026D24, 0xFFFF
    .word 0x00026D36, 0xFFFF
    .word 0x00026D38, 0xFFFF
    .word 0x00026D3A, 0xFFFF
    .word 0x00026D44, 0xFFFF
    .word 0x00026D4C, 0xFFFF
    .word 0x00026D4E, 0xFFFF
    .word 0x00026D50, 0xFFFF
    .word 0x00026D52, 0xFFFF
    .word 0x00026D54, 0xFFFF
    .word 0x00026D58, 0xFFFF
    .word 0x00026D5A, 0xFFFF
    .word 0x00026D5C, 0xFFFF
    .word 0x00026D5E, 0xFFFF
    .word 0x00026D68, 0xFFFF
    .word 0x00027114, 0xFFFF
    .word 0x0002711C, 0xFFFF
    .word 0x00027124, 0xFFFF
    .word 0x0002713C, 0xFFFF
    .word 0x00027144, 0xFFFF
    .word 0x0002714C, 0xFFFF
    .word 0x00027154, 0xFFFF
    .word 0x00027158, 0xFFFF
    .word 0x0002715C, 0xFFFF
    .word 0x00027168, 0xFFFF
    .word 0x00027514, 0xFFFF
    .word 0x0002751C, 0xFFFF
    .word 0x00027524, 0xFFFF
    .word 0x0002753C, 0xFFFF
    .word 0x00027544, 0xFFFF
    .word 0x0002754C, 0xFFFF
    .word 0x00027554, 0xFFFF
    .word 0x00027558, 0xFFFF
    .word 0x0002755E, 0xFFFF
    .word 0x00027568, 0xFFFF
    .word 0x00027914, 0xFFFF
    .word 0x0002791E, 0xFFFF
    .word 0x00027920, 0xFFFF
    .word 0x00027922, 0xFFFF
    .word 0x00027934, 0xFFFF
    .word 0x00027936, 0xFFFF
    .word 0x00027938, 0xFFFF
    .word 0x0002793A, 0xFFFF
    .word 0x00027944, 0xFFFF
    .word 0x0002794C, 0xFFFF
    .word 0x00027954, 0xFFFF
    .word 0x00027958, 0xFFFF
    .word 0x00027960, 0xFFFF
    .word 0x00027968, 0xFFFF
    .word 0x0002F0C2, 0x632F
    .word 0x0002F0CA, 0x632F
    .word 0x0002F0D0, 0x632F
    .word 0x0002F0D2, 0x632F
    .word 0x0002F0D4, 0x632F
    .word 0x0002F0DA, 0x632F
    .word 0x0002F0DC, 0x632F
    .word 0x0002F0DE, 0x632F
    .word 0x0002F0E0, 0x632F
    .word 0x0002F0E6, 0x632F
    .word 0x0002F0E8, 0x632F
    .word 0x0002F0EA, 0x632F
    .word 0x0002F0EC, 0x632F
    .word 0x0002F0FE, 0x632F
    .word 0x0002F100, 0x632F
    .word 0x0002F102, 0x632F
    .word 0x0002F104, 0x632F
    .word 0x0002F106, 0x632F
    .word 0x0002F10A, 0x632F
    .word 0x0002F116, 0x632F
    .word 0x0002F118, 0x632F
    .word 0x0002F11A, 0x632F
    .word 0x0002F11C, 0x632F
    .word 0x0002F11E, 0x632F
    .word 0x0002F124, 0x632F
    .word 0x0002F126, 0x632F
    .word 0x0002F128, 0x632F
    .word 0x0002F12A, 0x632F
    .word 0x0002F12E, 0x632F
    .word 0x0002F136, 0x632F
    .word 0x0002F13A, 0x632F
    .word 0x0002F13C, 0x632F
    .word 0x0002F13E, 0x632F
    .word 0x0002F140, 0x632F
    .word 0x0002F142, 0x632F
    .word 0x0002F154, 0x632F
    .word 0x0002F156, 0x632F
    .word 0x0002F158, 0x632F
    .word 0x0002F15A, 0x632F
    .word 0x0002F15E, 0x632F
    .word 0x0002F160, 0x632F
    .word 0x0002F162, 0x632F
    .word 0x0002F164, 0x632F
    .word 0x0002F166, 0x632F
    .word 0x0002F16A, 0x632F
    .word 0x0002F172, 0x632F
    .word 0x0002F176, 0x632F
    .word 0x0002F17E, 0x632F
    .word 0x0002F182, 0x632F
    .word 0x0002F190, 0x632F
    .word 0x0002F192, 0x632F
    .word 0x0002F194, 0x632F
    .word 0x0002F19A, 0x632F
    .word 0x0002F19C, 0x632F
    .word 0x0002F19E, 0x632F
    .word 0x0002F1A0, 0x632F
    .word 0x0002F1A2, 0x632F
    .word 0x0002F1A8, 0x632F
    .word 0x0002F1AA, 0x632F
    .word 0x0002F1AC, 0x632F
    .word 0x0002F1B2, 0x632F
    .word 0x0002F1B4, 0x632F
    .word 0x0002F1B6, 0x632F
    .word 0x0002F1B8, 0x632F
    .word 0x0002F4C2, 0x632F
    .word 0x0002F4CA, 0x632F
    .word 0x0002F4CE, 0x632F
    .word 0x0002F4D6, 0x632F
    .word 0x0002F4DA, 0x632F
    .word 0x0002F4E2, 0x632F
    .word 0x0002F4E6, 0x632F
    .word 0x0002F4EE, 0x632F
    .word 0x0002F4FE, 0x632F
    .word 0x0002F50A, 0x632F
    .word 0x0002F51A, 0x632F
    .word 0x0002F522, 0x632F
    .word 0x0002F52E, 0x632F
    .word 0x0002F536, 0x632F
    .word 0x0002F53E, 0x632F
    .word 0x0002F552, 0x632F
    .word 0x0002F562, 0x632F
    .word 0x0002F56A, 0x632F
    .word 0x0002F56C, 0x632F
    .word 0x0002F570, 0x632F
    .word 0x0002F572, 0x632F
    .word 0x0002F576, 0x632F
    .word 0x0002F57E, 0x632F
    .word 0x0002F582, 0x632F
    .word 0x0002F58E, 0x632F
    .word 0x0002F596, 0x632F
    .word 0x0002F59E, 0x632F
    .word 0x0002F5A6, 0x632F
    .word 0x0002F5AE, 0x632F
    .word 0x0002F5B2, 0x632F
    .word 0x0002F5BA, 0x632F
    .word 0x0002F8C2, 0x632F
    .word 0x0002F8CA, 0x632F
    .word 0x0002F8CE, 0x632F
    .word 0x0002F8D6, 0x632F
    .word 0x0002F8DA, 0x632F
    .word 0x0002F8E2, 0x632F
    .word 0x0002F8E6, 0x632F
    .word 0x0002F8EE, 0x632F
    .word 0x0002F8FE, 0x632F
    .word 0x0002F90A, 0x632F
    .word 0x0002F91A, 0x632F
    .word 0x0002F922, 0x632F
    .word 0x0002F92E, 0x632F
    .word 0x0002F936, 0x632F
    .word 0x0002F93E, 0x632F
    .word 0x0002F952, 0x632F
    .word 0x0002F962, 0x632F
    .word 0x0002F96A, 0x632F
    .word 0x0002F96E, 0x632F
    .word 0x0002F972, 0x632F
    .word 0x0002F976, 0x632F
    .word 0x0002F97E, 0x632F
    .word 0x0002F982, 0x632F
    .word 0x0002F98E, 0x632F
    .word 0x0002F996, 0x632F
    .word 0x0002F99E, 0x632F
    .word 0x0002F9A6, 0x632F
    .word 0x0002F9AE, 0x632F
    .word 0x0002F9B2, 0x632F
    .word 0x0002F9BA, 0x632F
    .word 0x0002FCC2, 0x632F
    .word 0x0002FCC6, 0x632F
    .word 0x0002FCCA, 0x632F
    .word 0x0002FCCE, 0x632F
    .word 0x0002FCD0, 0x632F
    .word 0x0002FCD2, 0x632F
    .word 0x0002FCD4, 0x632F
    .word 0x0002FCD6, 0x632F
    .word 0x0002FCDA, 0x632F
    .word 0x0002FCDC, 0x632F
    .word 0x0002FCDE, 0x632F
    .word 0x0002FCE0, 0x632F
    .word 0x0002FCE6, 0x632F
    .word 0x0002FCE8, 0x632F
    .word 0x0002FCEA, 0x632F
    .word 0x0002FCEC, 0x632F
    .word 0x0002FCFE, 0x632F
    .word 0x0002FD00, 0x632F
    .word 0x0002FD02, 0x632F
    .word 0x0002FD04, 0x632F
    .word 0x0002FD0A, 0x632F
    .word 0x0002FD1A, 0x632F
    .word 0x0002FD22, 0x632F
    .word 0x0002FD26, 0x632F
    .word 0x0002FD28, 0x632F
    .word 0x0002FD2A, 0x632F
    .word 0x0002FD2E, 0x632F
    .word 0x0002FD30, 0x632F
    .word 0x0002FD32, 0x632F
    .word 0x0002FD34, 0x632F
    .word 0x0002FD36, 0x632F
    .word 0x0002FD3E, 0x632F
    .word 0x0002FD54, 0x632F
    .word 0x0002FD56, 0x632F
    .word 0x0002FD58, 0x632F
    .word 0x0002FD62, 0x632F
    .word 0x0002FD6A, 0x632F
    .word 0x0002FD72, 0x632F
    .word 0x0002FD76, 0x632F
    .word 0x0002FD7E, 0x632F
    .word 0x0002FD82, 0x632F
    .word 0x0002FD8E, 0x632F
    .word 0x0002FD90, 0x632F
    .word 0x0002FD92, 0x632F
    .word 0x0002FD94, 0x632F
    .word 0x0002FD96, 0x632F
    .word 0x0002FD9E, 0x632F
    .word 0x0002FDA6, 0x632F
    .word 0x0002FDAE, 0x632F
    .word 0x0002FDB2, 0x632F
    .word 0x0002FDB4, 0x632F
    .word 0x0002FDB6, 0x632F
    .word 0x0002FDB8, 0x632F
    .word 0x000300C2, 0x632F
    .word 0x000300C6, 0x632F
    .word 0x000300CA, 0x632F
    .word 0x000300CE, 0x632F
    .word 0x000300D6, 0x632F
    .word 0x000300DA, 0x632F
    .word 0x000300DE, 0x632F
    .word 0x000300E6, 0x632F
    .word 0x000300FE, 0x632F
    .word 0x0003010A, 0x632F
    .word 0x0003011A, 0x632F
    .word 0x00030122, 0x632F
    .word 0x0003012A, 0x632F
    .word 0x0003012E, 0x632F
    .word 0x00030136, 0x632F
    .word 0x0003013E, 0x632F
    .word 0x0003015A, 0x632F
    .word 0x00030162, 0x632F
    .word 0x0003016A, 0x632F
    .word 0x00030172, 0x632F
    .word 0x00030176, 0x632F
    .word 0x0003017E, 0x632F
    .word 0x00030182, 0x632F
    .word 0x0003018E, 0x632F
    .word 0x00030196, 0x632F
    .word 0x0003019E, 0x632F
    .word 0x000301A6, 0x632F
    .word 0x000301AE, 0x632F
    .word 0x000301B2, 0x632F
    .word 0x000301B6, 0x632F
    .word 0x000304C2, 0x632F
    .word 0x000304C4, 0x632F
    .word 0x000304C8, 0x632F
    .word 0x000304CA, 0x632F
    .word 0x000304CE, 0x632F
    .word 0x000304D6, 0x632F
    .word 0x000304DA, 0x632F
    .word 0x000304E0, 0x632F
    .word 0x000304E6, 0x632F
    .word 0x000304FE, 0x632F
    .word 0x0003050A, 0x632F
    .word 0x0003051A, 0x632F
    .word 0x00030522, 0x632F
    .word 0x0003052A, 0x632F
    .word 0x0003052E, 0x632F
    .word 0x00030536, 0x632F
    .word 0x0003053E, 0x632F
    .word 0x0003055A, 0x632F
    .word 0x00030562, 0x632F
    .word 0x0003056A, 0x632F
    .word 0x00030572, 0x632F
    .word 0x00030576, 0x632F
    .word 0x0003057E, 0x632F
    .word 0x00030582, 0x632F
    .word 0x0003058E, 0x632F
    .word 0x00030596, 0x632F
    .word 0x0003059E, 0x632F
    .word 0x000305A6, 0x632F
    .word 0x000305AE, 0x632F
    .word 0x000305B2, 0x632F
    .word 0x000305B8, 0x632F
    .word 0x000308C2, 0x632F
    .word 0x000308CA, 0x632F
    .word 0x000308CE, 0x632F
    .word 0x000308D6, 0x632F
    .word 0x000308DA, 0x632F
    .word 0x000308E2, 0x632F
    .word 0x000308E6, 0x632F
    .word 0x000308FE, 0x632F
    .word 0x0003090A, 0x632F
    .word 0x0003090C, 0x632F
    .word 0x0003090E, 0x632F
    .word 0x00030910, 0x632F
    .word 0x00030912, 0x632F
    .word 0x00030916, 0x632F
    .word 0x00030918, 0x632F
    .word 0x0003091A, 0x632F
    .word 0x0003091C, 0x632F
    .word 0x0003091E, 0x632F
    .word 0x00030924, 0x632F
    .word 0x00030926, 0x632F
    .word 0x00030928, 0x632F
    .word 0x0003092A, 0x632F
    .word 0x0003092E, 0x632F
    .word 0x00030936, 0x632F
    .word 0x0003093E, 0x632F
    .word 0x00030952, 0x632F
    .word 0x00030954, 0x632F
    .word 0x00030956, 0x632F
    .word 0x00030958, 0x632F
    .word 0x0003095E, 0x632F
    .word 0x00030960, 0x632F
    .word 0x00030962, 0x632F
    .word 0x00030964, 0x632F
    .word 0x00030966, 0x632F
    .word 0x0003096A, 0x632F
    .word 0x00030972, 0x632F
    .word 0x00030978, 0x632F
    .word 0x0003097A, 0x632F
    .word 0x0003097C, 0x632F
    .word 0x00030982, 0x632F
    .word 0x00030984, 0x632F
    .word 0x00030986, 0x632F
    .word 0x00030988, 0x632F
    .word 0x0003098A, 0x632F
    .word 0x0003098E, 0x632F
    .word 0x00030996, 0x632F
    .word 0x0003099E, 0x632F
    .word 0x000309A8, 0x632F
    .word 0x000309AA, 0x632F
    .word 0x000309AC, 0x632F
    .word 0x000309B2, 0x632F
    .word 0x000309BA, 0x632F
    .word 0x00036C24, 0xFFF2
    .word 0x00036E5A, 0xFFF2
    .word 0x00037420, 0xFFF2
    .word 0x00037424, 0xFFF2
    .word 0x00037428, 0xFFF2
    .word 0x00037656, 0xFFF2
    .word 0x0003765A, 0xFFF2
    .word 0x0003765E, 0xFFF2
    .word 0x00037C24, 0xFFF2
    .word 0x00037E5A, 0xFFF2
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