# Prepara una copia segura del script oficial para importarlo en chinook_t17.
# No ejecuta SQL ni elimina bases. El archivo original permanece intacto.
$ErrorActionPreference = 'Stop'
$dir = Join-Path $PSScriptRoot 'origen'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$original = Join-Path $dir 'Chinook_PostgreSql_SerialPKs.sql'
$salida = Join-Path $dir 'Chinook_practica_import.sql'
$fuente = 'https://raw.githubusercontent.com/lerocha/chinook-database/master/ChinookDatabase/DataSources/Chinook_PostgreSql_SerialPKs.sql'

# Descargar la variante SerialPKs de Chinook desde su repositorio oficial.
Invoke-WebRequest -Uri $fuente -OutFile $original
$contenido = [System.IO.File]::ReadAllText($original)
$lineas = [regex]::Split($contenido, '\r?\n')

# El script original administra la base y se reconecta mediante psql.
# Se excluyen UNICAMENTE esas tres instrucciones en una copia de trabajo.
# Así se importa el esquema y los datos en una base creada previamente,
# con nombre distinto al de las bases existentes del estudiante.
$patrones = @{
    drop = '^\s*DROP\s+DATABASE\s+IF\s+EXISTS\s+chinook_serial\s*;'
    create = '^\s*CREATE\s+DATABASE\s+chinook_serial\s*;'
    connect = '^\s*\\(?:c|connect)(?:\s|$)'
}
$contadores = @{ drop = 0; create = 0; connect = 0 }
$filtradas = New-Object 'System.Collections.Generic.List[string]'
foreach ($linea in $lineas) {
    $tipo = $null
    foreach ($clave in @('drop', 'create', 'connect')) {
        if ($linea -match $patrones[$clave]) { $tipo = $clave; break }
    }
    if ($null -ne $tipo) {
        $contadores[$tipo]++
        Write-Host ("Instruccion omitida en copia ($tipo): $linea")
    } else {
        $filtradas.Add($linea)
    }
}
foreach ($clave in @('drop', 'create', 'connect')) {
    if ($contadores[$clave] -ne 1) {
        throw "Revision necesaria: se esperaban 1 instruccion '$clave', pero hay $($contadores[$clave]). No se genera la copia."
    }
}
if ($contenido -notmatch '(?i)CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:"?public"?\.)?"?invoice"?' -or
    $contenido -notmatch '(?i)CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:"?public"?\.)?"?invoice_line"?') {
    throw 'No se reconocieron las tablas de ventas. Revisar el script oficial antes de importar.'
}
$utf8SinBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($salida, ($filtradas -join "`n"), $utf8SinBom)
Write-Host "Original conservado: $original"
Write-Host "Copia para importar: $salida"
Write-Host 'Antes de importar: revisar el encabezado del original y las instrucciones omitidas.'
