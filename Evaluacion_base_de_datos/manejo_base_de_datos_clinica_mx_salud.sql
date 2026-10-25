SET SERVEROUTPUT ON;

BEGIN
    BEGIN
        EXECUTE IMMEDIATE 'DROP SEQUENCE sq_error';
    EXCEPTION
        WHEN OTHERS THEN
            IF sqlcode != -2289 THEN
                RAISE;
            END IF;
    END;

    EXECUTE IMMEDIATE '
        CREATE SEQUENCE sq_error
        START WITH 1
        INCREMENT BY 1
        NOCACHE
    ';
END;
/

-- VARIABLES BIND
VAR b_fecha_proceso VARCHAR2(6);
EXEC :b_fecha_proceso := '202510';

VAR b_porc_multa NUMBER;
EXEC :b_porc_multa := 0.10;

-- BLOQUE PRINCIPAL
DECLARE

    ----- CURSOR SIN PARAMETROS
    CURSOR cur_medico IS
    SELECT
        med.med_run     run_med,
        med.pnombre
        || ' '
        || nvl(med.snombre || ' ', '')
        || med.apaterno
        || ' '
        || med.amaterno nombre,
        med.esp_id      id_especialiodad,
        med.car_id      id_cargo,
        med.uni_id      id_unidad
    FROM
        medico med
    ORDER BY
        med.med_run;

    ----- CURSOR CON PARAMETROS
    CURSOR cur_atencion (
        p_med_run NUMBER
    ) IS
    SELECT
        atencion.ate_id,
        atencion.fecha_atencion fecha_ate,
        atencion.hr_atencion    hora,
        atencion.costo,
        atencion.med_run,
        atencion.pac_run,
        paciente.dv_run         pac_dv_run,
        paciente.pnombre
        || ' '
        || nvl(paciente.snombre || ' ', '')
        || paciente.apaterno
        || ' '
        || paciente.amaterno    nombre_paciente,
        paciente.fecha_nacimiento,
        paciente.sal_id
    FROM
             atencion atencion
        JOIN paciente paciente ON ( atencion.pac_run = paciente.pac_run )
    WHERE
        med_run = p_med_run;

    ----- VARRAY
    TYPE tipo_varray_porcentaje IS
        VARRAY(5) OF NUMBER(3, 2);
    varray_descto              tipo_varray_porcentaje;

    ---- ESCALARES
    v_tot_ambul                NUMBER(5);
    v_tot_urgen                NUMBER(5);
    v_tot_pacritico            NUMBER(5);
    v_tot_adulto               NUMBER(5);
    v_tot_infantil             NUMBER(5);
    v_tot_maternidad           NUMBER(5);
    v_tot_cirugia              NUMBER(5);
    v_tot_cirugia_plast        NUMBER(5);
    v_tot_sobrep_obes          NUMBER(5);
    v_copago_base              NUMBER(10);
    v_porc_copago              NUMBER(5, 2);
    v_edad_paciente            NUMBER(3);
    v_porc_descto_edad         NUMBER(4, 2);
    v_descto_3ra_edad          NUMBER(10);
    v_porc_recargo_ffaa        NUMBER(3, 2);
    v_recargo_ffaa             NUMBER(10);
    v_valor_a_pagar            NUMBER(10);
    v_fec_venc_pago            DATE;
    v_fec_pago_real            DATE;
    v_valor_pagado_real        NUMBER(10);
    v_dias_atraso              NUMBER(4);
    v_monto_multa              NUMBER(10);
    v_diferencia               NUMBER(10);
    v_msg_error                VARCHAR2(250);
    v_nombre_unidad            VARCHAR2(25);
    v_nombre_especialidad      VARCHAR2(100);
    v_sitema_salud             VARCHAR2(100);
    v_decripcion_sistema_salud VARCHAR2(100);
    v_cargo_medico             VARCHAR2(100);
    v_tipo_sal_id              VARCHAR2(3);
    v_mes_anno                 VARCHAR2(7);

    ---- EXCEPCIONES
    costo_invalido EXCEPTION;
    paciente_sin_salud EXCEPTION;

----- COMIENZA EL BLOQUE
BEGIN
    EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_ATENMEDICAS_MENSUALES';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_ATENMEDICAS_MENSUALES';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE PAGO_MOROSO';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE ERRORES_PROCESO';

    ---- REINICIAR LA SECUENCIA DEL CORRELATIVO DE ERRORES
    

    ---- ASIGNAR VALORES AL VARRAY
    varray_descto := tipo_varray_porcentaje(0.05, 0.09, 0.12, 0.15, 0.18);

    ---- FORMATO DEL MES DE PROCESO MM/AAAA
    v_mes_anno := substr(:b_fecha_proceso, 5, 2)
                  || '/'
                  || substr(:b_fecha_proceso, 1, 4);

    ---- VARIABLES TOTALIZADORAS
    v_tot_ambul := 0;
    v_tot_urgen := 0;
    v_tot_pacritico := 0;
    v_tot_adulto := 0;
    v_tot_infantil := 0;
    v_tot_maternidad := 0;
    v_tot_cirugia := 0;
    v_tot_cirugia_plast := 0;
    v_tot_sobrep_obes := 0;

    ---- PRIMER LOOP CURSOR SIN PARAMETROS
    FOR reg_medico IN cur_medico LOOP

        ---- SEGUNDO LOOP CURSOR CON PARAMETROS
        FOR reg_atencion IN cur_atencion(reg_medico.run_med) LOOP
            IF to_char(reg_atencion.fecha_ate, 'YYYYMM') = :b_fecha_proceso THEN

                -- Obtencion unidad atencion
                SELECT
                    uni.nombre
                INTO v_nombre_unidad
                FROM
                         unidad uni
                    JOIN medico med ON ( uni.uni_id = med.uni_id )
                WHERE
                    med.med_run = reg_medico.run_med;

                -- Obtencion especialidad atencion
                SELECT
                    espe.nombre
                INTO v_nombre_especialidad
                FROM
                         especialidad espe
                    JOIN medico med ON ( espe.esp_id = med.esp_id )
                WHERE
                    med.med_run = reg_medico.run_med;

                -- Obtencion cargo medico
                SELECT
                    car.nombre
                INTO v_cargo_medico
                FROM
                         cargo car
                    JOIN medico med ON ( car.car_id = med.car_id )
                WHERE
                    med.med_run = reg_medico.run_med;

                -- Obtencion sistema salud
                SELECT
                    ti_sal.descripcion,
                    ti_sal.tipo_sal_id
                INTO
                    v_sitema_salud,
                    v_tipo_sal_id
                FROM
                         tipo_salud ti_sal
                    JOIN salud sal ON ( ti_sal.tipo_sal_id = sal.tipo_sal_id )
                WHERE
                    sal.sal_id = reg_atencion.sal_id;

                -- Obtencion descripcion sistema salud y porcentaje de copago
                SELECT
                    sal.descripcion,
                    sal.costo_pago / 100
                INTO
                    v_decripcion_sistema_salud,
                    v_porc_copago
                FROM
                    salud sal
                WHERE
                    sal.sal_id = reg_atencion.sal_id;

                -- Obtencion datos del pago
                BEGIN
                    SELECT
                        pag_ate.valor_a_pagar,
                        pag_ate.fecha_venc_pago,
                        pag_ate.fecha_pago
                    INTO
                        v_valor_pagado_real,
                        v_fec_venc_pago,
                        v_fec_pago_real
                    FROM
                        pago_atencion pag_ate
                    WHERE
                        pag_ate.ate_id = reg_atencion.ate_id;

                EXCEPTION
                    WHEN OTHERS THEN
                        v_valor_pagado_real := 0;
                        v_fec_venc_pago := NULL;
                        v_fec_pago_real := NULL;
                END;

                ----- VALIDACIONES CON EXCEPCIONES DE USUARIO
                BEGIN
                    IF reg_atencion.costo <= 0 THEN
                        RAISE costo_invalido;
                    END IF;
                    IF reg_atencion.sal_id IS NULL THEN
                        RAISE paciente_sin_salud;
                    END IF;
                EXCEPTION
                    WHEN costo_invalido THEN
                        INSERT INTO errores_proceso VALUES ( sq_error.NEXTVAL,
                                                             'Atencion ID: ' || reg_atencion.ate_id,
                                                             'La atencion registra un costo menor o igual a cero' );

                    WHEN paciente_sin_salud THEN
                        INSERT INTO errores_proceso VALUES ( sq_error.NEXTVAL,
                                                             'Paciente RUN: ' || reg_atencion.pac_run,
                                                             'El paciente no tiene sistema de salud asociado' );

                END;

                ----- CALCULO DEL COPAGO BASE
                v_copago_base := round(reg_atencion.costo * nvl(v_porc_copago, 0));

                ----- CALCULO DEL DESCUENTO POR TERCERA EDAD
                v_edad_paciente := trunc(months_between(reg_atencion.fecha_ate, reg_atencion.fecha_nacimiento) / 12);

                IF v_edad_paciente BETWEEN 60 AND 65 THEN
                    v_porc_descto_edad := varray_descto(1);
                ELSIF v_edad_paciente BETWEEN 66 AND 70 THEN
                    v_porc_descto_edad := varray_descto(2);
                ELSIF v_edad_paciente BETWEEN 71 AND 76 THEN
                    v_porc_descto_edad := varray_descto(3);
                ELSIF v_edad_paciente BETWEEN 77 AND 85 THEN
                    v_porc_descto_edad := varray_descto(4);
                ELSIF v_edad_paciente >= 86 THEN
                    v_porc_descto_edad := varray_descto(5);
                ELSE
                    v_porc_descto_edad := 0;
                END IF;

                v_descto_3ra_edad := round(v_copago_base * v_porc_descto_edad);

                ----- CALCULO DEL RECARGO FUERZAS ARMADAS
                v_recargo_ffaa := 0;
                IF v_tipo_sal_id = 'FA' THEN
                    BEGIN
                        SELECT
                            porc_recargo
                        INTO v_porc_recargo_ffaa
                        FROM
                            recargo_atencion_ffaa
                        WHERE
                            anno_recargo = TO_NUMBER(substr(:b_fecha_proceso, 1, 4));

                        v_recargo_ffaa := round(v_copago_base * v_porc_recargo_ffaa);
                    EXCEPTION
                        WHEN OTHERS THEN
                            v_msg_error := sqlerrm;
                            INSERT INTO errores_proceso VALUES ( sq_error.NEXTVAL,
                                                                 'Error al obtener recargo FFAA del anio: '
                                                                 || substr(:b_fecha_proceso, 1, 4),
                                                                 v_msg_error );

                    END;
                END IF;

                ----- CALCULO FINAL DEL VALOR A PAGAR
                v_valor_a_pagar := v_copago_base - v_descto_3ra_edad + v_recargo_ffaa;

                ----- DIFERENCIA CONTRA LO REGISTRADO EN PAGO_ATENCION
                v_diferencia := v_valor_a_pagar - nvl(v_valor_pagado_real, 0);

                ----- INSERTAR DATOS EN TABLA DETALLE
                INSERT INTO detalle_atenmedicas_mensuales VALUES ( v_mes_anno,
                                                                   reg_atencion.ate_id,
                                                                   reg_atencion.fecha_ate,
                                                                   reg_atencion.hora,
                                                                   v_nombre_unidad,
                                                                   v_nombre_especialidad,
                                                                   reg_medico.nombre,
                                                                   v_cargo_medico,
                                                                   reg_atencion.nombre_paciente,
                                                                   v_sitema_salud,
                                                                   v_decripcion_sistema_salud,
                                                                   reg_atencion.costo,
                                                                   v_valor_a_pagar,
                                                                   v_valor_pagado_real,
                                                                   v_diferencia );

                COMMIT;

                ----- CONTROL DE PAGOS MOROSOS
                IF
                    v_fec_pago_real IS NOT NULL
                    AND v_fec_venc_pago IS NOT NULL
                    AND v_fec_pago_real > v_fec_venc_pago
                THEN
                    v_dias_atraso := trunc(v_fec_pago_real - v_fec_venc_pago);
                    v_monto_multa := round(v_valor_a_pagar * :b_porc_multa);
                    INSERT INTO pago_moroso VALUES ( reg_atencion.pac_run,
                                                     reg_atencion.pac_dv_run,
                                                     substr(reg_atencion.nombre_paciente, 1, 50),
                                                     reg_atencion.ate_id,
                                                     v_fec_venc_pago,
                                                     v_fec_pago_real,
                                                     v_dias_atraso,
                                                     substr(v_nombre_especialidad, 1, 30),
                                                     reg_atencion.costo,
                                                     v_monto_multa,
                                                     'Pago fuera de plazo' );

                    COMMIT;
                END IF;

                ------- CALCULO DE LAS TOTALIZADORAS
                IF reg_medico.id_unidad = 100 THEN
                    v_tot_ambul := v_tot_ambul + 1;
                ELSIF reg_medico.id_unidad = 200 THEN
                    v_tot_urgen := v_tot_urgen + 1;
                ELSIF reg_medico.id_unidad = 300 THEN
                    v_tot_pacritico := v_tot_pacritico + 1;
                ELSIF reg_medico.id_unidad = 400 THEN
                    v_tot_adulto := v_tot_adulto + 1;
                ELSIF reg_medico.id_unidad = 500 THEN
                    v_tot_infantil := v_tot_infantil + 1;
                ELSIF reg_medico.id_unidad = 600 THEN
                    v_tot_maternidad := v_tot_maternidad + 1;
                ELSIF reg_medico.id_unidad = 700 THEN
                    v_tot_cirugia := v_tot_cirugia + 1;
                ELSIF reg_medico.id_unidad = 800 THEN
                    v_tot_cirugia_plast := v_tot_cirugia_plast + 1;
                ELSIF reg_medico.id_unidad = 900 THEN
                    v_tot_sobrep_obes := v_tot_sobrep_obes + 1;
                END IF;

            END IF;
        END LOOP;
    END LOOP;

    ------ INSERTAR TABLA RESUMEN
    INSERT INTO resumen_atenmedicas_mensuales VALUES ( v_mes_anno,
                                                       v_tot_ambul,
                                                       v_tot_urgen,
                                                       v_tot_pacritico,
                                                       v_tot_adulto,
                                                       v_tot_infantil,
                                                       v_tot_maternidad,
                                                       v_tot_cirugia,
                                                       v_tot_cirugia_plast,
                                                       v_tot_sobrep_obes,
                                                       sysdate );

    COMMIT;
END;
/