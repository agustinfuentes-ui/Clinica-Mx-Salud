-- variables
-- bind
VAR b_fecha_proceso VARCHAR2
EXEC :b_fecha_proceso:='202404';

DECLARE
-- escalares

-- cursor sin parametros Es la tabla de atencion
CURSOR cur_medico IS
    SELECT med_run || dv_run AS run_medico,
           pnombre || snombre || apaterno || amaterno AS nombre,
           esp_id AS id_especialiodad,
           car_id AS id_cargo
    FROM  medico;

-- cursor con parametros Es la tabla de medico
CURSOR cur_atencion(p_med_run NUMBER)IS
    SELECT atencion.ate_id,
           fecha_atencion,
           med_run,
           pac_run
    FROM atencion
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
EXECUTE IMMEDIATE 'TRUNCATE TABLE ERRORES_PROCESO';
-- DROP 
-- asignar valores del varray

-- inicio primer loop (cursor sin parametros)
FOR reg_atencion IN cur_atencion LOOP
-- creacion y asignacion de variable totalizadora

-- inicio segundo loop (cursor con parametros)
    FOR reg_medico IN cur_medico()LOOP
-- calculos

-- uso de exepciones

-- insercion de detalle

-- calculo de totalizadoras

-- fin del segundo loop
    END LOOP;
-- inserto en la tabla resumen

-- fin del primer loop
END LOOP;
-- fin de bloque
END;

