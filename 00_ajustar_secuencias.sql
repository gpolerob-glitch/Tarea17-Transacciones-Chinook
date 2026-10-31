-- TAREA 17 | Preparacion unica posterior a la importacion en chinook_t17.
-- La variante SerialPKs usa secuencias para claves de invoice e invoice_line.
-- Sin insertar claves manualmente, se posicionan tras los IDs ya importados.
-- No se elimina ni modifica ninguna factura original; solo secuencias.
\set ON_ERROR_STOP on
\set ECHO queries
\pset pager off

-- Verificar que existen las secuencias y datos de las tablas originales.
-- Esperado: dos nombres de secuencia y cantidades mayores que cero.
SELECT pg_get_serial_sequence('invoice', 'invoice_id') AS secuencia_factura,
       pg_get_serial_sequence('invoice_line', 'invoice_line_id') AS secuencia_detalle,
       (SELECT COUNT(*) FROM invoice) AS facturas_originales,
       (SELECT COUNT(*) FROM invoice_line) AS detalles_originales;

-- Cada siguiente INSERT usara nextval() y RETURNING, nunca MAX(id) + 1.
-- ORDER BY DESC LIMIT 1 solo identifica el ultimo registro importado.
SELECT setval(pg_get_serial_sequence('invoice', 'invoice_id'),
              (SELECT invoice_id FROM invoice ORDER BY invoice_id DESC LIMIT 1), true)
       AS ultimo_id_factura;
SELECT setval(pg_get_serial_sequence('invoice_line', 'invoice_line_id'),
              (SELECT invoice_line_id FROM invoice_line ORDER BY invoice_line_id DESC LIMIT 1), true)
       AS ultimo_id_detalle;

-- Resultado esperado: secuencias alineadas con los datos cargados.
-- No usar nextval() en la validacion: consumirlo crearia un salto innecesario.
