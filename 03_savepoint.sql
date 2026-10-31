-- TAREA 17 | Escenario 3 | Conexion A (psql).
-- Esperado: dos detalles anteriores conservados, error de FK recuperado,
-- tercer detalle corregido, total exacto y COMMIT final.
\set ON_ERROR_STOP on
\set ECHO queries
\pset pager off
\echo 'ESCENARIO 3 - RECUPERACION CON SAVEPOINT / SESION A'
-- Datos de sesion e identificacion del track inexistente.
SELECT pg_backend_pid() AS pid_a, current_database() AS base;
SELECT NOT EXISTS(SELECT 1 FROM track WHERE track_id=-1) AS id_menos_uno_es_invalido;

-- Nueva venta, independiente de 1 y 2, con clave generada por SERIAL.
BEGIN ISOLATION LEVEL READ COMMITTED;
INSERT INTO invoice (customer_id, invoice_date, billing_address,
                     billing_city, billing_state, billing_country,
                     billing_postal_code, total)
SELECT c.customer_id, CURRENT_TIMESTAMP, 'T17 PRACTICA - SAVEPOINT',
       c.city, c.state, c.country, c.postal_code, 0.00::numeric(10,2)
FROM customer AS c ORDER BY c.customer_id LIMIT 1
RETURNING invoice_id AS id_savepoint \gset
\echo 'ID REAL DE VENTA SAVEPOINT = ' :id_savepoint

-- Agregar DOS lineas validas ANTES del punto de recuperacion.
WITH disponibles AS (
  SELECT t.track_id, t.unit_price,
         ROW_NUMBER() OVER (ORDER BY t.track_id) AS posicion
  FROM (SELECT track_id, unit_price FROM track
        WHERE unit_price > 0 ORDER BY track_id LIMIT 2) AS t
)
INSERT INTO invoice_line (invoice_id, track_id, unit_price, quantity)
SELECT :id_savepoint, track_id, unit_price,
       CASE posicion WHEN 1 THEN 1 ELSE 2 END
FROM disponibles
RETURNING invoice_line_id, track_id, quantity;

-- Esperado: 2 detalles, antes de ejecutar la operacion riesgosa.
SELECT COUNT(*) AS detalles_antes_del_error
FROM invoice_line WHERE invoice_id = :id_savepoint;

-- Punto de recuperacion antes de intentar el INSERT invalido.
SAVEPOINT antes_del_error;
\set ON_ERROR_STOP off
\set VERBOSITY verbose
-- FK existente debe rechazar la cancion inexistente; se captura el ERROR 23503.
INSERT INTO invoice_line (invoice_id, track_id, unit_price, quantity)
VALUES (:id_savepoint, -1, 0.99, 1);

-- Recuperar SOLO el trabajo posterior al SAVEPOINT, no la venta completa.
ROLLBACK TO SAVEPOINT antes_del_error;
\set ON_ERROR_STOP on
\set VERBOSITY default

-- Esperado: siguen presentes las dos lineas previas; 0 con track_id=-1.
SELECT COUNT(*) AS detalles_conservados,
       COUNT(*) FILTER (WHERE track_id = -1) AS detalles_invalidos
FROM invoice_line WHERE invoice_id = :id_savepoint;

-- Sustituir el intento invalido por una tercera cancion real y distinta.
INSERT INTO invoice_line (invoice_id, track_id, unit_price, quantity)
SELECT :id_savepoint, t.track_id, t.unit_price, 1
FROM track AS t
WHERE t.unit_price > 0
  AND NOT EXISTS (
    SELECT 1 FROM invoice_line AS il
    WHERE il.invoice_id = :id_savepoint AND il.track_id = t.track_id
  )
ORDER BY t.track_id
LIMIT 1
RETURNING invoice_line_id, invoice_id, track_id, unit_price, quantity;

-- RELEASE elimina el punto de retorno: NO equivale a COMMIT.
RELEASE SAVEPOINT antes_del_error;

-- Calcular el total desde los detalles validos y guardarlo en la cabecera.
UPDATE invoice AS i
SET total = (
    SELECT SUM(il.unit_price * il.quantity)::numeric(10,2)
    FROM invoice_line AS il WHERE il.invoice_id = :id_savepoint
)
WHERE i.invoice_id = :id_savepoint
RETURNING invoice_id, total;

-- Esperado: 3 lineas, ninguna invalida, total igual y resultado true.
SELECT i.invoice_id, COUNT(il.invoice_line_id) AS detalles,
       COUNT(il.invoice_line_id) FILTER (WHERE il.track_id=-1) AS invalidos,
       i.total AS total_cabecera,
       COALESCE(SUM(il.unit_price*il.quantity),0)::numeric(10,2) AS total_detalles,
       (COUNT(il.invoice_line_id)>=3 AND i.total=SUM(il.unit_price*il.quantity)) AS cumple
FROM invoice AS i JOIN invoice_line AS il ON il.invoice_id=i.invoice_id
WHERE i.invoice_id = :id_savepoint
GROUP BY i.invoice_id, i.total;

-- Confirmacion EXPLICITA de la tercera operacion.
COMMIT;
-- Resultado persistente luego del COMMIT, para captura.
SELECT invoice_id, total, billing_address
FROM invoice WHERE invoice_id = :id_savepoint;
