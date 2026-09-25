# tests\smoke.ps1 -- FoxPack por fuera: el foxpack.exe compilado, como lo usa
# una persona, contra proyectos de prueba en una carpeta temporal.
#
#   powershell -ExecutionPolicy Bypass -File tests\smoke.ps1
#   powershell -ExecutionPolicy Bypass -File tests\smoke.ps1 -Filter verify
#
# Las piezas de dentro (Huella, Candado) tienen sus tests en
# tests\FoxPackProofTests.prg, con FoxProof. Aqui va lo que solo se ve con la
# CLI entera: exit codes, stdout contra stderr y --format json.
#
# Fichero en ASCII: PowerShell 5.1 no lee bien un .ps1 con acentos.

[CmdletBinding()]
param([string]$Filter = "")

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$exe  = Join-Path $root "dist\foxpack.exe"
if (-not (Test-Path $exe)) { Write-Host "No existe $exe. Compila antes (Ctrl+F7)." -ForegroundColor Red; exit 1 }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("foxpack-smoke-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$script:pass = 0; $script:fail = 0; $script:skip = 0; $script:fallos = @()

function Invoke-Fp {
    param([string[]]$FpArgs, [string]$Dir, [int]$TimeoutSec = 30)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = ($FpArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join " "
    $psi.WorkingDirectory = $Dir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = New-Object Text.UTF8Encoding $false
    $psi.StandardErrorEncoding = New-Object Text.UTF8Encoding $false
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if ($p.WaitForExit($TimeoutSec * 1000)) { $code = $p.ExitCode } else { $p.Kill(); $code = "COLGADO" }
    [PSCustomObject]@{ Out = $o.Result; Err = $e.Result; Code = $code }
}

# Un proyecto con jsonfox instalado y su candado al dia.
function New-Proyecto {
    param([string]$Nombre)
    $d = Join-Path $tmp $Nombre
    $lib = Join-Path $d "lib\jsonfox"
    New-Item -ItemType Directory -Force -Path $lib | Out-Null
    Copy-Item (Join-Path $root "src\JsonFox.prg") $lib
    $sha = (Get-FileHash (Join-Path $lib "JsonFox.prg") -Algorithm SHA256).Hash.ToLower()
    $lock = @(
        '{',
        '  "lockVersion": 1,',
        '  "libraries": [',
        '    {',
        '      "name": "jsonfox",',
        '      "repo": "Irwin1985/JSONFox",',
        '      "version": "13.1.1",',
        '      "commit": "0123456789abcdef0123456789abcdef01234567",',
        '      "files": [',
        ('        { "path": "JsonFox.prg", "sha256": "' + $sha + '" }'),
        '      ]',
        '    }',
        '  ]',
        '}'
    ) -join "`r`n"
    [IO.File]::WriteAllText((Join-Path $d "foxpack.lock"), $lock + "`r`n")
    return $d
}

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    if ($Filter -ne "" -and $Name -notlike "*$Filter*") { $script:skip++; return }
    try {
        $problema = & $Body
        if ([string]::IsNullOrEmpty($problema)) { $script:pass++; Write-Host ("  OK    " + $Name) -ForegroundColor DarkGray }
        else { $script:fail++; $script:fallos += "$Name -- $problema"; Write-Host ("  FALLO " + $Name + "`n        " + $problema) -ForegroundColor Red }
    } catch { $script:fail++; $script:fallos += "$Name -- excepcion: $_"; Write-Host ("  ERROR " + $Name + " -- " + $_) -ForegroundColor Red }
}

Write-Host ""
Write-Host "FoxPack -- smoke" -ForegroundColor Cyan
Write-Host ""

Test-Case "list sin foxpack.lock: nada instalado, exit 0" {
    $d = Join-Path $tmp "vacio"; New-Item -ItemType Directory -Force -Path $d | Out-Null
    $r = Invoke-Fp @("list") $d
    if ($r.Code -ne 0) { return "exit $($r.Code): $($r.Err)" }
    if ($r.Out -notmatch "No libraries installed") { return "stdout: [$($r.Out)]" }
}

Test-Case "list con una libreria, en tabla y en json" {
    $d = New-Proyecto "lista"
    $r = Invoke-Fp @("list") $d
    if ($r.Code -ne 0) { return "exit $($r.Code): $($r.Err)" }
    if ($r.Out -notmatch "jsonfox\s+13\.1\.1\s+Irwin1985/JSONFox\s+0123456") { return "tabla: [$($r.Out)]" }
    $r = Invoke-Fp @("list", "--format", "json") $d
    $j = $r.Out | ConvertFrom-Json
    if ($j.libraries.Count -ne 1 -or $j.libraries[0].name -ne "jsonfox" -or $j.libraries[0].files -ne 1) { return "json: [$($r.Out)]" }
}

Test-Case "verify: todo igual, exit 0" {
    $d = New-Proyecto "igual"
    $r = Invoke-Fp @("verify") $d
    if ($r.Code -ne 0) { return "exit $($r.Code): $($r.Err)" }
    if ($r.Out -notmatch "1 file\(s\) checked: all match") { return "stdout: [$($r.Out)]" }
}

Test-Case "verify: una copia tocada da exit 12 y dice cual" {
    $d = New-Proyecto "tocada"
    Add-Content -Path (Join-Path $d "lib\jsonfox\JsonFox.prg") -Value "* un arreglo a mano"
    $r = Invoke-Fp @("verify") $d
    if ($r.Code -ne 12) { return "exit $($r.Code), esperaba 12" }
    if ($r.Out -notmatch "changed\s+lib\\jsonfox\\JsonFox\.prg") { return "stdout: [$($r.Out)]" }
    if ($r.Err -notmatch "never edited") { return "stderr: [$($r.Err)]" }
    $r = Invoke-Fp @("verify", "--format", "json") $d
    $j = $r.Out | ConvertFrom-Json
    if ($j.differ -ne 1 -or $j.files[0].status -ne "changed") { return "json: [$($r.Out)]" }
}

Test-Case "verify: una copia que falta da exit 12" {
    $d = New-Proyecto "falta"
    Remove-Item (Join-Path $d "lib\jsonfox\JsonFox.prg")
    $r = Invoke-Fp @("verify") $d
    if ($r.Code -ne 12) { return "exit $($r.Code), esperaba 12" }
    if ($r.Out -notmatch "missing\s+lib\\jsonfox\\JsonFox\.prg") { return "stdout: [$($r.Out)]" }
}

Test-Case "-p apunta a otra carpeta" {
    $d = New-Proyecto "otra"
    $r = Invoke-Fp @("verify", "-p", $d) $tmp
    if ($r.Code -ne 0) { return "exit $($r.Code): $($r.Err)" }
}

Test-Case "una carpeta que no existe da exit 14" {
    $r = Invoke-Fp @("list", "-p", (Join-Path $tmp "no-existe")) $tmp
    if ($r.Code -ne 14) { return "exit $($r.Code), esperaba 14" }
    if ($r.Err -notmatch "does not exist") { return "stderr: [$($r.Err)]" }
}

Test-Case "un foxpack.lock roto da exit 14 con el motivo" {
    $d = Join-Path $tmp "roto"; New-Item -ItemType Directory -Force -Path $d | Out-Null
    [IO.File]::WriteAllText((Join-Path $d "foxpack.lock"), '{"broken')
    $r = Invoke-Fp @("list") $d
    if ($r.Code -ne 14) { return "exit $($r.Code), esperaba 14" }
    if ($r.Err -notmatch "foxpack.lock") { return "stderr: [$($r.Err)]" }
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
if ($script:fail -eq 0) { Write-Host "$($script:pass) casos, todos en verde." -ForegroundColor Green }
else {
    Write-Host "$($script:pass) OK, $($script:fail) FALLIDOS" -ForegroundColor Red
    foreach ($f in $script:fallos) { Write-Host "  - $f" -ForegroundColor Red }
}
if ($script:skip -gt 0) { Write-Host "$($script:skip) omitidos por -Filter" -ForegroundColor DarkGray }
if ($script:fail -gt 0) { exit 1 }
exit 0
