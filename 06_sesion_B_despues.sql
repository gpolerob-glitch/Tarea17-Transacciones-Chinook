-- TAREA 17 | Conexion B (psql) | Correr DESPUES de COMMIT en A.
-- MISMA transaccion READ COMMITTED de B iniciada en archivo 05.
-- Esperado: B ahora ve 1 cabecera y 3 detalles de A.
\set ON_ERROR_STOP on
\set ECHO queries
\pset pager off
\echo 'SESION B DESPUES DE COMMIT DE A'
-- Confirmar mismo PID de B y mismo aislamiento.
SELECT pg_backend_pid() AS pid_b,
       current_setting('transaction_isolation') AS aislamiento_b,
       :id_exito AS factura_consultada;
-- Contadores principales para el antes/despues de COMMIT.
SELECT (SELECT COUNT(*) FROM invoice WHERE invoice_id=:id_exito) AS cabeceras_visibles,
       (SELECT COUNT(*) FROM invoice_line WHERE invoice_id=:id_exito) AS detalles_visibles;
-- Ver total calculado en cabecera y detalles confirmados.
SELECT i.invoice_id, i.total AS total_factura,
       COUNT(il.invoice_line_id) AS detalles,
       SUM(il.unit_price*il.quantity)::numeric(10,2) AS suma_detalles,
       i.total=SUM(il.unit_price*il.quantity) AS coincide
FROM invoice i JOIN invoice_line il ON il.invoice_id=i.invoice_id
WHERE i.invoice_id=:id_exito
GROUP BY i.invoice_id, i.total;
-- Cerrar la transaccion de lectura de B (no modifica datos).
COMMIT;
