-- TAREA 17 | Escenario 2 | Conexion A (psql).
-- Esperado: error 23503 de FOREIGN KEY, estado 25P02 y ROLLBACK completo.
-- Ejecucion independiente: usa RETURNING, no depende de la venta 1.
\set ON_ERROR_STOP on
\set ECHO queries
\pset pager off
\echo 'ESCENARIO 2 - ERROR Y ROLLBACK TOTAL / SESION A'
-- Identificar sesion, base y nivel de aislamiento.
SELECT current_database() AS base, pg_backend_pid() AS pid_a,
       current_setting('default_transaction_isolation') AS aislamiento;

-- Comprobar ANTES del error que track_id = -1 no existe en esta copia.
-- Esperado: existe_id_invalido = false y coincidencias = 0.
SELECT EXISTS(SELECT 1 FROM track WHERE track_id = -1) AS existe_id_invalido,
       (SELECT COUNT(*) FROM track WHERE track_id = -1) AS coincidencias;

-- Abrir una NUEVA venta y recuperar clave de PostgreSQL.
BEGIN ISOLATION LEVEL READ COMMITTED;
INSERT INTO invoice (customer_id, invoice_date, billing_address,
                     billing_city, billing_state, billing_country,
                     billing_postal_code, total)
SELECT c.customer_id, CURRENT_TIMESTAMP, 'T17 PRACTICA - ROLLBACK',
       c.city, c.state, c.country, c.postal_code, 0.00::numeric(10,2)
FROM customer AS c ORDER BY c.customer_id LIMIT 1
RETURNING invoice_id AS id_rollback \gset
\echo 'ID REAL DE VENTA A REVERTIR = ' :id_rollback

-- Insertar por lo menos un detalle valido de una cancion existente.
INSERT INTO invoice_line (invoice_id, track_id, unit_price, quantity)
SELECT :id_rollback, track_id, unit_price, 2
FROM track WHERE unit_price > 0 ORDER BY track_id LIMIT 1
RETURNING invoice_line_id, invoice_id, track_id, quantity;

-- Error PROVOCADO: la FK invoice_line_track_id_fkey impide track_id -1.
-- Desactivar ON_ERROR_STOP de psql SOLO para capturar los mensajes y recuperar.
\set ON_ERROR_STOP off
\set VERBOSITY verbose
INSERT INTO invoice_line (invoice_id, track_id, unit_price, quantity)
VALUES (:id_rollback, -1, 0.99, 1);
-- Esperado: ERROR current transaction is aborted (SQLSTATE 25P02).
SELECT COUNT(*) AS consulta_imposible_mientras_abortada
FROM invoice WHERE invoice_id = :id_rollback;

-- La transaccion completa se revierte, incluida la cabecera y el detalle valido.
ROLLBACK;
\set ON_ERROR_STOP on
\set VERBOSITY default

-- Esperado: 0 cabeceras y 0 detalles para la CLAVE DEVUELTA por RETURNING.
SELECT :id_rollback AS factura_revertida,
       (SELECT COUNT(*) FROM invoice WHERE invoice_id = :id_rollback) AS cabeceras_restantes,
       (SELECT COUNT(*) FROM invoice_line WHERE invoice_id = :id_rollback) AS detalles_restantes;
