-- TAREA 17 | Escenario 1 | Ejecutar en psql, conexion A.
-- Requisito: Chinook oficial variante SerialPKs en una BD local dedicada.
-- Esperado: factura con 3 detalles, total exacto y COMMIT explicito.
-- NOTA: Este archivo usa comandos de psql (\\gset y \\prompt); no se ejecuta como SQL puro en DataGrip.
\set ON_ERROR_STOP on
\set ECHO queries
\pset pager off
\echo 'ESCENARIO 1 - VENTA EXITOSA / SESION A'
-- Mostrar la conexion efectiva y el aislamiento por defecto.
SELECT current_database() AS base, pg_backend_pid() AS pid_a,
       current_setting('default_transaction_isolation') AS aislamiento_defecto,
       current_setting('server_version') AS version_postgresql;

-- Comenzar una transaccion READ COMMITTED; autocommit del cliente permanece activado.
BEGIN ISOLATION LEVEL READ COMMITTED;
-- Recuperar el identificador real sin calcular MAX(id)+1; psql lo guarda en :id_exito.
-- El total 0.00 es temporal y NO se confirma antes de actualizarlo.
INSERT INTO invoice (customer_id, invoice_date, billing_address,
                     billing_city, billing_state, billing_country,
                     billing_postal_code, total)
SELECT c.customer_id, CURRENT_TIMESTAMP, 'T17 PRACTICA - EXITO',
       c.city, c.state, c.country, c.postal_code, 0.00::numeric(10,2)
FROM customer AS c
ORDER BY c.customer_id
LIMIT 1
RETURNING invoice_id AS id_exito \gset
\echo 'ID REAL DE VENTA EXITOSA = ' :id_exito

-- Incorporar 3 canciones existentes; precios vienen de track y cantidades son positivas.
WITH disponibles AS (
  SELECT t.track_id, t.unit_price,
         ROW_NUMBER() OVER (ORDER BY t.track_id) AS posicion
  FROM (SELECT track_id, unit_price FROM track
        WHERE unit_price > 0 ORDER BY track_id LIMIT 3) AS t
)
INSERT INTO invoice_line (invoice_id, track_id, unit_price, quantity)
SELECT :id_exito, track_id, unit_price,
       CASE posicion WHEN 1 THEN 1 WHEN 2 THEN 2 ELSE 3 END
FROM disponibles
RETURNING invoice_line_id, invoice_id, track_id, unit_price, quantity;

-- Actualizar el total a partir de los detalles, usando NUMERIC.
UPDATE invoice AS i
SET total = (
    SELECT SUM(il.unit_price * il.quantity)::numeric(10,2)
    FROM invoice_line AS il WHERE il.invoice_id = :id_exito
)
WHERE i.invoice_id = :id_exito
RETURNING i.invoice_id, i.total;

-- Comprobar >=3 lineas, precios y cantidades validos y total exactamente coincidente.
SELECT i.invoice_id, COUNT(il.invoice_line_id) AS cantidad_detalles,
       i.total AS total_factura,
       COALESCE(SUM(il.unit_price * il.quantity), 0)::numeric(10,2) AS total_calculado,
       BOOL_AND(il.quantity > 0 AND il.unit_price >= 0) AS detalles_validos,
       (COUNT(il.invoice_line_id) >= 3 AND
        i.total = COALESCE(SUM(il.unit_price * il.quantity),0)) AS cumple
FROM invoice AS i
LEFT JOIN invoice_line AS il ON il.invoice_id = i.invoice_id
WHERE i.invoice_id = :id_exito
GROUP BY i.invoice_id, i.total;

-- PAUSA REAL: antes de pulsar Enter aqui, ejecutar 05_sesion_B_antes.sql en B.
\echo 'PAUSA: registrar ID ' :id_exito ' y consultar desde SESION B (archivo 05).'
\prompt 'Cuando B muestre 0 cabeceras y 0 detalles, vuelve a A y pulsa ENTER: ' confirmacion
-- Solo despues de la captura de B se confirma. COMMIT es visible y explicito.
COMMIT;

-- Despues del COMMIT, esta cabecera debe seguir visible en A.
SELECT invoice_id, total, billing_address FROM invoice WHERE invoice_id = :id_exito;
\echo 'A confirmo. En B ejecute 06_sesion_B_despues.sql SIN cerrar la sesion.'
