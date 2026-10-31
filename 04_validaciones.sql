-- TAREA 17 | Consultas finales no destructivas | Conexion A (psql).
-- Ejecutar DESPUES de cada escenario en la MISMA conexion A,
-- pues :id_exito, :id_rollback y :id_savepoint son variables de psql.
-- Cualquier bloque no ejecutado se omite automaticamente.
\set ON_ERROR_STOP on
\set ECHO queries
\pset pager off
\echo 'VALIDACIONES FINALES (SIN MODIFICAR DATOS)'
-- Identificar servidor/sesion y aislamiento.
SELECT pg_backend_pid() AS pid_actual, current_database() AS base,
       current_setting('server_version') AS version,
       current_setting('default_transaction_isolation') AS aislamiento_default;

\if :{?id_exito}
  \echo 'Validacion venta confirmada ID ' :id_exito
  -- Esperado: 1 factura, 3 detalles y total coincidente.
  SELECT i.invoice_id, i.billing_address, i.total,
         COUNT(il.invoice_line_id) AS detalles,
         SUM(il.unit_price*il.quantity)::numeric(10,2) AS suma,
         i.total=SUM(il.unit_price*il.quantity) AS coincide
  FROM invoice i JOIN invoice_line il ON il.invoice_id=i.invoice_id
  WHERE i.invoice_id=:id_exito
  GROUP BY i.invoice_id, i.billing_address, i.total;
  -- Mostrar las canciones facturadas y sus subtotales.
  SELECT il.invoice_line_id, t.name AS cancion, il.quantity,
         il.unit_price, (il.unit_price*il.quantity)::numeric(10,2) AS subtotal
  FROM invoice_line il JOIN track t ON t.track_id=il.track_id
  WHERE il.invoice_id=:id_exito ORDER BY il.invoice_line_id;
\else
  \echo 'Escenario 1 sin ejecutar en esta sesion: omitido.'
\endif

\if :{?id_rollback}
  \echo 'Validacion rollback ID ' :id_rollback
  -- Esperado: ambas cantidades 0, usando el ID obtenido ANTES del ROLLBACK.
  SELECT :id_rollback AS factura_revertida,
         (SELECT COUNT(*) FROM invoice WHERE invoice_id=:id_rollback) AS cabeceras,
         (SELECT COUNT(*) FROM invoice_line WHERE invoice_id=:id_rollback) AS detalles;
\else
  \echo 'Escenario 2 sin ejecutar en esta sesion: omitido.'
\endif

\if :{?id_savepoint}
  \echo 'Validacion savepoint ID ' :id_savepoint
  -- Esperado: 3 detalles, 0 invalidos, total coincidente.
  SELECT i.invoice_id, i.total, COUNT(il.invoice_line_id) AS detalles,
         COUNT(il.invoice_line_id) FILTER (WHERE il.track_id=-1) AS invalidos,
         SUM(il.unit_price*il.quantity)::numeric(10,2) AS suma,
         i.total=SUM(il.unit_price*il.quantity) AS coincide
  FROM invoice i JOIN invoice_line il ON il.invoice_id=i.invoice_id
  WHERE i.invoice_id=:id_savepoint GROUP BY i.invoice_id,i.total;
  -- Mostrar que las canciones conservadas/corregida tienen IDs existentes.
  SELECT il.invoice_line_id, il.track_id, t.name AS cancion,
         il.quantity, il.unit_price
  FROM invoice_line il JOIN track t ON t.track_id=il.track_id
  WHERE il.invoice_id=:id_savepoint ORDER BY il.invoice_line_id;
\else
  \echo 'Escenario 3 sin ejecutar en esta sesion: omitido.'
\endif
