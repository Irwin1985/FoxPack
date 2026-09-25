# tests\smoke.ps1 -- FoxPack por fuera: el foxpack.exe compilado, como lo usa
# una persona, contra proyectos de prueba en una carpeta temporal.
#
#   powershell -ExecutionPolicy Bypass -File tests\smoke.ps1
#   powershell -ExecutionPolicy Bypass -File tests\smoke.ps1 -Filter verify
#
# Las piezas de dentro (Huella, Candado) tienen sus tests en
# tests\FoxPackProofTests.prg, con FoxProof. Aqui va lo que solo se ve con la
# CLI entera: exit codes, stdout contra stderr y --format json, y add y restore
# contra un GitHub de mentira en una carpeta (FOXPACK_REMOTE), sin red.
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
    param([string[]]$FpArgs, [string]$Dir, [string]$Remote = "", [int]$TimeoutSec = 30)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = ($FpArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join " "
    $psi.WorkingDirectory = $Dir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    # Sin nadie delante: la entrada redirigida y cerrada, como en un script.
    $psi.RedirectStandardInput = $true
    # El GitHub de mentira (src\remoto.prg); vacio, ninguno.
    $psi.EnvironmentVariables["FOXPACK_REMOTE"] = $Remote
    $psi.StandardOutputEncoding = New-Object Text.UTF8Encoding $false
    $psi.StandardErrorEncoding = New-Object Text.UTF8Encoding $false
    $p = [Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
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


# ---------------------------------------------------------------------------
# add y restore, contra un GitHub de mentira
# ---------------------------------------------------------------------------
# Una carpeta con la forma que Remoto espera cuando FOXPACK_REMOTE apunta a
# ella (ver src\remoto.prg). Ningun caso de aqui toca la red.
#
#   jsonlib   fake/JsonLib, v1.0 y v2.0, dos ficheros (uno en una subcarpeta)
#   mala      fake/Mala: la etiqueta dice 1.0 y foxpack.json 1.1
#   sinmanif  fake/Sin: no tiene foxpack.json
#   rota      fake/Rota: foxpack.json lista un fichero que no esta

function Write-Remoto { param([string]$Ruta, [string]$Texto)
    New-Item -ItemType Directory -Force -Path (Split-Path $Ruta) | Out-Null
    [IO.File]::WriteAllText($Ruta, $Texto, [Text.Encoding]::GetEncoding(1252))
}

function New-Remoto {
    $r = Join-Path $tmp ("remoto-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
    Write-Remoto (Join-Path $r "index.json") ('{"indexVersion": 1, "libraries": [' +
        '{"name": "jsonlib", "repo": "fake/JsonLib"}, {"name": "mala", "repo": "fake/Mala"},' +
        '{"name": "sinmanif", "repo": "fake/Sin"}, {"name": "rota", "repo": "fake/Rota"},' +
        '{"name": "otra", "repo": "fake/Otra"}]}')

    $j = Join-Path $r "repos\fake\JsonLib"
    Write-Remoto (Join-Path $j "tags.json") ('[{"name": "v1.0", "commit": {"sha": "1111111111111111111111111111111111111111"}},' +
        '{"name": "v2.0", "commit": {"sha": "2222222222222222222222222222222222222222"}}]')
    foreach ($v in @(@{ V = "1.0"; S = "1111111111111111111111111111111111111111" },
                     @{ V = "2.0"; S = "2222222222222222222222222222222222222222" })) {
        $c = Join-Path $j $v.S
        Write-Remoto (Join-Path $c "foxpack.json") ('{"name": "jsonlib", "version": "' + $v.V +
            '", "files": ["JsonLib.prg", "inc/jsonlib.h"], "usage": "lo = NEWOBJECT(\"JsonLib\", \"JsonLib.prg\")"}')
        Write-Remoto (Join-Path $c "JsonLib.prg") ("* JsonLib " + $v.V + " -- " + [char]241 + "and" + [char]250 + "`r`n")
        Write-Remoto (Join-Path $c "inc\jsonlib.h") ("#DEFINE JSONLIB_VERSION `"" + $v.V + "`"`r`n")
    }

    $m = Join-Path $r "repos\fake\Mala"
    Write-Remoto (Join-Path $m "tags.json") '[{"name": "v1.0", "commit": {"sha": "3333333333333333333333333333333333333333"}}]'
    Write-Remoto (Join-Path $m "3333333333333333333333333333333333333333\foxpack.json") '{"name": "mala", "version": "1.1", "files": ["m.prg"]}'
    Write-Remoto (Join-Path $m "3333333333333333333333333333333333333333\m.prg") "* m`r`n"

    $s = Join-Path $r "repos\fake\Sin"
    Write-Remoto (Join-Path $s "tags.json") '[{"name": "v1.0", "commit": {"sha": "4444444444444444444444444444444444444444"}}]'
    Write-Remoto (Join-Path $s "4444444444444444444444444444444444444444\s.prg") "* s`r`n"

    $t = Join-Path $r "repos\fake\Otra"
    Write-Remoto (Join-Path $t "tags.json") ('[{"name": "v1.0", "commit": {"sha": "6666666666666666666666666666666666666666"}},' +
        '{"name": "v1.1", "commit": {"sha": "7777777777777777777777777777777777777777"}}]')
    foreach ($v in @(@{ V = "1.0"; S = "6666666666666666666666666666666666666666" },
                     @{ V = "1.1"; S = "7777777777777777777777777777777777777777" })) {
        Write-Remoto (Join-Path $t ($v.S + "\foxpack.json")) ('{"name": "otra", "version": "' + $v.V + '", "files": ["otra.prg"]}')
        Write-Remoto (Join-Path $t ($v.S + "\otra.prg")) ("* otra " + $v.V + "`r`n")
    }

    $o = Join-Path $r "repos\fake\Rota"
    Write-Remoto (Join-Path $o "tags.json") '[{"name": "v1.0", "commit": {"sha": "5555555555555555555555555555555555555555"}}]'
    Write-Remoto (Join-Path $o "5555555555555555555555555555555555555555\foxpack.json") '{"name": "rota", "version": "1.0", "files": ["a.prg", "falta.prg"]}'
    Write-Remoto (Join-Path $o "5555555555555555555555555555555555555555\a.prg") "* a`r`n"
    return $r
}

function New-Vacio { param([string]$Nombre)
    $d = Join-Path $tmp $Nombre; New-Item -ItemType Directory -Force -Path $d | Out-Null; return $d
}

function Get-Lock { param([string]$Dir) Get-Content -Raw (Join-Path $Dir "foxpack.lock") | ConvertFrom-Json }

Test-Case "add: la ultima version, con sus ficheros, el candado y .gitattributes" {
    $rem = New-Remoto; $d = New-Vacio "add1"
    $r = Invoke-Fp @("add", "jsonlib") $d -Remote $rem
    if ($r.Code -ne 0) { return "exit $($r.Code): $($r.Err)" }
    if ($r.Out -notmatch "Installed jsonlib 2\.0 \(2222222\)") { return "stdout: [$($r.Out)]" }
    if ($r.Out -notmatch 'Use it with: lo = NEWOBJECT') { return "sin la linea de uso: [$($r.Out)]" }
    foreach ($f in @("lib\jsonlib\JsonLib.prg", "lib\jsonlib\inc\jsonlib.h", "lib\.gitattributes")) {
        if (-not (Test-Path (Join-Path $d $f))) { return "falta $f" }
    }
    $lock = Get-Lock $d
    $lib = $lock.libraries[0]
    if ($lib.name -ne "jsonlib" -or $lib.version -ne "2.0" -or $lib.commit -ne "2222222222222222222222222222222222222222") { return "candado: $($lib | ConvertTo-Json -Compress)" }
    if ($lib.files.Count -ne 2 -or $lib.files[1].path -ne "inc/jsonlib.h") { return "ficheros del candado: $($lib.files | ConvertTo-Json -Compress)" }
    # los bytes, tal cual: el hash del candado es el del fichero del remoto
    $esperado = (Get-FileHash (Join-Path $rem "repos\fake\JsonLib\2222222222222222222222222222222222222222\JsonLib.prg") -Algorithm SHA256).Hash.ToLower()
    if ($lib.files[0].sha256 -ne $esperado) { return "sha256 $($lib.files[0].sha256), esperaba $esperado" }
    $v = Invoke-Fp @("verify") $d -Remote $rem
    if ($v.Code -ne 0) { return "verify despues de add: exit $($v.Code) $($v.Out)" }
}

Test-Case "add jsonlib@1.0 cambia de version, y otra vez la misma no hace nada" {
    $rem = New-Remoto; $d = New-Vacio "add2"
    $null = Invoke-Fp @("add", "jsonlib") $d -Remote $rem
    $r = Invoke-Fp @("add", "jsonlib@1.0") $d -Remote $rem
    if ($r.Code -ne 0) { return "exit $($r.Code): $($r.Err)" }
    if ((Get-Lock $d).libraries[0].version -ne "1.0") { return "el candado no dice 1.0" }
    if ((Get-Content -Raw (Join-Path $d "lib\jsonlib\JsonLib.prg")) -notmatch "JsonLib 1\.0") { return "la copia no es la 1.0" }
    $r = Invoke-Fp @("add", "jsonlib@1.0") $d -Remote $rem
    if ($r.Code -ne 0 -or $r.Out -notmatch "already installed") { return "segunda vez: exit $($r.Code) [$($r.Out)]" }
}

Test-Case "add sobre una copia tocada da exit 12 y no la pisa" {
    $rem = New-Remoto; $d = New-Vacio "add3"
    $null = Invoke-Fp @("add", "jsonlib@1.0") $d -Remote $rem
    Add-Content -Path (Join-Path $d "lib\jsonlib\JsonLib.prg") -Value "* arreglo a mano"
    $r = Invoke-Fp @("add", "jsonlib") $d -Remote $rem
    if ($r.Code -ne 12) { return "exit $($r.Code), esperaba 12" }
    if ((Get-Content -Raw (Join-Path $d "lib\jsonlib\JsonLib.prg")) -notmatch "arreglo a mano") { return "piso la copia tocada" }
    if ((Get-Lock $d).libraries[0].version -ne "1.0") { return "cambio el candado" }
}

Test-Case "add de algo que no existe da exit 10, y de una version que no existe tambien" {
    $rem = New-Remoto; $d = New-Vacio "add4"
    $r = Invoke-Fp @("add", "nada") $d -Remote $rem
    if ($r.Code -ne 10) { return "nombre: exit $($r.Code), esperaba 10" }
    $r = Invoke-Fp @("add", "jsonlib@9.9") $d -Remote $rem
    if ($r.Code -ne 10) { return "version: exit $($r.Code), esperaba 10" }
    if ($r.Err -notmatch "Versions: 1\.0, 2\.0") { return "no dice las versiones: [$($r.Err)]" }
    if (Test-Path (Join-Path $d "foxpack.lock")) { return "escribio un candado" }
}

Test-Case "add: foxpack.json que no cuadra con la etiqueta, o que falta, da exit 13" {
    $rem = New-Remoto; $d = New-Vacio "add5"
    $r = Invoke-Fp @("add", "mala") $d -Remote $rem
    if ($r.Code -ne 13) { return "mala: exit $($r.Code), esperaba 13" }
    if ($r.Err -notmatch "the tag says 1\.0 and foxpack\.json says 1\.1") { return "mala: [$($r.Err)]" }
    $r = Invoke-Fp @("add", "sinmanif") $d -Remote $rem
    if ($r.Code -ne 13) { return "sinmanif: exit $($r.Code), esperaba 13" }
    if (Test-Path (Join-Path $d "lib")) { return "creo lib\" }
}

Test-Case "add: si falta un fichero, exit 11 y lib\ como estaba (sin temporales)" {
    $rem = New-Remoto; $d = New-Vacio "add6"
    $null = Invoke-Fp @("add", "jsonlib") $d -Remote $rem
    $r = Invoke-Fp @("add", "rota") $d -Remote $rem
    if ($r.Code -ne 11) { return "exit $($r.Code), esperaba 11" }
    if (Test-Path (Join-Path $d "lib\rota")) { return "dejo lib\rota a medias" }
    $restos = @(Get-ChildItem (Join-Path $d "lib") -Force -Directory | Where-Object { $_.Name -like ".foxpack-*" })
    if ($restos.Count -gt 0) { return "dejo la temporal: $($restos[0].Name)" }
    if ((Get-Lock $d).libraries.Count -ne 1) { return "el candado cambio" }
}

Test-Case "add github: sin --yes y sin nadie delante no instala; con --yes si" {
    $rem = New-Remoto; $d = New-Vacio "add7"
    $r = Invoke-Fp @("add", "github:fake/JsonLib") $d -Remote $rem
    if ($r.Code -eq 0) { return "instalo sin --yes" }
    if ($r.Err -notmatch "--yes") { return "no dice que falta --yes: [$($r.Err)]" }
    if (Test-Path (Join-Path $d "lib")) { return "creo lib\ sin confirmar" }
    $r = Invoke-Fp @("add", "github:fake/JsonLib@1.0", "--yes") $d -Remote $rem
    if ($r.Code -ne 0) { return "con --yes: exit $($r.Code) $($r.Err)" }
    if ((Get-Lock $d).libraries[0].repo -ne "fake/JsonLib") { return "el candado no dice el repo" }
}

Test-Case "restore repone lo borrado con los mismos bytes, y deja en paz lo que esta bien" {
    $rem = New-Remoto; $d = New-Vacio "rest1"
    $null = Invoke-Fp @("add", "jsonlib") $d -Remote $rem
    $antes = (Get-FileHash (Join-Path $d "lib\jsonlib\JsonLib.prg")).Hash
    Remove-Item (Join-Path $d "lib\jsonlib") -Recurse -Force
    $r = Invoke-Fp @("restore") $d -Remote $rem
    if ($r.Code -ne 0) { return "exit $($r.Code): $($r.Err)" }
    if ($r.Out -notmatch "restored\s+jsonlib 2\.0") { return "stdout: [$($r.Out)]" }
    if ((Get-FileHash (Join-Path $d "lib\jsonlib\JsonLib.prg")).Hash -ne $antes) { return "no son los mismos bytes" }
    $r = Invoke-Fp @("restore") $d -Remote $rem
    if ($r.Out -notmatch "ok\s+jsonlib 2\.0") { return "segunda vez: [$($r.Out)]" }
}

Test-Case "restore: si el remoto ya no tiene lo del candado, exit 11 y no toca nada" {
    $rem = New-Remoto; $d = New-Vacio "rest2"
    $null = Invoke-Fp @("add", "jsonlib") $d -Remote $rem
    Add-Content -Path (Join-Path $d "lib\jsonlib\JsonLib.prg") -Value "* tocado"
    # alguien reescribio el fichero en el remoto con el mismo commit
    Add-Content -Path (Join-Path $rem "repos\fake\JsonLib\2222222222222222222222222222222222222222\JsonLib.prg") -Value "* otro"
    $r = Invoke-Fp @("restore") $d -Remote $rem
    if ($r.Code -ne 11) { return "exit $($r.Code), esperaba 11" }
    if ($r.Err -notmatch "SHA-256 differs") { return "stderr: [$($r.Err)]" }
    if ((Get-Content -Raw (Join-Path $d "lib\jsonlib\JsonLib.prg")) -notmatch "tocado") { return "cambio la copia" }
}


# ---------------------------------------------------------------------------
# update y remove
# ---------------------------------------------------------------------------

Test-Case "update pasa a la ultima, y la segunda vez dice que esta al dia" {
    $rem = New-Remoto; $d = New-Vacio "upd1"
    $null = Invoke-Fp @("add", "jsonlib@1.0") $d -Remote $rem
    $r = Invoke-Fp @("update", "jsonlib") $d -Remote $rem
    if ($r.Code -ne 0) { return "exit $($r.Code): $($r.Err)" }
    if ($r.Out -notmatch "updated\s+jsonlib 1\.0 -> 2\.0") { return "stdout: [$($r.Out)]" }
    if ((Get-Lock $d).libraries[0].version -ne "2.0") { return "el candado no dice 2.0" }
    if ((Get-Content -Raw (Join-Path $d "lib\jsonlib\JsonLib.prg")) -notmatch "JsonLib 2\.0") { return "la copia no es la 2.0" }
    $r = Invoke-Fp @("update") $d -Remote $rem
    if ($r.Code -ne 0 -or $r.Out -notmatch "up to date\s+jsonlib 2\.0") { return "segunda vez: exit $($r.Code) [$($r.Out)]" }
}

Test-Case "update sin nombre las pasa todas" {
    $rem = New-Remoto; $d = New-Vacio "upd2"
    $null = Invoke-Fp @("add", "jsonlib@1.0") $d -Remote $rem
    $null = Invoke-Fp @("add", "otra@1.0") $d -Remote $rem
    $r = Invoke-Fp @("update") $d -Remote $rem
    if ($r.Code -ne 0) { return "exit $($r.Code): $($r.Err)" }
    if ($r.Out -notmatch "updated\s+jsonlib 1\.0 -> 2\.0") { return "jsonlib: [$($r.Out)]" }
    if ($r.Out -notmatch "updated\s+otra 1\.0 -> 1\.1") { return "otra: [$($r.Out)]" }
}

Test-Case "update no pisa una copia tocada sin --force, y con --force si" {
    $rem = New-Remoto; $d = New-Vacio "upd3"
    $null = Invoke-Fp @("add", "jsonlib@1.0") $d -Remote $rem
    Add-Content -Path (Join-Path $d "lib\jsonlib\JsonLib.prg") -Value "* arreglo a mano"
    $r = Invoke-Fp @("update", "jsonlib") $d -Remote $rem
    if ($r.Code -ne 12) { return "sin --force: exit $($r.Code), esperaba 12" }
    if ($r.Err -notmatch "--force") { return "no dice --force: [$($r.Err)]" }
    if ((Get-Lock $d).libraries[0].version -ne "1.0") { return "sin --force cambio el candado" }
    $r = Invoke-Fp @("update", "jsonlib", "--force") $d -Remote $rem
    if ($r.Code -ne 0) { return "con --force: exit $($r.Code) $($r.Err)" }
    if ((Get-Content -Raw (Join-Path $d "lib\jsonlib\JsonLib.prg")) -match "arreglo a mano") { return "con --force no piso la copia" }
    $v = Invoke-Fp @("verify") $d -Remote $rem
    if ($v.Code -ne 0) { return "verify despues de --force: exit $($v.Code)" }
}

Test-Case "update y remove de algo que no esta instalado dan exit 10" {
    $rem = New-Remoto; $d = New-Vacio "upd4"
    $r = Invoke-Fp @("update", "jsonlib") $d -Remote $rem
    if ($r.Code -ne 10) { return "update: exit $($r.Code), esperaba 10" }
    $r = Invoke-Fp @("remove", "jsonlib") $d -Remote $rem
    if ($r.Code -ne 10) { return "remove: exit $($r.Code), esperaba 10" }
}

Test-Case "remove borra lib\<libreria> y la quita del candado, y deja las demas" {
    $rem = New-Remoto; $d = New-Vacio "rem1"
    $null = Invoke-Fp @("add", "jsonlib") $d -Remote $rem
    $null = Invoke-Fp @("add", "github:fake/JsonLib@1.0", "--yes") $d -Remote $rem
    # las dos se llaman jsonlib: la segunda sustituye a la primera
    $r = Invoke-Fp @("remove", "JSONLIB") $d -Remote $rem
    if ($r.Code -ne 0) { return "exit $($r.Code): $($r.Err)" }
    if ($r.Out -notmatch "Removed jsonlib 1\.0") { return "stdout: [$($r.Out)]" }
    if (Test-Path (Join-Path $d "lib\jsonlib")) { return "no borro lib\jsonlib" }
    if ((Get-Lock $d).libraries.Count -ne 0) { return "sigue en el candado" }
    $r = Invoke-Fp @("list") $d -Remote $rem
    if ($r.Out -notmatch "No libraries installed") { return "list: [$($r.Out)]" }
}


# ---------------------------------------------------------------------------
# remove y el proyecto VFP (tests\fixtures\fixture.pjx)
# ---------------------------------------------------------------------------
# El .pjx de prueba tiene lib\jsonlib\jsonlib.prg, lib\jsonlib\inc\jsonlib.h,
# lib\otra\otra.prg y lib\jsonfox\jsonfox.prg, ademas de src\. Se lee con un
# VFP de verdad (vfp9.exe -T), con plazo, como hace smoke-cli.ps1 de FoxForge.

$vfp = "C:\Program Files (x86)\Microsoft Visual FoxPro 9\vfp9.exe"

# Las entradas vivas (no borradas) del .pjx, en minusculas y sin el CHR(0).
function Get-EntradasPjx { param([string]$Pjx)
    $dir = Split-Path $Pjx
    $res = Join-Path $dir "entradas.txt"
    $cfg = Join-Path $dir "sonda.fpw"
    $prg = Join-Path $dir "sonda.prg"
    [IO.File]::WriteAllText($cfg, "SCREEN = OFF`r`nRESOURCE = OFF`r`n")
    [IO.File]::WriteAllText($prg, (@(
        "LOCAL lc",
        "lc = """"",
        "SET DELETED ON",
        "USE ""$Pjx"" AGAIN SHARED NOUPDATE ALIAS p",
        "SCAN FOR !(p.TYPE == ""H"")",
        "    lc = lc + LOWER(CHRTRAN(p.NAME, CHR(0), """")) + CHR(13)",
        "ENDSCAN",
        "USE IN SELECT(""p"")",
        "STRTOFILE(lc, ""$res"")",
        "QUIT") -join "`r`n") + "`r`n")
    $p = Start-Process -FilePath $vfp -ArgumentList @("-T", "-c$cfg", $prg) -WorkingDirectory $dir -PassThru
    if (-not $p.WaitForExit(60000)) { $p.Kill(); return @("COLGADO") }
    if (-not (Test-Path $res)) { return @("SIN RESULTADO") }
    $salida = @((Get-Content -Raw $res) -split "`r" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" } | Sort-Object)
    Remove-Item $res, $cfg, $prg -Force
    return $salida
}

function New-ConPjx { param([string]$Nombre)
    $d = New-Vacio $Nombre
    Copy-Item (Join-Path $root "tests\fixtures\fixture.pjx") $d
    Copy-Item (Join-Path $root "tests\fixtures\fixture.pjt") $d
    return $d
}

Test-Case "remove quita del .pjx cerrado las entradas de la libreria, y solo esas" {
    if (-not (Test-Path $vfp)) { return "no esta vfp9.exe en $vfp" }
    $rem = New-Remoto; $d = New-ConPjx "pjx1"
    $null = Invoke-Fp @("add", "jsonlib") $d -Remote $rem
    $r = Invoke-Fp @("remove", "jsonlib") $d -Remote $rem
    if ($r.Code -ne 0) { return "exit $($r.Code): $($r.Err)" }
    if ($r.Out -notmatch "Taken out of the project: 2 file") { return "stdout: [$($r.Out)]" }
    $quedan = Get-EntradasPjx (Join-Path $d "fixture.pjx")
    $esperadas = @("..\..\desarrollo\irwinrodriguez.dev\foxforge\providers\cli\hook\foxclihook.vcx",
                   "lib\jsonfox\jsonfox.prg", "lib\otra\otra.prg",
                   "src\foxcli.h", "src\foxcli.prg", "src\main.prg") | Sort-Object
    if (($quedan -join ",") -ne ($esperadas -join ",")) { return "quedan [" + ($quedan -join ",") + "]" }
}

Test-Case "remove con el .pjx abierto (bloqueado) no falla y avisa" {
    $rem = New-Remoto; $d = New-ConPjx "pjx2"
    $null = Invoke-Fp @("add", "jsonlib") $d -Remote $rem
    # Como el IDE con el proyecto abierto: el fichero, abierto en exclusiva.
    $fs = [IO.File]::Open((Join-Path $d "fixture.pjx"), "Open", "ReadWrite", "None")
    try { $r = Invoke-Fp @("remove", "jsonlib") $d -Remote $rem } finally { $fs.Close() }
    if ($r.Code -ne 0) { return "exit $($r.Code): $($r.Err)" }
    if ($r.Out -notmatch "The project is open in VFP \(fixture\.pjx\)") { return "stdout: [$($r.Out)]" }
    if (Test-Path (Join-Path $d "lib\jsonlib")) { return "no borro lib\jsonlib" }
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
