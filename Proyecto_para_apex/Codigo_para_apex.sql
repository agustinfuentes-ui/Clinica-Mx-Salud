SET SERVEROUTPUT ON;

/* =============================================================================
   EVALUACIÓN PARCIAL N°2: ARQUITECTURA MODULAR PL/SQL
   PROYECTO: CLÍNICA MAX SALUD
   
   ORDEN DE COMPILACIÓN:
     1. Secuencias y Tablas de Auditoría
     2. Especificación del Package (PKG_LIQUIDACION_MAXSALUD)
     3. Cuerpo del Package (PKG_LIQUIDACION_MAXSALUD)
     4. Funciones Almacenadas Independientes (Con y Sin Parámetros)
     5. Triggers de Base de Datos (Fila y Sentencia)
     6. Procedimientos Almacenados (Con y Sin Parámetros)
     7. Bloque de Ejecución y Consultas de Validación
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- 1. SECUENCIAS Y TABLAS DE AUDITORÍA
-- -----------------------------------------------------------------------------

-- Secuencia para el correlativo de bitácora de errores
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

-- Tabla de auditoría para el Trigger a nivel de sentencia
BEGIN
    EXECUTE IMMEDIATE 'CREATE TABLE LOG_CIERRE_MENSUAL (
        id_log        NUMBER GENERATED ALWAYS AS IDENTITY,
        fecha_proceso DATE,
        usuario       VARCHAR2(30),
        mensaje       VARCHAR2(150)
    )';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

-- -----------------------------------------------------------------------------
-- 2. ENCABEZADO DEL PACKAGE (ESPECIFICACIÓN PÚBLICA)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE PKG_LIQUIDACION_MAXSALUD IS

    -- Función pública: Calcula el descuento por tramo etario (3ra edad)
    FUNCTION F_CALCULAR_DESCTO_EDAD(
        p_fecha_ate    IN DATE,
        p_fecha_nac    IN DATE,
        p_copago_base  IN NUMBER
    ) RETURN NUMBER;

    -- Función pública: Obtiene el porcentaje anual y liquida el recargo de Fuerzas Armadas
    FUNCTION F_OBTENER_RECARGO_FFAA(
        p_tipo_sal_id  IN VARCHAR2,
        p_anno         IN NUMBER,
        p_copago_base  IN NUMBER
    ) RETURN NUMBER;

    -- Función pública SIN parámetros: Retorna la cantidad de tramos etarios soportados
    FUNCTION F_CANTIDAD_TRAMOS_SENIOR RETURN NUMBER;

END PKG_LIQUIDACION_MAXSALUD;
/

-- -----------------------------------------------------------------------------
-- 3. CUERPO DEL PACKAGE (PACKAGE BODY)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY PKG_LIQUIDACION_MAXSALUD IS

    -- Elementos privados: Tipo y constante VARRAY para los 5 tramos etarios
    TYPE tipo_varray_descto IS VARRAY(5) OF NUMBER(3,2);
    c_tramos_descto CONSTANT tipo_varray_descto := tipo_varray_descto(0.05, 0.09, 0.12, 0.15, 0.18);

    -- Función privada auxiliar: Determina los años cumplidos a la fecha de atención
    FUNCTION F_CALCULAR_EDAD_ANOS(
        p_fecha_ref IN DATE,
        p_fecha_nac IN DATE
    ) RETURN NUMBER IS
    BEGIN
        IF p_fecha_ref IS NULL OR p_fecha_nac IS NULL THEN
            RETURN 0;
        END IF;
        RETURN TRUNC(MONTHS_BETWEEN(p_fecha_ref, p_fecha_nac) / 12);
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 0;
    END F_CALCULAR_EDAD_ANOS;

    -- Función privada auxiliar: Valida consistencia de un monto de costo
    FUNCTION F_VALIDAR_COSTO(p_costo IN NUMBER) RETURN BOOLEAN IS
    BEGIN
        RETURN (p_costo IS NOT NULL AND p_costo > 0);
    END F_VALIDAR_COSTO;

    -- Función pública: Liquida el descuento por tercera edad
    FUNCTION F_CALCULAR_DESCTO_EDAD(
        p_fecha_ate    IN DATE,
        p_fecha_nac    IN DATE,
        p_copago_base  IN NUMBER
    ) RETURN NUMBER IS
        v_edad NUMBER(3);
        v_pct  NUMBER(3,2) := 0;
    BEGIN
        v_edad := F_CALCULAR_EDAD_ANOS(p_fecha_ate, p_fecha_nac);

        IF v_edad BETWEEN 60 AND 65 THEN
            v_pct := c_tramos_descto(1);
        ELSIF v_edad BETWEEN 66 AND 70 THEN
            v_pct := c_tramos_descto(2);
        ELSIF v_edad BETWEEN 71 AND 76 THEN
            v_pct := c_tramos_descto(3);
        ELSIF v_edad BETWEEN 77 AND 85 THEN
            v_pct := c_tramos_descto(4);
        ELSIF v_edad >= 86 THEN
            v_pct := c_tramos_descto(5);
        ELSE
            v_pct := 0;
        END IF;

        RETURN ROUND(NVL(p_copago_base, 0) * v_pct);
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 0;
    END F_CALCULAR_DESCTO_EDAD;

    -- Función pública: Liquida el recargo FFAA consultando la tabla paramétrica
    FUNCTION F_OBTENER_RECARGO_FFAA(
        p_tipo_sal_id  IN VARCHAR2,
        p_anno         IN NUMBER,
        p_copago_base  IN NUMBER
    ) RETURN NUMBER IS
        v_porc_recargo NUMBER(3,2) := 0;
        v_msg_error    VARCHAR2(250);
    BEGIN
        IF p_tipo_sal_id = 'FA' THEN
            BEGIN
                SELECT porc_recargo
                INTO v_porc_recargo
                FROM recargo_atencion_ffaa
                WHERE anno_recargo = p_anno;
            EXCEPTION
                WHEN OTHERS THEN
                    v_msg_error := SQLERRM;
                    INSERT INTO ERRORES_PROCESO
                    VALUES (
                        sq_error.NEXTVAL,
                        'PKG_LIQUIDACION_MAXSALUD.F_OBTENER_RECARGO_FFAA',
                        'Error consultando recargo anio ' || p_anno || ': ' || v_msg_error
                    );
                    v_porc_recargo := 0;
            END;
            
            RETURN ROUND(NVL(p_copago_base, 0) * v_porc_recargo);
        END IF;

        RETURN 0;
    END F_OBTENER_RECARGO_FFAA;

    -- Función pública sin parámetros: Retorna la cantidad de tramos del VARRAY
    FUNCTION F_CANTIDAD_TRAMOS_SENIOR RETURN NUMBER IS
    BEGIN
        RETURN c_tramos_descto.COUNT;
    END F_CANTIDAD_TRAMOS_SENIOR;

END PKG_LIQUIDACION_MAXSALUD;
/

-- -----------------------------------------------------------------------------
-- 4. FUNCIONES ALMACENADAS INDEPENDIENTES
-- -----------------------------------------------------------------------------

-- Función con parámetros (Almacenada): Obtiene el nombre de la unidad médica
CREATE OR REPLACE FUNCTION FN_NOMBRE_UNIDAD(p_med_run NUMBER) 
RETURN VARCHAR2 IS
    v_nombre_unidad unidad.nombre%TYPE;
    v_error         VARCHAR2(250);
BEGIN
    SELECT uni.nombre
    INTO v_nombre_unidad
    FROM unidad uni 
    JOIN medico med ON (uni.uni_id = med.uni_id)
    WHERE med.med_run = p_med_run;
    
    RETURN v_nombre_unidad;
EXCEPTION 
    WHEN OTHERS THEN
        v_error := SQLERRM;
        INSERT INTO ERRORES_PROCESO
        VALUES (
            sq_error.NEXTVAL,
            'FN_NOMBRE_UNIDAD',
            'Error al obtener unidad para medico RUN ' || p_med_run || ': ' || v_error
        );
        RETURN '***UNIDAD NO ENCONTRADA***';
END FN_NOMBRE_UNIDAD;
/

-- Función sin parámetros (Almacenada): Retorna la tasa institucional de morosidad (10%)
CREATE OR REPLACE FUNCTION FN_MULTA_GLOBAL 
RETURN NUMBER IS
BEGIN
    RETURN 0.10;
END FN_MULTA_GLOBAL;
/

-- -----------------------------------------------------------------------------
-- 5. TRIGGERS DE BASE DE DATOS
-- -----------------------------------------------------------------------------

-- Trigger a nivel de fila (FOR EACH ROW): Valida e inicializa atributos de la atención
CREATE OR REPLACE TRIGGER TRG_AUDITA_DETALLE_FILA
BEFORE INSERT ON DETALLE_ATENMEDICAS_MENSUALES
FOR EACH ROW
BEGIN
    IF :NEW.fecha_atencion IS NULL THEN
        :NEW.fecha_atencion := TRUNC(SYSDATE);
    END IF;
END TRG_AUDITA_DETALLE_FILA;
/

-- Trigger a nivel de sentencia: Audita el cierre y consolidación mensual de unidades
CREATE OR REPLACE TRIGGER TRG_AUDITA_CIERRE_SENTENCIA
AFTER INSERT ON RESUMEN_ATENMEDICAS_MENSUALES
BEGIN
    INSERT INTO LOG_CIERRE_MENSUAL (fecha_proceso, usuario, mensaje)
    VALUES (
        SYSDATE, 
        USER, 
        'Consolidacion mensual de atenciones por unidad generada con exito.'
    );
END TRG_AUDITA_CIERRE_SENTENCIA;
/

-- -----------------------------------------------------------------------------
-- 6. PROCEDIMIENTOS ALMACENADOS
-- -----------------------------------------------------------------------------

-- Procedimiento principal con parámetros: Procesa la liquidación del período
CREATE OR REPLACE PROCEDURE SP_LIQUIDACION_MEDICA(
    p_periodo    IN VARCHAR2, -- Formato: 'YYYYMM' (ej: '202601')
    p_porc_multa IN NUMBER    -- Tasa de multa (ej: 0.10)
) IS

    -- Cursores de procesamiento
    CURSOR cur_medico IS
        SELECT med.med_run run_med,
               med.esp_id id_especialiodad,
               med.car_id id_cargo
        FROM   medico med
        ORDER BY med.med_run;

    CURSOR cur_atencion(p_med_run NUMBER) IS
        SELECT atencion.ate_id,
               atencion.fecha_atencion fecha_ate,
               atencion.hr_atencion hora,
               atencion.costo,
               atencion.med_run,
               atencion.pac_run,
               paciente.dv_run pac_dv_run,
               paciente.pnombre || ' ' || NVL(paciente.snombre || ' ', '') || paciente.apaterno || ' ' || paciente.amaterno nombre_paciente,
               paciente.fecha_nacimiento,
               paciente.sal_id
        FROM atencion atencion 
        JOIN paciente paciente ON (atencion.pac_run = paciente.pac_run)
        WHERE med_run = p_med_run;

    -- Totalizadores por unidad médica
    v_tot_ambul          NUMBER(5) := 0;
    v_tot_urgen          NUMBER(5) := 0;
    v_tot_pacritico      NUMBER(5) := 0;
    v_tot_adulto         NUMBER(5) := 0;
    v_tot_infantil       NUMBER(5) := 0;
    v_tot_maternidad     NUMBER(5) := 0;
    v_tot_cirugia        NUMBER(5) := 0;
    v_tot_cirugia_plast  NUMBER(5) := 0;
    v_tot_sobrep_obes    NUMBER(5) := 0;

    -- Variables de cálculo monetario
    v_copago_base        NUMBER(10);
    v_porc_copago        NUMBER(5,2);
    v_descto_3ra_edad    NUMBER(10);
    v_recargo_ffaa       NUMBER(10);
    v_valor_a_pagar      NUMBER(10);
    v_fec_venc_pago      DATE;
    v_fec_pago_real      DATE;
    v_valor_pagado_real  NUMBER(10);
    v_dias_atraso        NUMBER(4);
    v_monto_multa        NUMBER(10);
    v_diferencia         NUMBER(10);

    -- Variables descriptivas
    v_nombre_medico            VARCHAR2(100);
    v_nombre_unidad            VARCHAR2(100);
    v_nombre_especialidad      VARCHAR2(100);
    v_cargo_medico             VARCHAR2(100);
    v_sitema_salud             VARCHAR2(100);
    v_tipo_sal_id              VARCHAR2(3);
    v_decripcion_sistema_salud VARCHAR2(100);
    v_mes_anno                 VARCHAR2(7);

    -- Excepciones de negocio definidas por el usuario
    costo_invalido     EXCEPTION;
    paciente_sin_salud EXCEPTION;

BEGIN
    -- Limpieza de tablas destino
    EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_ATENMEDICAS_MENSUALES';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_ATENMEDICAS_MENSUALES';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE PAGO_MOROSO';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE ERRORES_PROCESO';

    -- Formato visual MM/AAAA
    v_mes_anno := SUBSTR(p_periodo, 5, 2) || '/' || SUBSTR(p_periodo, 1, 4);

    -- Primer Loop: Médicos
    FOR reg_medico IN cur_medico LOOP

        -- Invocación de función independiente
        v_nombre_unidad := FN_NOMBRE_UNIDAD(reg_medico.run_med);

        SELECT espe.nombre 
        INTO v_nombre_especialidad
        FROM especialidad espe
        WHERE espe.esp_id = reg_medico.id_especialiodad;

        SELECT car.nombre
        INTO v_cargo_medico
        FROM cargo car 
        WHERE car.car_id = reg_medico.id_cargo;

        SELECT med.pnombre ||' '|| med.snombre ||' '|| med.apaterno ||' '|| med.amaterno
        INTO v_nombre_medico
        FROM medico med
        WHERE med.med_run = reg_medico.run_med;

        -- Segundo Loop: Atenciones del médico
        FOR reg_atencion IN cur_atencion(reg_medico.run_med) LOOP

            IF TO_CHAR(reg_atencion.fecha_ate, 'YYYYMM') = p_periodo THEN

                SELECT ti_sal.descripcion, ti_sal.tipo_sal_id
                INTO v_sitema_salud, v_tipo_sal_id
                FROM tipo_salud ti_sal 
                JOIN salud sal ON (ti_sal.tipo_sal_id = sal.tipo_sal_id)
                WHERE sal.sal_id = reg_atencion.sal_id;

                SELECT sal.descripcion, sal.costo_pago / 100
                INTO v_decripcion_sistema_salud, v_porc_copago
                FROM salud sal
                WHERE sal.sal_id = reg_atencion.sal_id;

                -- Consulta de pago con captura OTHERS
                BEGIN
                    SELECT pag_ate.valor_a_pagar, pag_ate.fecha_venc_pago, pag_ate.fecha_pago
                    INTO v_valor_pagado_real, v_fec_venc_pago, v_fec_pago_real
                    FROM pago_atencion pag_ate
                    WHERE pag_ate.ate_id = reg_atencion.ate_id;
                EXCEPTION
                    WHEN OTHERS THEN
                        v_valor_pagado_real := 0;
                        v_fec_venc_pago := NULL;
                        v_fec_pago_real := NULL;
                END;

                -- Validación de reglas de integridad
                BEGIN
                    IF reg_atencion.costo <= 0 THEN
                        RAISE costo_invalido;
                    END IF;
                    IF reg_atencion.sal_id IS NULL THEN
                        RAISE paciente_sin_salud;
                    END IF;
                EXCEPTION
                    WHEN costo_invalido THEN
                        INSERT INTO ERRORES_PROCESO
                        VALUES (sq_error.NEXTVAL, 'SP_LIQUIDACION_MEDICA - Ate ID: ' || reg_atencion.ate_id, 'La atencion registra un costo menor o igual a cero');
                    WHEN paciente_sin_salud THEN
                        INSERT INTO ERRORES_PROCESO
                        VALUES (sq_error.NEXTVAL, 'SP_LIQUIDACION_MEDICA - Pac RUN: ' || reg_atencion.pac_run, 'El paciente no tiene sistema de salud asociado');
                END;

                -- Cálculo de copago base
                v_copago_base := ROUND(reg_atencion.costo * NVL(v_porc_copago, 0));

                -- Invocaciones a funciones del Package
                v_descto_3ra_edad := PKG_LIQUIDACION_MAXSALUD.F_CALCULAR_DESCTO_EDAD(
                    reg_atencion.fecha_ate, 
                    reg_atencion.fecha_nacimiento, 
                    v_copago_base
                );

                v_recargo_ffaa := PKG_LIQUIDACION_MAXSALUD.F_OBTENER_RECARGO_FFAA(
                    v_tipo_sal_id, 
                    TO_NUMBER(SUBSTR(p_periodo, 1, 4)), 
                    v_copago_base
                );

                -- Valores finales
                v_valor_a_pagar := v_copago_base - v_descto_3ra_edad + v_recargo_ffaa;
                v_diferencia    := v_valor_a_pagar - NVL(v_valor_pagado_real, 0);

                -- Inserción en tabla detalle (Dispara TRG_AUDITA_DETALLE_FILA)
                INSERT INTO DETALLE_ATENMEDICAS_MENSUALES
                VALUES(v_mes_anno,
                       reg_atencion.ate_id,
                       reg_atencion.fecha_ate,
                       reg_atencion.hora,
                       v_nombre_unidad,
                       v_nombre_especialidad,
                       v_nombre_medico,
                       v_cargo_medico,
                       reg_atencion.nombre_paciente,
                       v_sitema_salud,
                       v_decripcion_sistema_salud,
                       reg_atencion.costo,
                       v_valor_a_pagar,
                       v_valor_pagado_real,
                       v_diferencia);

                -- Registro de morosidad
                IF v_fec_pago_real IS NOT NULL AND v_fec_venc_pago IS NOT NULL AND v_fec_pago_real > v_fec_venc_pago THEN
                    v_dias_atraso := TRUNC(v_fec_pago_real - v_fec_venc_pago);
                    v_monto_multa := ROUND(v_valor_a_pagar * p_porc_multa);

                    INSERT INTO PAGO_MOROSO
                    VALUES(reg_atencion.pac_run,
                           reg_atencion.pac_dv_run,
                           SUBSTR(reg_atencion.nombre_paciente, 1, 50),
                           reg_atencion.ate_id,
                           v_fec_venc_pago,
                           v_fec_pago_real,
                           v_dias_atraso,
                           SUBSTR(v_nombre_especialidad, 1, 30),
                           reg_atencion.costo,
                           v_monto_multa,
                           'Pago fuera de plazo');
                END IF;

                -- Acumulación de atenciones por unidad
                CASE v_nombre_unidad
                    WHEN 'Atencion Ambulatoria' THEN v_tot_ambul := v_tot_ambul + 1;
                    WHEN 'Atencion Urgencia' THEN v_tot_urgen := v_tot_urgen + 1;
                    WHEN 'Paciente Critico' THEN v_tot_pacritico := v_tot_pacritico + 1;
                    WHEN 'Atencion Adulto' THEN v_tot_adulto := v_tot_adulto + 1;
                    WHEN 'Atencion Infantil' THEN v_tot_infantil := v_tot_infantil + 1;
                    WHEN 'Maternidad' THEN v_tot_maternidad := v_tot_maternidad + 1;
                    WHEN 'Cirugia' THEN v_tot_cirugia := v_tot_cirugia + 1;
                    WHEN 'Cirugia Plastica' THEN v_tot_cirugia_plast := v_tot_cirugia_plast + 1;
                    WHEN 'Sobrepreso y Obesidad' THEN v_tot_sobrep_obes := v_tot_sobrep_obes + 1;
                    ELSE NULL;
                END CASE;

            END IF;
        END LOOP;
    END LOOP;

    -- Inserción del resumen mensual (Dispara TRG_AUDITA_CIERRE_SENTENCIA)
    INSERT INTO RESUMEN_ATENMEDICAS_MENSUALES
    VALUES(v_mes_anno,
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
    DBMS_OUTPUT.PUT_LINE('Proceso finalizado exitosamente para el periodo: ' || v_mes_anno);

END SP_LIQUIDACION_MEDICA;
/

-- Procedimiento sin parámetros: Invoca el proceso usando parámetros globales por defecto
CREATE OR REPLACE PROCEDURE SP_CIERRE_MES_ACTUAL IS
    v_periodo_defecto VARCHAR2(6);
    v_multa_defecto   NUMBER;
BEGIN
    v_periodo_defecto := '202601';
    v_multa_defecto   := FN_MULTA_GLOBAL;

    SP_LIQUIDACION_MEDICA(v_periodo_defecto, v_multa_defecto);
END SP_CIERRE_MES_ACTUAL;
/

-- -----------------------------------------------------------------------------
-- 7. EJECUCIÓN Y VALIDACIÓN FINAL
-- -----------------------------------------------------------------------------

-- Ejecución del procedimiento de liquidación mensual
EXEC SP_LIQUIDACION_MEDICA('202601', 0.10);

-- Consultas de comprobación
SELECT * FROM RESUMEN_ATENMEDICAS_MENSUALES;
SELECT COUNT(*) AS TOTAL_DETALLE FROM DETALLE_ATENMEDICAS_MENSUALES;
SELECT COUNT(*) AS TOTAL_MOROSOS FROM PAGO_MOROSO;
SELECT * FROM ERRORES_PROCESO;
SELECT * FROM LOG_CIERRE_MENSUAL;