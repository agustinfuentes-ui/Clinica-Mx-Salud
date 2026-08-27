-- variables
-- bind

DECLARE
-- escalares

-- cursor sin parametros
CURSOR cur_num1 IS
    SELECT *
    FROM table;

-- cursor con parametros
CURSOR cur_num2 IS
    SELECT * 
    FROM table;
-- varray

-- declaracion de exepciones

-- inicio de bloque
BEGIN
-- truncar tablas y secuencias

-- asignar valores del varray

-- inicio primer loop (cursor sin parametros)
FOR reg_num1 IN cur_num1 LOOP
-- creacion y asignacion de variable totalizadora

-- inicio segundo loop (cursor con parametros)
    FOR reg_num2 IN cur_num2()LOOP
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

