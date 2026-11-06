<#
  Lanza N ejecuciones de Newman en paralelo (por defecto 10) contra la Azure Function
  y genera un resumen (consola + results\summary.csv).

  Uso (desde la carpeta postman):
    .\run-concurrent.ps1                                  # 10 peticiones, nth=1000000, funcion Fibonacci
    .\run-concurrent.ps1 -N 10 -Nth 1000000 -Function FibonacciMemo
#>
param(
    [int]$N = 10,
    [int]$Nth = 1000000,
    [string]$Function = "Fibonacci"
)

$ErrorActionPreference = "Stop"
$root       = Split-Path -Parent $MyInvocation.MyCommand.Path
$collection = Join-Path $root "ARSW_Fibonacci.postman_collection.json"
$envFile    = Join-Path $root "ARSW_Fibonacci.postman_environment.json"
$stamp      = Get-Date -Format "yyyyMMdd-HHmmss"
$out        = Join-Path $root "results\$Function-nth$Nth-$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null

if (-not (Get-Command newman -ErrorAction SilentlyContinue)) {
    Write-Error "Newman no esta instalado. Ejecute: npm install -g newman"
}

Write-Host "Lanzando $N peticiones concurrentes -> funcion '$Function', nth=$Nth" -ForegroundColor Cyan
$start = Get-Date

$procs = 1..$N | ForEach-Object {
    $nargs = @(
        "/c", "newman", "run", "`"$collection`"",
        "-e", "`"$envFile`"",
        "--env-var", "nth=$Nth",
        "--env-var", "function=$Function",
        "--timeout-request", "240000",
        "-r", "cli,json",
        "--reporter-json-export", "`"$out\run-$_.json`""
    )
    Start-Process -FilePath "cmd.exe" -ArgumentList $nargs -NoNewWindow -PassThru `
        -RedirectStandardOutput "$out\run-$_.log" -RedirectStandardError "$out\run-$_.err.log"
}

$procs | Wait-Process
$wall = ((Get-Date) - $start).TotalSeconds

# ---- Resumen ----
$rows = foreach ($i in 1..$N) {
    $file = "$out\run-$i.json"
    if (-not (Test-Path $file)) {
        [pscustomobject]@{ Peticion = $i; Status = "SIN REPORTE"; TiempoMs = $null; Error = "ver run-$i.err.log" }
        continue
    }
    $j = Get-Content $file -Raw | ConvertFrom-Json
    $ex = $j.run.executions[0]
    if ($ex.requestError) {
        [pscustomobject]@{ Peticion = $i; Status = "ERROR"; TiempoMs = $null; Error = $ex.requestError.message }
    } else {
        [pscustomobject]@{ Peticion = $i; Status = $ex.response.code; TiempoMs = $ex.response.responseTime; Error = "" }
    }
}

$rows | Format-Table -AutoSize
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 "$out\summary.csv"

$ok    = @($rows | Where-Object { $_.Status -eq 200 })
$times = $ok | ForEach-Object { [double]$_.TiempoMs }
Write-Host ("Exitosas: {0}/{1}" -f $ok.Count, $N) -ForegroundColor Green
if ($times.Count -gt 0) {
    $m = $times | Measure-Object -Minimum -Maximum -Average
    Write-Host ("Tiempo de respuesta (ms)  min={0:N0}  prom={1:N0}  max={2:N0}" -f $m.Minimum, $m.Average, $m.Maximum)
}
Write-Host ("Tiempo total (reloj) de las {0} peticiones: {1:N1} s" -f $N, $wall)
Write-Host "Reportes en: $out"
