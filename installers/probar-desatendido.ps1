# installers\probar-desatendido.ps1 -- el instalador de FoxPack, sin nadie delante
#
# Reglas 13 y 14 de shared\vfp-rules\tooling-rules.md. Sin nadie delante
# (/VERYSILENT /SUPPRESSMSGBOXES /NORESTART):
#
#   1. Instala una version "vieja" en Program Files (x86)\FoxPack, como las de
#      antes de la regla 14.
#   2. Instala otra vez SIN /DIR: tiene que quitar la de Program Files e ir a
#      C:\Programas\FoxPack, con la carpeta CERRADA (sin herencia, usuarios
#      solo lectura y ejecucion, nada para "Usuarios autentificados").
#   3. Comprueba exe, registro, PATH (solo la carpeta nueva) y --version.
#   4. Desinstala y comprueba que el PATH del sistema queda en crudo como estaba.
#
# OJO al medir una desinstalacion: unins000.exe se copia a %TEMP% y sale; la
# copia sigue trabajando despues y quita la entrada del PATH al final
# (usPostUninstall). Leer el PATH en cuanto sale da un falso "no la ha
# quitado": se espera a que cambie, con plazo.
#
# Toca el registro y el PATH del sistema: hace falta administrador.
#
#   powershell -ExecutionPolicy Bypass -File installers\probar-desatendido.ps1
#
# Fichero en ASCII: PowerShell 5.1 no lee bien un .ps1 con acentos.

$ErrorActionPreference = "Stop"
$setup = Get-ChildItem (Join-Path $PSScriptRoot "output\FoxPack-Setup-*.exe") | Sort-Object LastWriteTime | Select-Object -Last 1
if (-not $setup) { "No hay instalador en installers\output. Compila FoxPack.iss antes."; exit 1 }
$envKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
$regKey = "HKLM:\SOFTWARE\WOW6432Node\irwinrodriguez.dev\FoxPack"
$vieja  = Join-Path ${env:ProgramFiles(x86)} "FoxPack"
$nueva  = Join-Path $env:SystemDrive "Programas\FoxPack"
$fallos = @()

function Get-PathCrudo { (Get-Item $envKey).GetValue("Path", $null, "DoNotExpandEnvironmentNames") }

function Invoke-Setup { param([string]$Exe, [string[]]$Extra = @())
    $p = Start-Process $Exe -ArgumentList (@("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART") + $Extra) -PassThru
    if (-not $p.WaitForExit(180000)) { $p.Kill(); "SE QUEDO PARADO: $Exe (un dialogo esperando a nadie)"; exit 1 }
    return $p.ExitCode
}

if ((Test-Path "$vieja\foxpack.exe") -or (Test-Path "$nueva\foxpack.exe")) {
    "Ya hay un FoxPack instalado ($vieja o $nueva). Desinstalalo antes de la prueba."; exit 1
}
$antes = Get-PathCrudo
"Instalador: " + $setup.Name

# 1. La "vieja", en Program Files
# Con comillas: Start-Process junta los argumentos con espacios y NO los
# entrecomilla, y "/DIR=C:\Program Files (x86)\FoxPack" llegaba como
# "/DIR=C:\Program" (medido: instalo en C:\Program).
$c = Invoke-Setup $setup.FullName @('/DIR="' + $vieja + '"')
if ($c -ne 0 -or -not (Test-Path "$vieja\foxpack.exe")) { "no se pudo poner la vieja en $vieja (exit $c)"; exit 1 }
"vieja en:  $vieja"

# 2. La nueva, sin /DIR
$c = Invoke-Setup $setup.FullName
if ($c -ne 0) { $fallos += "instalar: exit $c" }
if (Test-Path "$vieja\foxpack.exe") { $fallos += "no quito la de Program Files" }
if (-not (Test-Path "$nueva\foxpack.exe")) { $fallos += "no instalo en $nueva" }
"nueva en:  $nueva"

# 3. Lo instalado
$reg = Get-ItemProperty $regKey -ErrorAction SilentlyContinue
if (-not $reg -or $reg.InstallDir -ne $nueva) { $fallos += "el registro no dice InstallDir=$nueva" }
$entradas = (Get-PathCrudo) -split ";"
if ($entradas -notcontains $nueva) { $fallos += "la nueva no esta en el PATH" }
if ($entradas -contains $vieja) { $fallos += "la vieja sigue en el PATH" }
$ver = & "$nueva\foxpack.exe" --version
if ($ver -notmatch "^foxpack \d") { $fallos += "foxpack --version: [$ver]" }
# PLAN-FOXCLI-LICENCIA, pieza 5: FoxPack sale sellado a nombre de Irwin, y el sello
# solo lo lee el host si Nexum.dll esta instalado a su lado. Sin el, sale en evaluacion.
if ($ver -notmatch "licensed to Irwin Rodr") { $fallos += "el instalado no esta sellado (falta Nexum.dll?): [$ver]" }
"version:   $ver"

# La carpeta, cerrada (regla 14)
$acl = Get-Acl $nueva
if (-not $acl.AreAccessRulesProtected) { $fallos += "la carpeta sigue heredando permisos" }
foreach ($r in $acl.Access) {
    $sid = $r.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
    # Solo los bits que ESCRIBEN: WriteData 0x2, AppendData 0x4, WriteExtendedAttributes
    # 0x10, WriteAttributes 0x100, Delete 0x10000. Una mascara con Modify daba
    # positivo con ReadAndExecute, porque comparten Synchronize y los de lectura.
    $escribe = ([int]$r.FileSystemRights -band 0x10116) -ne 0
    if ($sid -eq "S-1-5-11") { $fallos += "Usuarios autentificados sigue en la carpeta ($($r.FileSystemRights))" }
    if ($sid -eq "S-1-5-32-545" -and $escribe) { $fallos += "los usuarios pueden escribir ($($r.FileSystemRights))" }
}
$acl.Access | ForEach-Object { "  permiso:  " + $_.IdentityReference + " " + $_.FileSystemRights }

# 4. Desinstalar
$c = Invoke-Setup (Join-Path $nueva "unins000.exe")
if ($c -ne 0) { $fallos += "desinstalar: exit $c" }
for ($i = 0; $i -lt 40 -and ((Get-PathCrudo) -ne $antes); $i++) { Start-Sleep -Milliseconds 500 }
if ((Get-PathCrudo) -ne $antes) { $fallos += "el PATH no ha vuelto a como estaba" }
if (Test-Path $regKey) { $fallos += "sigue la clave del registro" }
if (Test-Path "$nueva\foxpack.exe") { $fallos += "sigue foxpack.exe" }

if ($fallos.Count -eq 0) { "OK: migra de Program Files a C:\Programas, cierra la carpeta, y desinstala dejando el PATH como estaba"; exit 0 }
$fallos | ForEach-Object { "FALLO: $_" }
exit 1
