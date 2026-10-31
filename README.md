# Tarea 17 — Control transaccional de ventas en Chinook

**Estudiante:** Gabriel Polero  
**Carné:** 2890-24-8909  
**Motor:** PostgreSQL 18  
**Base de práctica:** `chinook_t17`  
**Fuente del conjunto de datos:** Chinook 1.4.5, variante `Chinook_PostgreSql_SerialPKs.sql`

## 1. Descripción del caso

Se registra una venta de canciones mediante las tablas originales `customer`, `track`, `invoice` e `invoice_line`. Cada factura tiene un cliente, una fecha y un total que debe ser igual a la suma de `unit_price × quantity` de sus detalles. La operación se comprueba en cuatro situaciones: confirmación, reversión completa por clave foránea inválida, recuperación parcial mediante punto de guardado y visibilidad de una transacción entre dos sesiones independientes.

Se utiliza una base local de práctica. Las ventas nuevas se identifican mediante el texto `T17 PRACTICA` en `billing_address`; los valores del resto de datos de facturación se toman de un cliente existente. No se alteran ni se eliminan facturas originales. Los precios de venta se toman de canciones existentes; las cantidades de los detalles insertados son positivas. No se agregan tablas de inventario.

## 2. Requisitos y fuentes

Requisitos: Docker Desktop, Docker Compose, PowerShell de Windows y una conexión a Internet para obtener el script de Chinook. El servicio usa la imagen `postgres:18` y publica el puerto **5434** en el equipo anfitrión para evitar conflictos con otro PostgreSQL local. La versión exacta del servidor se registra al ejecutar `SELECT version()`.

Fuentes oficiales consultadas:

- [Chinook, repositorio oficial](https://github.com/lerocha/chinook-database)
- [Chinook, variante PostgreSQL con SERIAL](https://raw.githubusercontent.com/lerocha/chinook-database/master/ChinookDatabase/DataSources/Chinook_PostgreSql_SerialPKs.sql)
- [PostgreSQL 18, transacciones](https://www.postgresql.org/docs/18/tutorial-transactions.html)
- [PostgreSQL 18, aislamiento](https://www.postgresql.org/docs/18/transaction-iso.html)

El proyecto utiliza el formato de datos Chinook 1.4.5; se recomienda verificar la versión declarada en el encabezado del archivo descargado porque el enlace remite a la rama principal del repositorio oficial.

## 3. Inicio del entorno

Desde **PowerShell**, situado en la carpeta que contiene este README:

```powershell
Copy-Item .env.example .env
notepad .env
```

Se sustituye el valor `CAMBIAR_POR_CLAVE_PRIVADA` de `POSTGRES_PASSWORD` por una clave local. No se sube el archivo `.env` al repositorio. La plantilla `.env.example` no contiene contraseñas reales.

A continuación:

```powershell
docker compose up -d
docker compose ps
docker compose exec db psql -U postgres -d postgres -c "SELECT version();"
```

El servidor de este proyecto usa un volumen propio. La instrucción `docker compose down` detiene los servicios sin borrar los datos. La opción `down -v` **elimina** el volumen y no debe utilizarse si se desean conservar las pruebas realizadas.

## 4. Preparación e importación de Chinook

**Advertencia:** el script original de Chinook incluye instrucciones para eliminar y crear una base de datos y una metaorden de conexión de `psql`. No se ejecuta directamente sobre un servidor con información que deba conservarse.

Primero se descarga el archivo oficial y se genera una copia para importación en una base previamente creada:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\00_preparar_importacion.ps1
Get-Content .\origen\Chinook_PostgreSql_SerialPKs.sql -TotalCount 45
```

El script `00_preparar_importacion.ps1` **no ejecuta SQL** ni elimina bases. Conserva intacto el original en `origen/Chinook_PostgreSql_SerialPKs.sql` y crea `origen/Chinook_practica_import.sql`. En la copia se omiten únicamente las tres instrucciones de administración de base de datos (`DROP DATABASE`, `CREATE DATABASE` y `\c`/`\connect`); el resto del esquema y de los datos corresponde a la variante oficial. La preparación se detiene si no reconoce dichas instrucciones o las tablas de ventas.

Después de revisar esas instrucciones, se crea una base nueva con nombre dedicado y se importa la copia preparada:

```powershell
docker compose exec -T db psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE chinook_t17;"
docker compose exec -T db psql -X -U postgres -d chinook_t17 -v ON_ERROR_STOP=1 -f /workspace/origen/Chinook_practica_import.sql
```

Si `chinook_t17` ya existe, se reutiliza únicamente si es la copia de práctica correspondiente. No se vuelve a crear ni a importar encima de datos existentes sin inspeccionarlos. El archivo original permanece disponible para cotejarlo con la copia.

Alinear las secuencias de las claves seriales después de cargar las filas originales:

```powershell
docker compose exec -T db psql -X -U postgres -d chinook_t17 -v ON_ERROR_STOP=1 -f /workspace/00_ajustar_secuencias.sql
```

Esta operación no calcula manualmente identificadores para ventas. Solo coloca las secuencias tras los últimos identificadores de la importación para que `INSERT ... RETURNING` funcione correctamente sobre el conjunto preexistente.

Verificar que la importación generó el modelo esperado:

```powershell
docker compose exec db psql -U postgres -d chinook_t17 -c "SELECT COUNT(*) AS clientes FROM customer; SELECT COUNT(*) AS canciones FROM track; SELECT COUNT(*) AS facturas FROM invoice; SELECT COUNT(*) AS detalles FROM invoice_line;"
```

**Referencia esperada del conjunto original:** 59 clientes, 3,503 canciones, 412 facturas y 2,240 detalles. Los valores reales se registran con la consulta anterior. En caso de error de importación, no se ejecutan los escenarios hasta corregir el entorno.

## 5. Conexiones independientes A y B

Abrir **dos ventanas** de PowerShell. En cada una, desde la misma carpeta:

```powershell
docker compose exec db psql -X -U postgres -d chinook_t17
```

En la consola `psql` de cada conexión:

```sql
\set AUTOCOMMIT on
\echo :AUTOCOMMIT
SELECT pg_backend_pid() AS pid,
       current_database() AS base,
       current_setting('default_transaction_isolation') AS aislamiento_predeterminado,
       current_setting('server_version') AS version;
```

Los resultados deben mostrar **PID diferentes** para A y B. `AUTOCOMMIT on` significa que las sentencias independientes se confirman automáticamente. En los scripts, las transacciones se delimitan expresamente con `BEGIN ISOLATION LEVEL READ COMMITTED` y `COMMIT`/`ROLLBACK`. El nivel vigente dentro de las transacciones también se consulta desde los scripts.

**Importante:** los scripts contienen metaórdenes de `psql` (`\gset`, `\if`, `\prompt` y `\echo`). Deben ejecutarse con `psql`, no pegando todo el archivo como SQL puro en DataGrip.

## 6. Ejecución de escenarios

Las rutas siguientes se escriben **dentro de psql** de cada conexión. Cada escenario obtiene sus claves con `RETURNING`; ninguno requiere un número de factura supuesto y ninguno depende de haber ejecutado antes los otros dos.

### 6.1. Venta exitosa y visibilidad A/B

1. **A:** `\i /workspace/01_venta_exitosa.sql`.
2. **A:** comprobar el identificador mostrado, las tres líneas insertadas y que `cumple = t`. El script espera una respuesta en `\prompt` **antes** de efectuar `COMMIT`; no se presiona Enter todavía.
3. **B:** `\i /workspace/05_sesion_B_antes.sql`. Introducir el **ID real** impreso en A. La consulta debe mostrar `cabeceras_visibles = 0` y `detalles_visibles = 0`. Registrar una captura con el PID de B y el aislamiento `read committed`.
4. **A:** presionar Enter para continuar el script y confirmar la venta con `COMMIT` explícito.
5. **B:** `\i /workspace/06_sesion_B_despues.sql` **sin cerrar la sesión B**. Se esperan `cabeceras_visibles = 1`, `detalles_visibles = 3` y `coincide = t`.

La sesión B mantiene su misma transacción `READ COMMITTED` entre las dos consultas. En ese nivel, cada sentencia inicia una nueva instantánea de datos confirmados, por lo que B observa la factura tras el `COMMIT` de A.

Si el escenario 1 se prueba sin B, se puede continuar el `\prompt` para confirmar, pero esa ejecución por sí sola **no acredita** el requisito de visibilidad; la demostración A/B deberá repetirse.

### 6.2. Error de FOREIGN KEY y ROLLBACK completo

**A:**

```sql
\i /workspace/02_rollback_total.sql
```

El script verifica que la canción `track_id = -1` no existe; crea **otra factura** y un detalle válido; intenta agregar un detalle con esa canción inexistente. Se espera un error de clave foránea **SQLSTATE 23503** y, en una consulta posterior, el estado abortado **SQLSTATE 25P02**. Después ejecuta `ROLLBACK` y comprueba por el identificador obtenido con `RETURNING` que permanecen **0 cabeceras y 0 detalles**.

La opción `ON_ERROR_STOP` de `psql` se desactiva temporalmente para mostrar ambos errores y permitir la recuperación programada. Se vuelve a activar después del `ROLLBACK`. Si un cliente externo detiene el archivo en el primer error, debe ejecutarse `ROLLBACK;` **en esa misma conexión** y luego la consulta de ausencia correspondiente al identificador capturado; sin ello la prueba queda incompleta.

### 6.3. Recuperación parcial con SAVEPOINT

**A:**

```sql
\i /workspace/03_savepoint.sql
```

Se crea una tercera factura con **dos detalles válidos**. A continuación se define `SAVEPOINT antes_del_error`, se intenta agregar `track_id = -1` y se produce el error `23503`. La sentencia `ROLLBACK TO SAVEPOINT antes_del_error` permite continuar la transacción conservando los dos detalles anteriores. Se agrega una tercera canción existente, se recalcula el total a partir de los detalles y se ejecuta `COMMIT`.

Resultados esperados: **2 detalles conservados** tras la recuperación, **0 detalles inválidos**, **3 detalles al final** y total de la factura exactamente igual a la suma calculada. `RELEASE SAVEPOINT` elimina el punto de guardado, pero no confirma la venta: solamente `COMMIT` hace definitivos los cambios de la transacción completa.

### 6.4. Validaciones finales

**A, tras completar los escenarios ejecutados en esa misma sesión:**

```sql
\i /workspace/04_validaciones.sql
```

Se muestran los detalles, canciones, subtotales y totales de las operaciones confirmadas. Se comprueba también la ausencia de la factura revertida con su clave real. Las pruebas que no se ejecutaron en esa sesión se omiten sin producir errores. Los escenarios pueden repetirse de manera independiente y crean nuevas facturas de práctica sin borrar otras.

## 7. Resultado esperado por criterio

| Escenario | Comprobación esperada | Archivos |
| --- | --- | --- |
| Venta confirmada | Una cabecera, tres detalles, cantidades positivas, total calculado, `cumple = t`, `COMMIT` | `01_venta_exitosa.sql`, `04_validaciones.sql` |
| Reversión total | FK `23503`, error de transacción abortada `25P02`, y después de `ROLLBACK` cero cabeceras y detalles | `02_rollback_total.sql` |
| SAVEPOINT | Dos líneas válidas conservadas, línea inválida ausente, tercera línea corregida, total coincidente y `COMMIT` | `03_savepoint.sql` |
| Visibilidad | PIDs distintos; antes de `COMMIT` B consulta 0/0; después consulta 1/3 con `READ COMMITTED` | `05_sesion_B_antes.sql`, `06_sesion_B_despues.sql` |

**Los valores anteriores son resultados esperados, no resultados obtenidos.** La acreditación se realiza mediante las capturas y salidas reales de PostgreSQL incluidas en el PDF.

## 8. Explicación técnica: propiedades ACID

**Atomicidad.** Las sentencias de una venta quedan dentro de una transacción. Si se confirma, la factura y todos sus detalles permanecen; si se ejecuta `ROLLBACK`, se revierte tanto la cabecera como sus detalles. `SAVEPOINT` permite deshacer solamente una parte.

**Consistencia.** La clave foránea entre `invoice_line.track_id` y `track.track_id` bloquea la canción inexistente. El total se calcula con `NUMERIC` mediante `SUM(unit_price * quantity)` y se compara con el total almacenado antes de confirmar. No se supone que el esquema original tenga una restricción `CHECK` de cantidad positiva ni una restricción automática que mantenga la igualdad del total: ambas condiciones se comprueban explícitamente en esta práctica.

**Aislamiento.** Los PIDs diferentes demuestran que se usaron sesiones distintas. En `READ COMMITTED`, B no ve los cambios sin confirmar de A; una nueva consulta de B los puede ver después de `COMMIT`.

**Durabilidad.** La consulta posterior a `COMMIT` permite observar que los datos confirmados permanecen disponibles en la base durante las pruebas. Esta evidencia **no constituye una prueba completa de recuperación ante un fallo físico** del equipo, del almacenamiento o del servidor.

**Autocommit y estado abortado.** Con autocommit activado, una sentencia independiente se confirma al terminar correctamente; dentro de `BEGIN`, los cambios no se hacen definitivos hasta `COMMIT`. Una violación de clave foránea aborta la transacción actual y las sentencias posteriores reciben `25P02` hasta ejecutar `ROLLBACK` o regresar a un `SAVEPOINT` válido.

**Secuencias y huecos.** Las claves `SERIAL` utilizan secuencias. Un valor entregado por una secuencia no se devuelve al hacer `ROLLBACK`, así que pueden existir saltos entre IDs. Dichos saltos no significan que quedaron facturas incompletas ni que se haya calculado una clave manualmente.

## 9. Evidencias y entrega

Se entrega **un único PDF** en Canvas, con identificación, URL accesible del repositorio GitHub, matriz de escenarios (esperado/obtenido/captura), capturas legibles y explicaciones. Como mínimo se documentan: versión de PostgreSQL e importación, PID/autocommit/aislamiento de A y B, cálculo de total y `COMMIT`, error de FK y estado abortado, ausencia posterior a `ROLLBACK`, recuperación con `SAVEPOINT`, y visibilidad de B antes/después de confirmar. Cada captura indica escenario, conexión y lo que demuestra.

En el repositorio GitHub se publican el presente README, los archivos SQL y la configuración sin secretos. **No** se publican `.env`, contraseñas, credenciales ni archivos personales. La URL del repositorio se registra en el PDF una vez creado. No se entregan archivos SQL sueltos en Canvas; no se solicita video.

## 10. Archivos

| Archivo | Finalidad |
| --- | --- |
| `00_preparar_importacion.ps1` | Descarga y prepara una copia segura del script oficial |
| `00_ajustar_secuencias.sql` | Alinea las secuencias de claves importadas sin generar IDs manualmente |
| `01_venta_exitosa.sql` | Venta, cálculo de total, validación y confirmación |
| `02_rollback_total.sql` | FK inexistente, transacción abortada y reversión total |
| `03_savepoint.sql` | Error controlado, retroceso parcial, corrección y confirmación |
| `04_validaciones.sql` | Comprobaciones de las tres operaciones por sus claves reales |
| `05_sesion_B_antes.sql` | Lectura antes de confirmar desde una conexión distinta |
| `06_sesion_B_despues.sql` | Lectura después de confirmar desde la misma conexión B |
| `docker-compose.yml` | Instancia aislada de PostgreSQL 18 con volumen local |
| `.env.example` y `.gitignore` | Plantilla de configuración y protección de secretos |

El directorio `origen/` se genera localmente durante la preparación y no forma parte del repositorio: contiene el script oficial y su copia adaptada, que pueden volver a obtenerse mediante `00_preparar_importacion.ps1`.
