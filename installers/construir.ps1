# construir.ps1 -- compila el instalador de FoxPack (FoxPack.iss)
#
# Uso:  powershell -File installers\construir.ps1            (sin firmar, para probar)
#       powershell -File installers\construir.ps1 -Firmar    (la build que se publica)
#
# LA FIRMA, el mismo patron que FoxAgent (installers\Build-Installer.ps1 de su repo):
#   - Lo NUESTRO se firma en dist\, donde esta, ANTES de empaquetar: foxpack.exe (el host
#     de FoxCli con el nombre de la CLI), foxpack.dll y Nexum.dll. Un binario sin firma
#     dentro de un setup firmado es justo el que dispara el antivirus en casa de otro.
#   - El runtime de VFP (vfp9r.dll, msvcr71.dll, VFP9RENU.DLL, vfp9resn.dll) es de
#     Microsoft y NO se firma: firmar un binario ajeno seria responder de el.
#   - Inno firma el setup y el desinstalador con la SignTool 'firmar' del .iss, que solo
#     se activa con /DFirmar.
#   Firma Golem\tools\firmar.ps1 (certificado SSL.com IV de Irwin). Si un fichero ya lleva
#   nuestra firma valida no lo vuelve a firmar, y eso no gasta cuota de eSigner.
#
# EL SELLO no se rompe al firmar: va en foxpack.exe.commands.txt (linea sel|), no en el
# .exe, y el host no mira el hash de su propio binario.
#
# Fichero en ASCII (regla 7 de tooling-rules.md).

[CmdletBinding()]
param([switch]$Firmar)

$ErrorActionPreference = 'Stop'
$root      = Split-Path -Parent $PSScriptRoot
$dist      = Join-Path $root 'dist'
$iss       = Join-Path $PSScriptRoot 'FoxPack.iss'
$iscc      = 'C:\Programas\Inno Setup 7\ISCC.exe'
$firmarPs1 = 'C:\Desarrollo\IrwinRodriguez.dev\Golem\tools\firmar.ps1'

$nuestros = @('foxpack.exe', 'foxpack.dll', 'Nexum.dll')

if (-not (Test-Path $iscc)) { Write-Error "No esta $iscc"; exit 1 }

# La version, de donde la lee el .iss: la linea ver| del manifiesto.
$man = Join-Path $dist 'foxpack.exe.commands.txt'
if (-not (Test-Path $man)) { Write-Error "No esta ${man}: compila la CLI antes"; exit 1 }
$version = ((Get-Content $man | Where-Object { $_ -like 'ver|*' } | Select-Object -First 1) -replace '^ver\|', '').Trim()
if ($version -eq '') { Write-Error "$man no trae la version (ver|)"; exit 1 }

# Sin sello, FoxPack diria "unlicensed" en cada llamada: no se publica asi.
if (-not (Get-Content $man | Where-Object { $_ -like 'sel|*' })) {
    Write-Error "NO SE COMPILA: ${man} no lleva el sello (sel|). Compila con FoxForge y la licencia de FoxCli"
    exit 1
}

if ($Firmar) {
    if (-not (Test-Path $firmarPs1)) { Write-Error "No esta $firmarPs1"; exit 1 }
    '== firma de lo nuestro, en dist\'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $firmarPs1 @($nuestros | ForEach-Object { Join-Path $dist $_ })
    if ($LASTEXITCODE -ne 0) { Write-Error "NO SE COMPILA: la firma fallo (ver arriba)"; exit 1 }

    $mal = @()
    foreach ($n in $nuestros) {
        $f = Get-AuthenticodeSignature (Join-Path $dist $n)
        $ok = $f.Status -eq 'Valid' -and $f.SignerCertificate.Subject -like '*Irwin Alfredo Rodriguez Gimenez*' -and $null -ne $f.TimeStamperCertificate
        '{0,-14} firma={1} {2}' -f $n, $f.Status, $(if ($ok) { 'OK' } else { 'SIN NUESTRA FIRMA' })
        if (-not $ok) { $mal += $n }
    }
    if ($mal.Count -gt 0) { Write-Error ("NO SE COMPILA: sin nuestra firma -> " + ($mal -join ', ')); exit 1 }
    ''
    # $q y $f los sustituye Inno (comilla y fichero a firmar); en PowerShell, entre comillas simples.
    & $iscc /Q /DFirmar ('/Sfirmar=powershell.exe -NoProfile -ExecutionPolicy Bypass -File $q' + $firmarPs1 + '$q $f') $iss
} else {
    & $iscc /Q $iss
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$out = Join-Path $PSScriptRoot "output\FoxPack-Setup-$version.exe"
'{0} {1} {2}' -f $out, (Get-Item $out).Length, (Get-FileHash $out -Algorithm SHA256).Hash

if ($Firmar) {
    $f = Get-AuthenticodeSignature $out
    if ($f.Status -ne 'Valid' -or $null -eq $f.TimeStamperCertificate) { Write-Error "el setup no salio firmado: $($f.Status)"; exit 1 }
    'setup firmado: ' + $f.SignerCertificate.Subject.Split(',')[0]
}
