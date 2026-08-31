-- variables
-- bind
VAR b_fecha_proceso VARCHAR2
EXEC :b_fecha_proceso:='202404';

DECLARE
-- escalares

-- cursor sin parametros Es la tabla de atencion
CURSOR cur_atencion IS
    SELECT ate_id
    FROM atencion;

-- cursor con parametros Es la tabla de medico
CURSOR cur_medico ()IS
    SELECT  med_run
    FROM medico;
-- varray

-- declaracion de exepciones

-- inicio de bloque
BEGIN
-- truncar tablas y secuencias
EXECUTE
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

