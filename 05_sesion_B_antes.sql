-- TAREA 17 | Conexion B (psql) | Correr mientras A este detenida en su PAUSA.
-- Esperado: no ver datos sin confirmar de la factura de A.
\set ON_ERROR_STOP on
\set ECHO queries
\pset pager off
\echo 'SESION B ANTES DE COMMIT DE A'
-- Forzar aislamiento apropiado: cada SELECT ve datos confirmados al comenzar.
BEGIN ISOLATION LEVEL READ COMMITTED;
-- Registrar el ID de factura mostrado por A; no inventar ni adivinar.
\prompt 'Escribe el ID REAL de venta exitosa mostrado en A: ' id_exito
-- Confirmar que B usa otro backend y el aislamiento de la transaccion.
SELECT current_database() AS base_b, pg_backend_pid() AS pid_b,
       current_setting('transaction_isolation') AS aislamiento_b,
       :id_exito AS id_buscado;
-- Esperado: cabeceras_visibles = 0, detalles_visibles = 0.
SELECT (SELECT COUNT(*) FROM invoice WHERE invoice_id=:id_exito) AS cabeceras_visibles,
       (SELECT COUNT(*) FROM invoice_line WHERE invoice_id=:id_exito) AS detalles_visibles;
\echo 'CAPTURA RESULTADO ANTES; AHORA VUELVE A A Y PULSA ENTER PARA COMMIT.'
-- IMPORTANTE: no hacer COMMIT en B hasta ejecutar 06_sesion_B_despues.sql.
