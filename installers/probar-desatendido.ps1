# installers\probar-desatendido.ps1 -- el instalador de FoxPack, sin nadie delante
#
# Instala con /VERYSILENT /SUPPRESSMSGBOXES en una carpeta de prueba, comprueba
# exe, registro, PATH y exit codes, desinstala igual y comprueba que el PATH del
# sistema queda EXACTAMENTE como estaba (en crudo: tipo REG_EXPAND_SZ y las
# %SystemRoot% sin expandir). Regla 13 de shared\vfp-rules\tooling-rules.md.
#
# OJO al medir la desinstalacion: unins000.exe se copia a %TEMP% y sale; la
# copia sigue trabajando despues, y quita la entrada del PATH al final
# (usPostUninstall). Leer el PATH en cuanto sale unins000.exe da un falso
# "no la ha quitado": se espera a que desaparezca, con plazo.
#
# Toca el registro y el PATH del sistema: hace falta administrador.
#
#   powershell -ExecutionPolicy Bypass -File installers\probar-desatendido.ps1
#
# Fichero en ASCII: PowerShell 5.1 no lee bien un .ps1 con acentos.

[CmdletBinding()]
param([string]$Dir = "C:\foxpack-prueba-desatendida")

$ErrorActionPreference = "Stop"
$setup = Get-ChildItem (Join-Path $PSScriptRoot "output\FoxPack-Setup-*.exe") | Sort-Object LastWriteTime | Select-Object -Last 1
if (-not $setup) { "No hay instalador en installers\output. Compila FoxPack.iss antes."; exit 1 }
$envKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
$regKey = "HKLM:\SOFTWARE\WOW6432Node\irwinrodriguez.dev\FoxPack"
$fallos = @()

function Get-PathCrudo {
    (Get-Item $envKey).GetValue("Path", $null, "DoNotExpandEnvironmentNames")
}

$antes = Get-PathCrudo
"Instalador: " + $setup.Name

$p = Start-Process $setup.FullName -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/DIR=$Dir" -PassThru
if (-not $p.WaitForExit(120000)) { $p.Kill(); "INSTALAR: se quedo parado (un dialogo esperando a nadie)"; exit 1 }
if ($p.ExitCode -ne 0) { $fallos += "instalar: exit $($p.ExitCode)" }
if (-not (Test-Path "$Dir\foxpack.exe")) { $fallos += "no instalo foxpack.exe" }
$reg = Get-ItemProperty $regKey -ErrorAction SilentlyContinue
if (-not $reg -or $reg.InstallDir -ne $Dir) { $fallos += "el registro no dice InstallDir=$Dir" }
if ((Get-PathCrudo) -split ";" -notcontains $Dir) { $fallos += "no esta en el PATH" }
$ver = & "$Dir\foxpack.exe" --version
if ($ver -notmatch "^foxpack \d") { $fallos += "foxpack --version: [$ver]" }
"instalado: $ver"

$u = Start-Process (Join-Path $Dir "unins000.exe") -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART" -PassThru
if (-not $u.WaitForExit(120000)) { $u.Kill(); "DESINSTALAR: se quedo parado"; exit 1 }
if ($u.ExitCode -ne 0) { $fallos += "desinstalar: exit $($u.ExitCode)" }
for ($i = 0; $i -lt 40 -and ((Get-PathCrudo) -ne $antes); $i++) { Start-Sleep -Milliseconds 500 }
if ((Get-PathCrudo) -ne $antes) { $fallos += "el PATH no ha vuelto a como estaba" }
if (Test-Path $regKey) { $fallos += "sigue la clave del registro" }
if (Test-Path "$Dir\foxpack.exe") { $fallos += "sigue foxpack.exe" }

if ($fallos.Count -eq 0) { "OK: instala y desinstala sin nadie delante, y el PATH queda como estaba"; exit 0 }
$fallos | ForEach-Object { "FALLO: $_" }
exit 1
