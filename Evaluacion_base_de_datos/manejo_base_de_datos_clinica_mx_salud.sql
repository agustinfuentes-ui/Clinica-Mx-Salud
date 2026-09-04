SET SERVEROUTPUT ON;
-- variables
-- bind
VAR b_fecha_proceso VARCHAR2
EXEC :b_fecha_proceso:='202404';

DECLARE
-- escalares
v_tot_ambul NUMBER(5);
v_tot_urgen NUMBER(5);
v_tot_pacritico NUMBER(5);
v_tot_adulto NUMBER(5);
v_tot_infantil NUMBER(5);
v_tot_maternidad NUMBER(5);
v_tot_cirugia NUMBER(5);
v_tot_cirugia_plast NUMBER(5);
v_tot_sobrep_obes NUMBER(5);
v_copago_base NUMBER(10);
v_porc_descto_edad NUMBER(4,2);
v_descto_3ra_edad NUMBER(10);
v_valor_a_pagar NUMBER(10);
v_fec_venc_pago DATE;
v_fec_pago_real DATE;
v_valor_pagado_real NUMBER(10);
v_dias_atraso NUMBER(4);
v_monto_multa NUMBER(10);
v_diferencia NUMBER(10);
v_msg_error VARCHAR2(250);
v_nombre_unidad VARCHAR2(25);
v_nombre_especialidad VARCHAR2(100);
v_sitema_salud VARCHAR2(100);
v_decripcion_sistema_salud VARCHAR2(100);
v_cargo_medico VARCHAR2(100);

-- cursor sin parametros Es la tabla de atencion
CURSOR cur_medico IS
    SELECT med.med_run run_med,
           med.pnombre || med.snombre || med.apaterno || med.amaterno nombre,
           med.esp_id id_especialiodad,
           med.car_id id_cargo,
           med.uni_id id_unidad
    FROM  medico med;

-- cursor con parametros Es la tabla de medico
CURSOR cur_atencion(p_med_run NUMBER)IS
    SELECT atencion.ate_id,
           atencion.fecha_atencion fecha_ate,
           atencion.hr_atencion hora,
           atencion.costo,
           atencion.med_run,
           atencion.pac_run,
           paciente.pnombre||paciente.snombre||paciente.apaterno||paciente.amaterno nombre_paciente,
           paciente.sal_id
    FROM atencion atencion JOIN paciente paciente
                           ON (atencion.pac_run=paciente.pac_run)
    WHERE med_run = p_med_run;
-- varray
TYPE tipo_varray_porcentaje IS VARRAY(5) OF NUMBER(3,2);

varray_mora tipo_varray_porcentaje;
-- declaracion de exepciones

-- inicio de bloque
BEGIN
-- truncar tablas y secuencias
EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_ATENMEDICAS_MENSUALES';
EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_ATENMEDICAS_MENSUALES';
EXECUTE IMMEDIATE 'TRUNCATE TABLE PAGO_MOROSO';
EXECUTE IMMEDIATE 'TRUNCATE TABLE ERRORES_PROCESO';
--EXECUTE IMMEDIATE 'DROP SEQUENCE SQ_ERROR';
--EXECUTE IMMEDIATE 'CREATE SEQUENCE SQ_ERROR';
-- DROP 
-- asignar valores del varray

-- inicio primer loop (cursor sin parametros)
FOR reg_medico IN cur_medico LOOP
-- creacion y asignacion de variable totalizadora
v_tot_ambul:=0;
v_tot_urgen:=0;
v_tot_pacritico:=0;
v_tot_adulto:=0;
v_tot_infantil:=0;
v_tot_maternidad:=0;
v_tot_cirugia:=0;
v_tot_cirugia_plast:=0;
v_tot_sobrep_obes:=0;

-- inicio segundo loop (cursor con parametros)
    FOR reg_atencion IN cur_atencion(reg_medico.run_med)LOOP
-- calculos
    IF TO_CHAR(reg_atencion.fecha_ate,'YYYYMM')=:b_fecha_proceso THEN
        -- Obtencion unidad atencion
        SELECT uni.nombre
        INTO v_nombre_unidad
        FROM unidad uni JOIN medico med
                        ON (uni.uni_id=med.uni_id)
        WHERE med.med_run = reg_medico.run_med;
        -- Obtencion especialidad atencion
        SELECT espe.nombre
        INTO v_nombre_especialidad
        FROM especialidad espe JOIN medico med
                        ON (espe.esp_id=med.esp_id)
        WHERE med.med_run = reg_medico.run_med;
        -- Obtencion cargo medico
        SELECT car.nombre
        INTO v_cargo_medico
        FROM cargo car JOIN medico med
                        ON (car.car_id=med.car_id)
        WHERE med.med_run=reg_medico.run_med;
        -- Obtencion sistema salud
        SELECT ti_sal.descripcion
        INTO v_sitema_salud
        FROM tipo_salud ti_sal JOIN salud sal
                        ON (ti_sal.TIPO_SAL_ID=sal.TIPO_SAL_ID)
                        JOIN paciente pac
                        ON (sal.sal_id=pac.sal_id)
        WHERE pac.sal_id = reg_atencion.sal_id;
        -- Obtencion descripcion sitema salud
        SELECT sal.descripcion
        INTO v_decripcion_sistema_salud
        FROM salud sal JOIN paciente pac
                        ON (sal.sal_id=pac.sal_id)
        WHERE pac.sal_id = reg_atencion.sal_id;
        -- Obtencion valor pagar
        SELECT pag_ate.valor_a_pagar
        INTO v_valor_a_pagar
        FROM pago_atencion pag_ate JOIN atencion ate
                        ON (pag_ate.ate_id=ate.ate_id)
        WHERE ate.ate_id=reg_atencion.ate_id;
        -- Obtencion valor pagado
        SELECT pag_ate.monto_pagado
        INTO v_valor_pagado_real
        FROM pago_atencion pag_ate JOIN atencion ate
                        ON (pag_ate.ate_id=ate.ate_id)
        WHERE ate.ate_id=reg_atencion.ate_id;
    -- uso de exepciones
        v_diferencia:=v_valor_a_pagar-v_valor_pagado_real;
    -- insercion de detalle
        INSERT INTO DETALLE_ATENMEDICAS_MENSUALES
        VALUES(SUBSTR(:b_fecha_proceso,5,2)||'/'||SUBSTR(:b_fecha_proceso,1,4),
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
            v_diferencia);        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE(reg_atencion.ate_id);
-- calculo de totalizadoras
        IF reg_medico.id_unidad = 100 THEN
            v_tot_ambul:= v_tot_ambul + 1;
        ELSIF reg_medico.id_unidad = 200 THEN
            v_tot_urgen:= v_tot_urgen + 1;
        ELSIF reg_medico.id_unidad = 300 THEN
            v_tot_pacritico:= v_tot_pacritico + 1;
        ELSIF reg_medico.id_unidad = 400 THEN
            v_tot_adulto:= v_tot_adulto + 1;
        ELSIF reg_medico.id_unidad = 500 THEN
        v_tot_infantil:= v_tot_infantil + 1;
        ELSIF reg_medico.id_unidad = 600 THEN
            v_tot_maternidad:= v_tot_maternidad + 1;
        ELSIF reg_medico.id_unidad = 700 THEN
            v_tot_cirugia:= v_tot_cirugia + 1;
        ELSIF reg_medico.id_unidad = 800 THEN
            v_tot_cirugia_plast:= v_tot_cirugia_plast + 1;
        ELSIF reg_medico.id_unidad = 900 THEN
            v_tot_sobrep_obes:= v_tot_sobrep_obes + 1;
        END IF;
    END IF;     
    -- fin del segundo loop
    END LOOP;
-- inserto en la tabla resumen
INSERT INTO RESUMEN_ATENMEDICAS_MENSUALES
VALUES(SUBSTR(:b_fecha_proceso,5,2)||'/'||SUBSTR(:b_fecha_proceso,1,4),
 v_tot_ambul,
 v_tot_urgen,
 v_tot_pacritico,
 v_tot_adulto,
 v_tot_infantil,
 v_tot_maternidad,
 v_tot_cirugia,
 v_tot_cirugia_plast,
 v_tot_sobrep_obes,
 SYSDATE);
COMMIT;
-- fin primer loop
END LOOP;
-- fin de bloque
END;

