# installers\probar-desatendido.ps1 -- el instalador de FoxPack, sin nadie delante
#
# Reglas 13 y 14 de shared\vfp-rules\tooling-rules.md. Sin nadie delante
# (/VERYSILENT /SUPPRESSMSGBOXES /NORESTART), y con un plazo: un setup que no
# sale en 180 s es un dialogo esperando a nadie, y la prueba lo mata y falla.
#
#   1. Instala una version "vieja" en Program Files (x86)\FoxPack, como las de
#      antes de la regla 14.
#   2. Instala otra vez SIN /DIR: tiene que quitar la de Program Files e ir a
#      C:\Programas\FoxPack, con la carpeta CERRADA (sin herencia, usuarios
#      solo lectura y ejecucion, nada para "Usuarios autentificados").
#   3. Comprueba exe, registro, PATH (solo la carpeta nueva) y --version.
#   4. FoxStack (PLAN-FOXSTACK-1.0.md, F3): lo ha instalado FoxPack, y FoxPack
#      es un proveedor suyo. foxstack list lo da ok, el servidor instalado
#      publica foxpack_* y una llamada de verdad a foxpack_list vuelve bien.
#      foxpack sigue funcionando por su cuenta. stack_info lo ve en la familia
#      stack, ok y con sus tools (ronda 93).
#   5. Reinstalar FoxPack: FoxStack no se reinstala (mismo hash y misma fecha
#      del exe), el provider.json se reescribe y la carpeta esta UNA vez en el
#      PATH (ronda 93).
#   6. Con un FoxStack "mas nuevo" en el registro, FoxPack no lo degrada.
#   7. a) Si el setup de FoxStack falla (su carpeta ocupada por un fichero),
#      FoxPack se instala igual y lo dice en su log. b) Con la clave de FoxStack
#      rota (carpeta que no existe) y una version mas nueva, FoxPack lo instala:
#      desde FoxStack 36eefad la guarda de degradar solo cuenta con un exe.
#   8. Las firmas de unins000.exe de FoxPack y de FoxStack.
#   9. Desinstala FoxPack: se va providers\foxpack\, FoxStack y un proveedor
#      ajeno se quedan (ronda 93), y foxstack doctor sale 0.
#  10. Desinstala FoxStack y comprueba que el PATH del sistema queda en crudo
#      como estaba y que no queda nada de ninguno de los dos.
#
# OJO al medir una desinstalacion: unins000.exe se copia a %TEMP% y sale; la
# copia sigue trabajando despues y quita la entrada del PATH al final
# (usPostUninstall). Leer el PATH en cuanto sale da un falso "no la ha
# quitado": se espera a que cambie, con plazo.
#
# Toca el registro y el PATH del sistema: hace falta administrador.
#
#   powershell -ExecutionPolicy Bypass -File installers\probar-desatendido.ps1 [-Setup <FoxPack-Setup-x.y.z.exe>]
#
# Fichero en ASCII: PowerShell 5.1 no lee bien un .ps1 con acentos.

[CmdletBinding()]
param(
    [string]$Setup,
    [string]$Salida = (Join-Path $env:TEMP ('foxpack-desatendido-' + (Get-Date -Format 'yyyyMMdd-HHmmss')))
)

$ErrorActionPreference = "Stop"
if (-not $Setup) {
    $s = Get-ChildItem (Join-Path $PSScriptRoot "output\FoxPack-Setup-*.exe") -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
    if (-not $s) { "No hay instalador en installers\output. Compila FoxPack.iss antes."; exit 1 }
    $Setup = $s.FullName
}
$envKey   = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
$regKey   = "HKLM:\SOFTWARE\WOW6432Node\irwinrodriguez.dev\FoxPack"
$stackKey = "HKLM:\SOFTWARE\WOW6432Node\irwinrodriguez.dev\FoxStack"
$vieja    = Join-Path ${env:ProgramFiles(x86)} "FoxPack"
$nueva    = Join-Path $env:SystemDrive "Programas\FoxPack"
$stack    = Join-Path $env:SystemDrive "Programas\FoxStack"
$stackExe = Join-Path $stack "foxstack.exe"
$prov     = Join-Path $stack "providers\foxpack\provider.json"
$fallos   = New-Object System.Collections.Generic.List[string]
New-Item -ItemType Directory -Force $Salida | Out-Null
$utf8     = New-Object System.Text.UTF8Encoding($false)

function Fallo([string]$m) { $script:fallos.Add($m); "  FALLO: $m" }
function Get-PathCrudo { (Get-Item $envKey).GetValue("Path", $null, "DoNotExpandEnvironmentNames") }

function Invoke-Setup { param([string]$Exe, [string]$Log, [string[]]$Extra = @())
    # Con comillas: Start-Process junta los argumentos con espacios y NO los
    # entrecomilla, y "/DIR=C:\Program Files (x86)\FoxPack" llegaba como
    # "/DIR=C:\Program" (medido: instalo en C:\Program).
    $a = @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", ('/LOG="' + $Log + '"')) + $Extra
    $p = Start-Process $Exe -ArgumentList $a -PassThru
    if (-not $p.WaitForExit(180000)) { $p.Kill(); "SE QUEDO PARADO: $Exe (un dialogo esperando a nadie)"; exit 1 }
    return $p.ExitCode
}

# Un exe con stdout, stderr y exit code, y stdin de un fichero si se da.
function Invoke-Exe([string]$Exe, [string[]]$A, [string]$Entrada) {
    $s = Join-Path $Salida ('p.' + [Guid]::NewGuid().ToString('N'))
    $sp = @{ FilePath = $Exe; RedirectStandardOutput = $s; RedirectStandardError = ($s + '.err'); NoNewWindow = $true; PassThru = $true }
    if ($A.Count -gt 0) { $sp.ArgumentList = $A }
    if ($Entrada) { $sp.RedirectStandardInput = $Entrada }
    $p = Start-Process @sp
    # Sin leer Handle antes de esperar, ExitCode sale vacio con -NoNewWindow y redirecciones (PS 5.1).
    $null = $p.Handle
    if (-not $p.WaitForExit(120000)) { $p.Kill(); Fallo "$Exe $($A -join ' ') no salio en 120 s" }
    $r = [pscustomobject]@{ Exit = $p.ExitCode; Out = [string](Get-Content $s -Raw -ErrorAction SilentlyContinue); Err = [string](Get-Content ($s + '.err') -Raw -ErrorAction SilentlyContinue) }
    Remove-Item $s, ($s + '.err') -ErrorAction SilentlyContinue
    return $r
}

function Show-Salida($r) {
    if ($r.Out) { ($r.Out.TrimEnd() -split "`n") | ForEach-Object { "  | $($_.TrimEnd())" } }
    if ($r.Err) { ($r.Err.TrimEnd() -split "`n") | ForEach-Object { "  ! $($_.TrimEnd())" } }
}

function Show-LogFoxPack([string]$Log) {
    Select-String -Path $Log -Pattern 'FoxPack:' -ErrorAction SilentlyContinue | ForEach-Object { "  su log: " + ($_.Line -replace '^\S+ \S+\s+', '') }
}

function Show-Firma([string]$Fichero) {
    $g = Get-AuthenticodeSignature $Fichero
    "  {0}: {1}{2}{3}" -f $Fichero, $g.Status,
        $(if ($g.SignerCertificate) { ', ' + $g.SignerCertificate.Subject.Split(',')[0] + ', huella ' + $g.SignerCertificate.Thumbprint }),
        $(if ($g.TimeStamperCertificate) { ', con sello de tiempo' })
}

# Un proyecto de FoxPack vacio, para las llamadas de solo lectura.
$proyecto = Join-Path $Salida 'proyecto'
New-Item -ItemType Directory -Force $proyecto | Out-Null
[IO.File]::WriteAllText((Join-Path $proyecto 'foxpack.lock'), '{"lockVersion": 1, "libraries": []}', $utf8)

# ---------------------------------------------------------------------------
"probar-desatendido de FoxPack, commit $(git -C (Split-Path -Parent $PSScriptRoot) rev-parse --short HEAD), $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
"setup: $Setup $((Get-Item $Setup).Length) bytes SHA256 $((Get-FileHash $Setup -Algorithm SHA256).Hash)"
Show-Firma $Setup
"logs de los setups en: $Salida"

"== 0. antes"
if ((Test-Path "$vieja\foxpack.exe") -or (Test-Path "$nueva\foxpack.exe")) {
    "Ya hay un FoxPack instalado ($vieja o $nueva). Desinstalalo antes de la prueba."; exit 1
}
if ((Test-Path $stack) -or (Test-Path $stackKey)) {
    "Ya hay algo de FoxStack en esta maquina ($stack o $stackKey). Desinstalalo antes de la prueba."; exit 1
}
$antes = Get-PathCrudo
"  ni FoxPack ni FoxStack; PATH del sistema: $(($antes -split ';').Count) entradas"

# 1 ---------------------------------------------------------------------------
"== 1. la vieja, en Program Files"
$c = Invoke-Setup $Setup (Join-Path $Salida '1-vieja.log') @('/DIR="' + $vieja + '"')
"  exit $c"
if ($c -ne 0 -or -not (Test-Path "$vieja\foxpack.exe")) { "no se pudo poner la vieja en $vieja (exit $c)"; exit 1 }
Show-LogFoxPack (Join-Path $Salida '1-vieja.log')

# 2 ---------------------------------------------------------------------------
"== 2. la nueva, sin /DIR"
$c = Invoke-Setup $Setup (Join-Path $Salida '2-nueva.log')
"  exit $c"
if ($c -ne 0) { Fallo "instalar: exit $c" }
if (Test-Path "$vieja\foxpack.exe") { Fallo "no quito la de Program Files" }
if (-not (Test-Path "$nueva\foxpack.exe")) { Fallo "no instalo en $nueva" }
Show-LogFoxPack (Join-Path $Salida '2-nueva.log')

# 3 ---------------------------------------------------------------------------
"== 3. lo instalado de FoxPack"
$reg = Get-ItemProperty $regKey -ErrorAction SilentlyContinue
"  registro: InstallDir=$($reg.InstallDir) Version=$($reg.Version)"
if (-not $reg -or $reg.InstallDir -ne $nueva) { Fallo "el registro no dice InstallDir=$nueva" }
$entradas = (Get-PathCrudo) -split ";"
if ($entradas -notcontains $nueva) { Fallo "la nueva no esta en el PATH" }
if ($entradas -contains $vieja) { Fallo "la vieja sigue en el PATH" }
$ver = & "$nueva\foxpack.exe" --version
if ($ver -notmatch "^foxpack \d") { Fallo "foxpack --version: [$ver]" }
# PLAN-FOXCLI-LICENCIA, pieza 5: FoxPack sale sellado a nombre de Irwin, y el sello
# solo lo lee el host si Nexum.dll esta instalado a su lado. Sin el, sale en evaluacion.
if ($ver -notmatch "licensed to Irwin Rodr") { Fallo "el instalado no esta sellado (falta Nexum.dll?): [$ver]" }
"  version:   $ver"
$acl = Get-Acl $nueva
if (-not $acl.AreAccessRulesProtected) { Fallo "la carpeta sigue heredando permisos" }
foreach ($r in $acl.Access) {
    $sid = $r.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
    # Solo los bits que ESCRIBEN: WriteData 0x2, AppendData 0x4, WriteExtendedAttributes
    # 0x10, WriteAttributes 0x100, Delete 0x10000. Una mascara con Modify daba
    # positivo con ReadAndExecute, porque comparten Synchronize y los de lectura.
    $escribe = ([int]$r.FileSystemRights -band 0x10116) -ne 0
    if ($sid -eq "S-1-5-11") { Fallo "Usuarios autentificados sigue en la carpeta ($($r.FileSystemRights))" }
    if ($sid -eq "S-1-5-32-545" -and $escribe) { Fallo "los usuarios pueden escribir ($($r.FileSystemRights))" }
}
$acl.Access | ForEach-Object { "  permiso:  " + $_.IdentityReference + " " + $_.FileSystemRights }

# 4 ---------------------------------------------------------------------------
"== 4. FoxStack, instalado por FoxPack, con foxpack como proveedor"
$sreg = Get-ItemProperty $stackKey -ErrorAction SilentlyContinue
"  FoxStack: InstallDir=$($sreg.InstallDir) Version=$($sreg.Version)"
if (-not $sreg -or $sreg.InstallDir -ne $stack -or -not (Test-Path $stackExe)) { Fallo "FoxStack no quedo instalado en $stack" }
if ($sreg.Version -ne '1.0.0') { Fallo "FoxStack no es 1.0.0" }
$r = Invoke-Exe $stackExe @('--version'); "  foxstack --version -> [$($r.Out.Trim())] exit $($r.Exit)"
if ($r.Out.Trim() -ne 'FoxStack 1.0.0') { Fallo "foxstack --version: [$($r.Out.Trim())]" }
"  provider.json:"
if (Test-Path $prov) { (Get-Content $prov) | ForEach-Object { "  | $_" } } else { Fallo "no esta $prov" }
$pj = Get-Content $prov -Raw | ConvertFrom-Json
if ($pj.exe -ne "$nueva\foxpack.exe") { Fallo "el provider.json no apunta a $nueva\foxpack.exe" }
$r = Invoke-Exe $stackExe @('list', '--format', 'json')
$fp = @(($r.Out | ConvertFrom-Json).providers | Where-Object { $_.id -eq 'foxpack' })
$r2 = Invoke-Exe $stackExe @('list'); "  foxstack list -> exit $($r2.Exit)"; Show-Salida $r2
if ($fp.Count -ne 1 -or $fp[0].status -ne 'ok') { Fallo "foxstack list no da foxpack en ok" }
"  foxpack bajo FoxStack: status=$($fp[0].status) tools=$($fp[0].tools) sealed=$($fp[0].sealed)"

$ent = Join-Path $Salida 'mcp-in.txt'
$llamada = @{ jsonrpc = '2.0'; id = 3; method = 'tools/call'; params = @{ name = 'foxpack_list'; arguments = @{ project = $proyecto } } } | ConvertTo-Json -Depth 5 -Compress
[IO.File]::WriteAllLines($ent, @(
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
    $llamada
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"stack_info","arguments":{}}}'), $utf8)
$r = Invoke-Exe $stackExe @() $ent
$lineas = @(($r.Out -split "`n") | Where-Object { $_.Trim() -ne '' })
$tools = @((($lineas[1] | ConvertFrom-Json).result.tools) | ForEach-Object { $_.name } | Where-Object { $_ -like 'foxpack_*' })
"  el servidor instalado publica $($tools.Count) foxpack_*: $($tools -join ', ')"
if ($tools.Count -eq 0) { Fallo "el servidor instalado no publica foxpack_*" }
$res = ($lineas[2] | ConvertFrom-Json).result
"  tools/call foxpack_list {project: <vacio>} -> isError=$($res.isError)"
$res.content | ForEach-Object { ($_.text -split "`n") | ForEach-Object { "  | $($_.TrimEnd())" } }
if ($res.isError -or ($res.content[0].text -notmatch 'libraries')) { Fallo "la llamada de verdad a foxpack_list no volvio bien" }
# stack_info lo ve en su familia (stack), ok y con sus tools (ronda 93).
$si = (($lineas[3] | ConvertFrom-Json).result.content[0].text | ConvertFrom-Json).data
$fpi = @($si.providers.stack | Where-Object { $_.id -eq 'foxpack' })
"  stack_info: foxpack en la familia stack: $(if ($fpi.Count -eq 1) { 'status=' + $fpi[0].status + ' tools=' + $fpi[0].tools } else { 'NO' })"
if ($fpi.Count -ne 1 -or $fpi[0].status -ne 'ok' -or $fpi[0].tools -ne $tools.Count) { Fallo "stack_info no ve foxpack ok en la familia stack con sus $($tools.Count) tools" }
if ($r.Err) { "  stderr del servidor:"; ($r.Err.TrimEnd() -split "`n") | ForEach-Object { "  ! $($_.TrimEnd())" } }

"  foxpack por su cuenta:"
$r = Invoke-Exe "$nueva\foxpack.exe" @('list', '-p', $proyecto, '--format', 'json'); "  foxpack list -p <vacio> --format json -> exit $($r.Exit)"; Show-Salida $r
if ($r.Exit -ne 0 -or $r.Out -notmatch 'libraries') { Fallo "foxpack list por su cuenta" }

# 5 ---------------------------------------------------------------------------
"== 5. reinstalar FoxPack: FoxStack no se toca y el provider.json se reescribe"
$hStack = (Get-FileHash $stackExe).Hash; $fStack = (Get-Item $stackExe).LastWriteTimeUtc.ToString('o')
$hUnins = (Get-FileHash (Join-Path $stack 'unins000.dat')).Hash
[IO.File]::WriteAllText($prov, '{"id": "foxpack", "kind": "cli", "family": "stack", "exe": "C:\\cambiado\\a\\mano.exe"}', $utf8)
$fProv = (Get-Item $prov).LastWriteTimeUtc
"  foxstack.exe antes: $hStack $fStack"
"  provider.json cambiado a mano para ver que se reescribe"
Start-Sleep -Milliseconds 1100
$c = Invoke-Setup $Setup (Join-Path $Salida '5-reinstalar.log')
"  exit $c"
if ($c -ne 0) { Fallo "reinstalar: exit $c" }
Show-LogFoxPack (Join-Path $Salida '5-reinstalar.log')
"  foxstack.exe despues: $((Get-FileHash $stackExe).Hash) $((Get-Item $stackExe).LastWriteTimeUtc.ToString('o'))"
if ((Get-FileHash $stackExe).Hash -ne $hStack -or (Get-Item $stackExe).LastWriteTimeUtc.ToString('o') -ne $fStack) { Fallo "FoxStack se reinstalo" }
if ((Get-FileHash (Join-Path $stack 'unins000.dat')).Hash -ne $hUnins) { Fallo "el unins000.dat de FoxStack cambio: se reinstalo" }
$pj = Get-Content $prov -Raw | ConvertFrom-Json
"  provider.json: exe=$($pj.exe), escrito $((Get-Item $prov).LastWriteTimeUtc.ToString('o'))"
if ($pj.exe -ne "$nueva\foxpack.exe" -or (Get-Item $prov).LastWriteTimeUtc -le $fProv) { Fallo "el provider.json no se reescribio" }
# Instalar encima de si mismo no duplica la entrada del PATH (ronda 93).
$veces = @((Get-PathCrudo) -split ';' | Where-Object { $_ -eq $nueva }).Count
"  PATH del sistema: $nueva aparece $veces vez/veces"
if ($veces -ne 1) { Fallo "tras reinstalar, $nueva esta $veces veces en el PATH" }

# 6 ---------------------------------------------------------------------------
"== 6. con un FoxStack 'mas nuevo' en el registro (9.9.9), FoxPack no lo degrada"
Set-ItemProperty $stackKey -Name Version -Value '9.9.9'
$c = Invoke-Setup $Setup (Join-Path $Salida '6-mas-nuevo.log')
"  exit $c"
if ($c -ne 0) { Fallo "instalar con un FoxStack mas nuevo: exit $c" }
Show-LogFoxPack (Join-Path $Salida '6-mas-nuevo.log')
if ((Get-FileHash $stackExe).Hash -ne $hStack -or (Get-Item $stackExe).LastWriteTimeUtc.ToString('o') -ne $fStack) { Fallo "FoxStack se toco con uno mas nuevo puesto" } else { "  foxstack.exe: mismo hash y misma fecha" }
if ((Get-ItemProperty $stackKey).Version -ne '9.9.9') { Fallo "la version del registro cambio" } else { "  registro: sigue 9.9.9" }
Set-ItemProperty $stackKey -Name Version -Value '1.0.0'
"  registro devuelto a 1.0.0"

# 7 ---------------------------------------------------------------------------
"== 7. la clave de FoxStack apuntando a una carpeta que no existe"
"  se desinstala FoxStack (FoxPack se queda) para que no haya ninguno"
$c = Invoke-Setup (Join-Path $stack 'unins000.exe') (Join-Path $Salida '7-desinstalar-stack.log')
for ($i = 0; $i -lt 60 -and (Test-Path $stackExe); $i++) { Start-Sleep -Milliseconds 500 }
"  exit $c; foxstack.exe: $(if (Test-Path $stackExe) { 'SIGUE' } else { 'no esta' })"
$noHay = Join-Path $env:SystemDrive 'Programas\FoxStack-no-existe'
New-Item -Path $stackKey -Force | Out-Null

# Desde FoxStack 36eefad (30-09) la guarda de degradar de FoxStack.iss solo cuenta con un
# foxstack.exe en InstallDir: una clave rota con una version mas nueva ya no hace fallar su
# setup. Para ver que FoxPack sigue si el setup de FoxStack FALLA (ronda 93), se le pone
# delante un FICHERO donde va su carpeta: no la puede crear.
"  7a. C:\Programas\FoxStack es un FICHERO: el setup de FoxStack falla y FoxPack se instala igual"
Remove-Item $stackKey -Recurse -ErrorAction SilentlyContinue
[IO.File]::WriteAllText($stack, 'no es una carpeta: probar-desatendido de FoxPack, paso 7a', $utf8)
$c = Invoke-Setup $Setup (Join-Path $Salida '7a-stack-falla.log')
"  exit $c"
if ($c -ne 0) { Fallo "FoxPack no se instalo con el setup de FoxStack fallando: exit $c" }
Show-LogFoxPack (Join-Path $Salida '7a-stack-falla.log')
if (-not (Select-String -Path (Join-Path $Salida '7a-stack-falla.log') -Pattern 'FoxPack se instala sin el' -Quiet)) { Fallo "el log no dice que FoxPack se instala sin FoxStack" }
if (Test-Path $stackExe) { Fallo "FoxStack se instalo con su carpeta ocupada por un fichero" }
if (-not (Test-Path "$nueva\foxpack.exe")) { Fallo "FoxPack no esta" }
Remove-Item -LiteralPath $stack -Force
Remove-Item $stackKey -Recurse -ErrorAction SilentlyContinue
New-Item -Path $stackKey -Force | Out-Null

"  7b. InstallDir=$noHay y Version=9.9.9 (una clave rota y mas nueva): FoxPack instala FoxStack"
Set-ItemProperty $stackKey -Name InstallDir -Value $noHay; Set-ItemProperty $stackKey -Name Version -Value '9.9.9'
$c = Invoke-Setup $Setup (Join-Path $Salida '7b-clave-rota.log')
"  exit $c"
if ($c -ne 0) { Fallo "instalar con la clave rota: exit $c" }
Show-LogFoxPack (Join-Path $Salida '7b-clave-rota.log')
$sreg = Get-ItemProperty $stackKey -ErrorAction SilentlyContinue
"  FoxStack: InstallDir=$($sreg.InstallDir) Version=$($sreg.Version); foxstack.exe $(if (Test-Path $stackExe) { 'esta' } else { 'NO esta' })"
if ($sreg.InstallDir -ne $stack -or -not (Test-Path $stackExe)) { Fallo "FoxStack no se instalo en $stack" }
if (-not (Test-Path $prov)) { Fallo "no se escribio el provider.json" }
if (Test-Path $noHay) { Fallo "se creo $noHay" }

# 8 ---------------------------------------------------------------------------
"== 8. las firmas de los desinstaladores"
Show-Firma (Join-Path $nueva 'unins000.exe')
Show-Firma (Join-Path $stack 'unins000.exe')

# 9 ---------------------------------------------------------------------------
"== 9. desinstalar FoxPack: se va su proveedor y FoxStack se queda, y un proveedor ajeno tambien"
# Un proveedor de otro producto (ronda 93): tiene que seguir ahi despues.
$ajeno = Join-Path $stack 'providers\ajeno'
New-Item -ItemType Directory -Force $ajeno | Out-Null
[IO.File]::WriteAllText((Join-Path $ajeno 'provider.json'), '{"id": "ajeno", "kind": "cli", "family": "stack", "exe": "C:\\no\\esta\\ajeno.exe"}', $utf8)
$c = Invoke-Setup (Join-Path $nueva "unins000.exe") (Join-Path $Salida '9-desinstalar-foxpack.log')
"  exit $c"
if ($c -ne 0) { Fallo "desinstalar FoxPack: exit $c" }
for ($i = 0; $i -lt 60 -and ((Test-Path "$nueva\foxpack.exe") -or (((Get-PathCrudo) -split ';') -contains $nueva)); $i++) { Start-Sleep -Milliseconds 500 }
Show-LogFoxPack (Join-Path $Salida '9-desinstalar-foxpack.log')
if (Test-Path (Split-Path $prov)) { Fallo "sigue providers\foxpack\" } else { "  providers\foxpack\: no esta" }
if (-not (Test-Path $stackExe)) { Fallo "se llevo FoxStack" } else { "  FoxStack: sigue en $stack" }
if (-not (Test-Path (Join-Path $ajeno 'provider.json'))) { Fallo "se llevo el proveedor ajeno" } else { "  providers\ajeno\: sigue" }
# El ajeno es de la prueba (su exe no existe): se quita a mano, antes del doctor y para que la
# desinstalacion de FoxStack deje la maquina limpia.
Remove-Item -LiteralPath $ajeno -Recurse -Force
if (Test-Path $regKey) { Fallo "sigue la clave de FoxPack" }
if (Test-Path "$nueva\foxpack.exe") { Fallo "sigue foxpack.exe" }
if (((Get-PathCrudo) -split ';') -contains $nueva) { Fallo "FoxPack sigue en el PATH" }
$r = Invoke-Exe $stackExe @('doctor'); "  foxstack doctor -> exit $($r.Exit)"; Show-Salida $r
if ($r.Exit -ne 0) { Fallo "foxstack doctor: exit $($r.Exit)" }

# 10 --------------------------------------------------------------------------
"== 10. desinstalar FoxStack, y como queda la maquina"
$c = Invoke-Setup (Join-Path $stack "unins000.exe") (Join-Path $Salida '10-desinstalar-stack.log')
"  exit $c"
if ($c -ne 0) { Fallo "desinstalar FoxStack: exit $c" }
for ($i = 0; $i -lt 60 -and ((Get-PathCrudo) -ne $antes -or (Test-Path $stackExe)); $i++) { Start-Sleep -Milliseconds 500 }
"  C:\Programas\FoxPack: $(if (Test-Path $nueva) { 'SIGUE: ' + ((Get-ChildItem $nueva -Recurse -Force | ForEach-Object Name) -join ', ') } else { 'no existe' })"
"  C:\Program Files (x86)\FoxPack: $(if (Test-Path $vieja) { 'SIGUE' } else { 'no existe' })"
"  C:\Programas\FoxStack: $(if (Test-Path $stack) { 'SIGUE: ' + ((Get-ChildItem $stack -Recurse -Force | ForEach-Object Name) -join ', ') } else { 'no existe' })"
"  $regKey : $(if (Test-Path $regKey) { 'SIGUE' } else { 'no existe' })"
"  $stackKey : $(if (Test-Path $stackKey) { 'SIGUE' } else { 'no existe' })"
"  PATH del sistema: $(if ((Get-PathCrudo) -eq $antes) { 'en crudo, igual que antes' } else { 'DISTINTO' })"
if ((Get-PathCrudo) -ne $antes) { Fallo "el PATH no ha vuelto a como estaba" }
if (Test-Path $regKey) { Fallo "sigue la clave de FoxPack" }
if (Test-Path $stackKey) { Fallo "sigue la clave de FoxStack" }
if (Test-Path $nueva) { Fallo "sigue $nueva" }
if (Test-Path $vieja) { Fallo "sigue $vieja" }
if (Test-Path $stack) { Fallo "sigue $stack" }

""
if ($fallos.Count -eq 0) { "OK: FoxPack instala FoxStack y se registra en el, no lo degrada, no lo reinstala sin motivo, sigue si FoxStack falla, y al desinstalar se lleva solo lo suyo; el PATH queda como estaba"; exit 0 }
$fallos | ForEach-Object { "FALLO: $_" }
exit 1
