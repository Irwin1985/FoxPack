# construir.ps1 -- compila el instalador de FoxPack (FoxPack.iss)
#
# Uso:  powershell -File installers\construir.ps1            (sin firmar, para probar)
#       powershell -File installers\construir.ps1 -Firmar    (la build que se publica)
#
# LA FIRMA MINIMA (regla 19 de tooling-rules.md, 2026-10-05): cada firma de eSigner se
# paga, y se firma solo lo que el usuario descarga y ejecuta. Con -Firmar se firma UNA
# cosa: el setup (1 firma por publicacion), con la SignTool 'firmar' del .iss, que solo
# se activa con /DFirmar.
#   - Lo nuestro de dist\ (foxpack.exe, foxpack.dll, Nexum.dll) va SIN firma a proposito:
#     lo instala el setup firmado y no lleva Mark of the Web, asi que SmartScreen no lo mira.
#   - El runtime de VFP es de Microsoft y nunca se ha firmado.
#   - El desinstalador de Inno, tampoco (SignedUninstaller=no en FoxPack.iss).
#   - El setup de FoxStack que va dentro no hace falta que llegue firmado: aqui es interno.
#   Firma Golem\tools\firmar.ps1 -Publicar (certificado SSL.com IV de Irwin). Si un fichero
#   ya lleva nuestra firma valida no lo vuelve a firmar, y eso no gasta cuota de eSigner.
#
# EL SELLO va en foxpack.exe.commands.txt (linea sel|), no en el .exe, y el host no mira
# el hash de su propio binario.
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

# FoxStack, el que va dentro. Su firma solo se informa: dentro de este setup es interno y
# no hace falta (firma minima, regla 19 de tooling-rules.md).
$stackExe = Join-Path $root '..\FoxStack\installers\payload\foxstack.exe'
if (-not (Test-Path $stackExe)) { Write-Error "No esta ${stackExe}: construye FoxStack con su installers\construir.ps1"; exit 1 }
$stackVer = ((Get-Item $stackExe).VersionInfo.FileVersion -split '\.')[0..2] -join '.'
$stackSetup = Join-Path $root "..\FoxStack\installers\output\FoxStack-Setup-$stackVer.exe"
if (-not (Test-Path $stackSetup)) { Write-Error "No esta ${stackSetup}: construye FoxStack con su installers\construir.ps1"; exit 1 }
$f = Get-AuthenticodeSignature $stackSetup
'dentro va {0} {1} bytes SHA256 {2} firma={3} (no hace falta)' -f (Split-Path $stackSetup -Leaf), (Get-Item $stackSetup).Length, (Get-FileHash $stackSetup -Algorithm SHA256).Hash, $f.Status

# Lo nuestro de dist\ va SIN firma a proposito (regla 19 de tooling-rules.md): con -Firmar
# solo se firma el setup.
if ($Firmar) {
    if (-not (Test-Path $firmarPs1)) { Write-Error "No esta $firmarPs1"; exit 1 }
    '== ISCC /DFirmar (firma el setup y nada mas)'
    # $q y $f los sustituye Inno (comilla y fichero a firmar); en PowerShell, entre comillas simples.
    & $iscc /Q /DFirmar ('/Sfirmar=powershell.exe -NoProfile -ExecutionPolicy Bypass -File $q' + $firmarPs1 + '$q -Publicar $f') $iss
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
