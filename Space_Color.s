@ ============================================================
@ fondo_espacial_v4.s
@ Fondo espacial con estrellas - VGA Pixel Buffer
@ ARMv7 - DE1-SoC / CPUlator
@
@ CLAVE: CPUlator usa stride = 1024 bytes por fila (y << 10)
@        aunque la pantalla visible sea 320x240.
@        Buffer total = 512 * 256 * 2 = 262144 bytes = 131072 hwords
@        Offset de pixel (x,y) = (y << 10) + (x << 1)
@ ============================================================

.equ FB_BASE,  0xC8000000

@ Colores RGB565
.equ C_BLACK,  0x0000
.equ C_WHITE,  0xFFFF
.equ C_BLUE_P, 0x9CF3
.equ C_YELLOW, 0xFFE0
.equ C_GRAY,   0x4208

@ ============================================================
.text
.global _start

_start:

@ ----------------------------------------------------------
@ PASO 1: Limpiar TODO el buffer a negro
@   131072 halfwords (igual que el código de referencia)
@   stride real = 1024 bytes = 512 píxeles por fila
@ ----------------------------------------------------------
    LDR  R4, =FB_BASE
    MOV  R5, #0
    LDR  R6, =131072

CLEAR_LOOP:
    SUBS R6, R6, #1
    BMI  CLEAR_DONE
    STRH R5, [R4], #2
    B    CLEAR_LOOP

CLEAR_DONE:

@ ----------------------------------------------------------
@ PASO 2: Estrellas blancas (1 px)
@ offset = (y << 10) + (x << 1)
@ ----------------------------------------------------------
    LDR  R6, =FB_BASE
    LDR  R7, =stars_white
    LDR  R8, =stars_white_end
    MOV  R5, #C_WHITE

swhite:
    CMP  R7, R8
    BGE  sblue
    LDR  R4, [R7], #4
    ADD  R3, R4, R6
    STRH R5, [R3]
    B    swhite

@ ----------------------------------------------------------
@ PASO 2b: Estrellas azul pálido
@ ----------------------------------------------------------
sblue:
    LDR  R7, =stars_blue
    LDR  R8, =stars_blue_end
    LDR  R5, val_blue

sblue_loop:
    CMP  R7, R8
    BGE  syellow
    LDR  R4, [R7], #4
    ADD  R3, R4, R6
    STRH R5, [R3]
    B    sblue_loop

@ ----------------------------------------------------------
@ PASO 2c: Estrellas amarillas
@ ----------------------------------------------------------
syellow:
    LDR  R7, =stars_yellow
    LDR  R8, =stars_yellow_end
    LDR  R5, val_yellow

syellow_loop:
    CMP  R7, R8
    BGE  smed
    LDR  R4, [R7], #4
    ADD  R3, R4, R6
    STRH R5, [R3]
    B    syellow_loop

@ ----------------------------------------------------------
@ PASO 3: Estrellas medianas (cruz 5px)
@ STRIDE = 1024 bytes cargado en R11
@ ----------------------------------------------------------
smed:
    LDR  R7,  =stars_med
    LDR  R8,  =stars_med_end
    LDR  R11, val_stride       @ R11 = 1024

smed_loop:
    CMP  R7, R8
    BGE  slarge

    LDR  R4, [R7], #4          @ offset centro
    LDR  R9, [R7], #4          @ color centro

    ADD  R3, R4, R6
    STRH R9, [R3]              @ centro

    MOV  R5, #C_GRAY

    SUB  R3, R4, #2            @ izquierda (x-1)
    ADD  R3, R3, R6
    STRH R5, [R3]

    ADD  R3, R4, #2            @ derecha (x+1)
    ADD  R3, R3, R6
    STRH R5, [R3]

    SUB  R3, R4, R11           @ arriba (y-1): offset - 1024
    ADD  R3, R3, R6
    STRH R5, [R3]

    ADD  R3, R4, R11           @ abajo (y+1): offset + 1024
    ADD  R3, R3, R6
    STRH R5, [R3]

    B    smed_loop

@ ----------------------------------------------------------
@ PASO 4: Estrellas grandes (cruz 9px)
@ ----------------------------------------------------------
slarge:
    LDR  R7,  =stars_large
    LDR  R8,  =stars_large_end
    LDR  R11, val_stride       @ 1024
    LSL  R12, R11, #1          @ 2048 = stride*2
    MOV  R5,  #C_WHITE
    MOV  R10, #C_GRAY

slarge_loop:
    CMP  R7, R8
    BGE  done

    LDR  R4, [R7], #4

    @ Centro: blanco
    ADD  R3, R4, R6            ; STRH R5, [R3]

    @ Brazos distancia 1: blanco
    SUB  R3, R4, #2    ; ADD R3, R3, R6 ; STRH R5, [R3]
    ADD  R3, R4, #2    ; ADD R3, R3, R6 ; STRH R5, [R3]
    SUB  R3, R4, R11   ; ADD R3, R3, R6 ; STRH R5, [R3]
    ADD  R3, R4, R11   ; ADD R3, R3, R6 ; STRH R5, [R3]

    @ Brazos distancia 2: gris
    SUB  R3, R4, #4    ; ADD R3, R3, R6 ; STRH R10, [R3]
    ADD  R3, R4, #4    ; ADD R3, R3, R6 ; STRH R10, [R3]
    SUB  R3, R4, R12   ; ADD R3, R3, R6 ; STRH R10, [R3]
    ADD  R3, R4, R12   ; ADD R3, R3, R6 ; STRH R10, [R3]

    B    slarge_loop

done:
    B    done

@ ============================================================
@ Literales de 32 bits
@ ============================================================
val_stride: .word 1024
val_blue:   .word C_BLUE_P
val_yellow: .word C_YELLOW

@ ============================================================
@ TABLAS DE OFFSETS
@ Formula correcta: offset = (y << 10) + (x << 1)
@                           = y*1024   + x*2
@ Pantalla visible: x en [0..319], y en [0..239]
@ ============================================================
.data
.align 2

@ --- 51 estrellas blancas en toda la pantalla ---------------
stars_white:
    @ Franja superior y=3..48
    .word  (3<<10)  + (12 <<1)
    .word  (3<<10)  + (288<<1)
    .word  (7<<10)  + (55 <<1)
    .word  (7<<10)  + (155<<1)
    .word  (7<<10)  + (255<<1)
    .word  (12<<10) + (90 <<1)
    .word  (12<<10) + (200<<1)
    .word  (12<<10) + (312<<1)
    .word  (17<<10) + (35 <<1)
    .word  (17<<10) + (175<<1)
    .word  (22<<10) + (275<<1)
    .word  (28<<10) + (68 <<1)
    .word  (28<<10) + (195<<1)
    .word  (33<<10) + (310<<1)
    .word  (38<<10) + (22 <<1)
    .word  (38<<10) + (138<<1)
    .word  (43<<10) + (248<<1)
    .word  (48<<10) + (78 <<1)
    @ Franja media-alta y=55..110
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
    @ Franja media y=115..170
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
    @ Franja baja y=175..238
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

@ --- Estrellas azul pálido ----------------------------------
stars_blue:
    .word  (5 <<10) + (168<<1)
    .word  (14<<10) + (308<<1)
    .word  (25<<10) + (228<<1)
    .word  (37<<10) + (108<<1)
    .word  (50<<10) + (282<<1)
    .word  (62<<10) + (42 <<1)
    .word  (74<<10) + (205<<1)
    .word  (86<<10) + (128<<1)
    .word  (98<<10) + (318<<1)
    .word  (110<<10)+ (18 <<1)
    .word  (122<<10)+ (258<<1)
    .word  (135<<10)+ (88 <<1)
    .word  (148<<10)+ (308<<1)
    .word  (160<<10)+ (148<<1)
    .word  (172<<10)+ (22 <<1)
    .word  (184<<10)+ (202<<1)
    .word  (196<<10)+ (68 <<1)
    .word  (208<<10)+ (248<<1)
    .word  (220<<10)+ (118<<1)
    .word  (232<<10)+ (38 <<1)
stars_blue_end:

@ --- Estrellas amarillas ------------------------------------
stars_yellow:
    .word  (10<<10) + (42 <<1)
    .word  (32<<10) + (268<<1)
    .word  (58<<10) + (155<<1)
    .word  (82<<10) + (62 <<1)
    .word  (105<<10)+ (188<<1)
    .word  (128<<10)+ (32 <<1)
    .word  (152<<10)+ (252<<1)
    .word  (175<<10)+ (112<<1)
    .word  (198<<10)+ (298<<1)
    .word  (220<<10)+ (78 <<1)
stars_yellow_end:

@ --- Estrellas medianas: pares (offset, color) --------------
stars_med:
    .word (22 <<10)+(148<<1), 0x0000FFFF   @ blanco  (148,22)
    .word (50 <<10)+(35 <<1), 0x0000FFE0   @ amarillo( 35,50)
    .word (78 <<10)+(295<<1), 0x0000FFFF   @ blanco  (295,78)
    .word (105<<10)+(82 <<1), 0x0000FFE0   @ amarillo( 82,105)
    .word (132<<10)+(218<<1), 0x0000FFFF   @ blanco  (218,132)
    .word (158<<10)+(52 <<1), 0x0000FFE0   @ amarillo( 52,158)
    .word (185<<10)+(272<<1), 0x0000FFFF   @ blanco  (272,185)
    .word (212<<10)+(138<<1), 0x0000FFE0   @ amarillo(138,212)
    .word (238<<10)+(305<<1), 0x0000FFFF   @ blanco  (305,238) 
stars_med_end:

@ --- Estrellas grandes: offset del centro -------------------
stars_large:
    .word (15 <<10)+(245<<1)   @ (245, 15)
    .word (58 <<10)+(98 <<1)   @  (98, 58)
    .word (105<<10)+(298<<1)   @ (298,105)
    .word (152<<10)+(48 <<1)   @  (48,152)
    .word (195<<10)+(198<<1)   @ (198,195)
    .word (230<<10)+(82 <<1)   @  (82,230)
    .word (68 <<10)+(175<<1)   @ (175, 68)
stars_large_end:

.end