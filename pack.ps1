# pack.ps1 -- arma el zip de despliegue de foxpack
# Generado por FoxForge el 09/25/26 02:40:47 PM
#
# dist\ es donde se COMPILA, y ahi queda todo: los binarios que hacen falta
# para ejecutar, los subproductos del BUILD DLL y el host generico sin
# renombrar. Este script separa una cosa de la otra, para que lo que se copia
# a un puesto sea exactamente lo que ese puesto necesita.
#
# LO QUE VA (y por que):
#
#   foxpack.exe                el host, con el nombre de tu CLI
#   foxpack.dll                tu codigo VFP, compilado como servidor COM
#   foxpack.exe.manifest       activa el COM SIN registro: por eso el
#                                despliegue es un xcopy y no pide administrador
#   foxpack.exe.commands.txt   el manifiesto de comandos, de donde salen el
#                                parseo, la validacion y el --help
#   el runtime de VFP, el de QUIEN COMPILO tu DLL (se mira lo que importa):
#     VFP 9:          vfp9r.dll + msvcr71.dll
#     VFP Advanced:   VFPAR.DLL + msvcr100.dll
#   VFP9RENU.DLL · vfp9resn.dll  sus recursos, los mismos para los dos
#
#   El msvcr lo IMPORTAN el runtime y tu propia DLL. En una maquina con VFP
#   instalado lo aporta el sistema y no se nota que falta; en una sin VFP, sin
#   el no arranca nada.
#
# LO QUE NO VA (y por que):
#
#   foxcli-host.exe   es el MISMO binario que foxpack.exe, sin renombrar. Se
#                     queda en el proyecto para poder recompilar sin FoxForge
#                     delante, pero en un puesto son 40 KB de un segundo
#                     ejecutable a un guion de distancia del bueno.
#   foxpack.tlb     la type library, y el registro para regsvr32. Solo hacen
#   foxpack.VBR     falta para registrar o importar el COM, que aqui no se
#                     hace: la activacion es por manifiesto.
#   src\main.FXP      el compilado de tu fuente. Un .FXP GANA al .prg de al
#                     lado sin avisar ni mirar fechas, asi que distribuirlo es
#                     distribuir la forma de un problema.
#
# Uso:  .\pack.ps1                    -> foxpack-dist.zip junto al proyecto
#       .\pack.ps1 -Out C:\ruta.zip

[CmdletBinding()]
param(
    [string]$Out = ""
)

$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$dist = Join-Path $root "dist"
if ($Out -eq "") { $Out = Join-Path $root "foxpack-dist.zip" }

# Que runtime: el que IMPORTA la DLL. Una de VFP Advanced importa MSVCR100;
# una de VFP 9, no (su msvcr71 lo trae vfp9r.dll).
$runtime = @("vfp9r.dll", "msvcr71.dll")
$dll = Join-Path $dist "foxpack.dll"
if (Test-Path $dll) {
    $texto = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($dll)).ToUpper()
    if ($texto.Contains("MSVCR100.DLL")) { $runtime = @("VFPAR.DLL", "msvcr100.dll") }
}

$necesarios = @(
    "foxpack.exe",
    "foxpack.dll",
    "foxpack.exe.manifest",
    "foxpack.exe.commands.txt",
    "VFP9RENU.DLL",
    "vfp9resn.dll"
) + $runtime

$faltan = @()
foreach ($f in $necesarios) {
    if (-not (Test-Path (Join-Path $dist $f))) { $faltan += $f }
}
if ($faltan.Count -gt 0) {
    throw ("Faltan en dist\: " + ($faltan -join ", ") + ". Compila la CLI antes de empaquetar.")
}

$stage = Join-Path ([IO.Path]::GetTempPath()) ("foxpack-pack-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $stage | Out-Null
foreach ($f in $necesarios) { Copy-Item (Join-Path $dist $f) $stage -Force }

if (Test-Path $Out) { Remove-Item $Out -Force }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $Out
Remove-Item $stage -Recurse -Force

Write-Host ("{0} ficheros -> {1} ({2:N0} bytes)" -f $necesarios.Count, $Out, (Get-Item $Out).Length)
Write-Host "Se despliega descomprimiendo: no hace falta registrar nada ni ser administrador."
