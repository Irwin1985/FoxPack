; =============================================================================
; FoxPack.iss -- instala la CLI de FoxPack
;
; QUE INSTALA
;   foxpack.exe con su DLL y el runtime de VFP (lo que arma pack.ps1: ocho
;   ficheros, activacion COM por manifiesto y sin registro), el README, la
;   licencia y docs\foxpack.md.
;
; DONDE: C:\Programas\FoxPack, regla 14 de shared\vfp-rules\tooling-rules.md.
;   Y como C:\Programas deja modificar su contenido a cualquier usuario
;   autenticado (lo hereda de C:\), el instalador CIERRA su carpeta al acabar:
;   sin herencia, administradores y SYSTEM con control total, usuarios con
;   lectura y ejecucion. Por SID, que funciona en Windows de cualquier idioma.
;   Si habia una instalacion en otra carpeta (Program Files, de antes de la
;   regla), se desinstala en silencio antes de instalar esta.
;
;   Y dos cosas fuera de su carpeta:
;     - {app} en el PATH del sistema, para que «foxpack» funcione en cualquier
;       consola. Se quita al desinstalar.
;     - HKLM\SOFTWARE\irwinrodriguez.dev\FoxPack con InstallDir y Version. Es
;       donde lo busca FoxForge (CliProvider.FoxPackExe, 0.3.22 en adelante)
;       para el menu «Añadir librería». Instalador de 32 bits: acaba en
;       WOW6432Node, que es donde lee un VFP.
;
;   Y FoxStack (PLAN-FOXSTACK-1.0.md, F3): FoxPack lleva dentro el setup de
;   FoxStack, como FoxCli lleva el de FoxForge. PrepareToInstall lo instala si
;   no esta (o la clave apunta a una carpeta sin foxstack.exe) o si el que hay
;   es mas viejo; igual o mas nuevo, no se toca. Si ese setup falla, FoxPack se
;   instala igual y queda en el log. Al acabar se escribe
;   <InstallDir de FoxStack>\providers\foxpack\provider.json, SIEMPRE, tambien
;   al actualizar: es lo que despierta la recarga de un FoxStack arrancado. Al
;   desinstalar FoxPack se va providers\foxpack\ y FoxStack se queda.
;
; LA VERSION sale del manifiesto que genera la compilacion
; (dist\foxpack.exe.commands.txt, linea «ver|»), que a su vez sale de la
; version del proyecto VFP. Asi el instalador no puede decir otra.
;
; Fichero en UTF-8. Ojo con las llaves en los comentarios de [Code]: Inno las
; interpreta aunque esten dentro de un //.
; =============================================================================

#define Nombre     "FoxPack"
#define Publicador "irwinrodriguez.dev"
#define Dist       "..\dist"

#define Version ""
#define Linea ""
#define FichMan FileOpen(AddBackslash(SourcePath) + Dist + "\foxpack.exe.commands.txt")
#if !FichMan
  #error No pude abrir dist\foxpack.exe.commands.txt: compila la CLI antes
#endif
#sub LeerVersion
  #expr Linea = FileRead(FichMan)
  #if Copy(Linea, 1, 4) == "ver|"
    #expr Version = Trim(Copy(Linea, 5))
  #endif
#endsub
#for {0; Version == "" && !FileEof(FichMan); 0} LeerVersion
#expr FileClose(FichMan)
#if Version == ""
  #error dist\foxpack.exe.commands.txt no trae la version (ver|)
#endif

; FoxStack, el que viaja dentro: el setup que deja FoxStack\installers\construir.ps1,
; con la version del foxstack.exe que empaqueto (su payload\). FIRMADO: un setup
; sin firma dentro de uno firmado es justo lo que para el antivirus en casa de otro.
#define StackDir "..\..\FoxStack\installers"
#define StackExe AddBackslash(SourcePath) + StackDir + "\payload\foxstack.exe"
#if !FileExists(StackExe)
  #error Falta FoxStack\installers\payload\foxstack.exe: construye FoxStack con su installers\construir.ps1 -Firmar
#endif
#define StackMaj 0
#define StackMin 0
#define StackRev 0
#define StackBld 0
#expr GetVersionComponents(StackExe, StackMaj, StackMin, StackRev, StackBld)
#define StackVer Str(StackMaj) + "." + Str(StackMin) + "." + Str(StackRev)
#define SetupStack "FoxStack-Setup-" + StackVer + ".exe"
#define SetupStackSrc StackDir + "\output\" + SetupStack
#if !FileExists(AddBackslash(SourcePath) + SetupStackSrc)
  #error Falta FoxStack\installers\output\FoxStack-Setup-<version>.exe: construye FoxStack con su installers\construir.ps1 -Firmar
#endif
#if Exec("powershell.exe", "-NoProfile -NonInteractive -Command $s=Get-AuthenticodeSignature -LiteralPath " + AddBackslash(SourcePath) + SetupStackSrc + "; if ($s.Status -ne 'Valid' -or $s.SignerCertificate.Subject -notlike '*Irwin Alfredo Rodriguez Gimenez*') { exit 1 }", , 1, 0) != 0
  #error El setup de FoxStack no lleva nuestra firma valida: construye FoxStack con su installers\construir.ps1 -Firmar
#endif

[Setup]
AppId={{6B0E2C41-8D7A-4F35-9E12-F0XPACK00001}
AppName={#Nombre}
AppVersion={#Version}
AppVerName={#Nombre} {#Version}
AppPublisher={#Publicador}
AppPublisherURL=https://irwinrodriguez.dev
DefaultDirName={sd}\Programas\FoxPack
; No la carpeta de la instalacion anterior: si estaba fuera de C:\Programas,
; se desinstala y esta va donde manda la regla (DesinstalarAnterior).
UsePreviousAppDir=no
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ChangesEnvironment=yes
OutputDir=output
OutputBaseFilename=FoxPack-Setup-{#Version}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#Nombre} {#Version}
LicenseFile=..\LICENSE
; LA FIRMA, SOLO SI SE PIDE. Con /DFirmar Inno firma el setup Y el desinstalador con la
; SignTool 'firmar', que le da installers\construir.ps1 -Firmar en la linea de comandos
; (Golem\tools\firmar.ps1, certificado SSL.com IV de Irwin). Sin /DFirmar compila igual
; y sin gastar cuota de eSigner.
#ifdef Firmar
SignTool=firmar
SignedUninstaller=yes
#endif

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[Messages]
en.WelcomeLabel2=FoxPack installs libraries into Visual FoxPro projects, downloaded from GitHub at a fixed version.%n%nIt is a console command: after installing, open a console in your project folder and type "foxpack add jsonfox".
es.WelcomeLabel2=FoxPack instala librerías en proyectos de Visual FoxPro, bajadas de GitHub con la versión fija.%n%nEs un comando de consola: al terminar, abre una consola en la carpeta de tu proyecto y escribe "foxpack add jsonfox".
de.WelcomeLabel2=FoxPack installiert Bibliotheken in Visual-FoxPro-Projekte, von GitHub geladen und mit fester Version.%n%nEs ist ein Konsolenbefehl: Öffne nach der Installation eine Konsole im Projektordner und tippe "foxpack add jsonfox".

[Files]
Source: "{#Dist}\foxpack.exe";              DestDir: "{app}"; Flags: ignoreversion
Source: "{#Dist}\foxpack.dll";              DestDir: "{app}"; Flags: ignoreversion
Source: "{#Dist}\foxpack.exe.manifest";     DestDir: "{app}"; Flags: ignoreversion
Source: "{#Dist}\foxpack.exe.commands.txt"; DestDir: "{app}"; Flags: ignoreversion
; Lee el sello de FoxCli del manifiesto (FoxPack sale sellado a nombre de Irwin).
; Sin ella, foxpack funciona igual pero escribe la linea de evaluacion.
Source: "{#Dist}\Nexum.dll";                DestDir: "{app}"; Flags: ignoreversion
Source: "{#Dist}\vfp9r.dll";                DestDir: "{app}"; Flags: ignoreversion
Source: "{#Dist}\msvcr71.dll";              DestDir: "{app}"; Flags: ignoreversion
Source: "{#Dist}\VFP9RENU.DLL";             DestDir: "{app}"; Flags: ignoreversion
Source: "{#Dist}\vfp9resn.dll";             DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md";                     DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE";                       DestDir: "{app}"; Flags: ignoreversion
Source: "..\docs\foxpack.md";               DestDir: "{app}\docs"; Flags: ignoreversion
; FoxStack, por si hay que ponerlo. Se extrae al temporal y se ejecuta solo cuando
; hace falta (PrepareToInstall), como FoxCli.iss con el setup de FoxForge.
Source: "{#SetupStackSrc}";                 DestDir: "{tmp}"; Flags: dontcopy nocompression

[Registry]
Root: HKLM; Subkey: "SOFTWARE\irwinrodriguez.dev\FoxPack"; ValueType: string; ValueName: "InstallDir"; ValueData: "{app}"; Flags: uninsdeletekey
Root: HKLM; Subkey: "SOFTWARE\irwinrodriguez.dev\FoxPack"; ValueType: string; ValueName: "Version"; ValueData: "{#Version}"
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; Check: FaltaEnPath(ExpandConstant('{app}'))

[Code]
#define AppIdUninst "{6B0E2C41-8D7A-4F35-9E12-F0XPACK00001}_is1"

// ---------------------------------------------------------------------------
// La instalacion anterior, si esta en otra carpeta: se desinstala en silencio.
//
// unins000.exe sale enseguida: se copia a %TEMP% y la copia sigue trabajando
// (regla 13). Por eso no basta con esperar a que termine: se espera, con plazo,
// a que desaparezca su foxpack.exe.
// ---------------------------------------------------------------------------
function DesinstalarAnterior(): String;
var
  Clave, Carpeta, Uninst: String;
  Codigo, I: Integer;
begin
  Result := '';
  Clave := 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{#AppIdUninst}';
  if not RegQueryStringValue(HKLM, Clave, 'InstallLocation', Carpeta) then
    Exit;
  Carpeta := RemoveBackslashUnlessRoot(Carpeta);
  if CompareText(Carpeta, RemoveBackslashUnlessRoot(ExpandConstant('{app}'))) = 0 then
    Exit;
  if not RegQueryStringValue(HKLM, Clave, 'UninstallString', Uninst) then
    Exit;
  Uninst := RemoveQuotes(Uninst);
  Log('FoxPack: desinstalando la anterior de ' + Carpeta);
  if not Exec(Uninst, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART', '', SW_HIDE,
              ewWaitUntilTerminated, Codigo) then
  begin
    Result := 'No se pudo desinstalar FoxPack de ' + Carpeta;
    Exit;
  end;
  for I := 1 to 60 do
  begin
    if not FileExists(AddBackslash(Carpeta) + 'foxpack.exe') then
      Break;
    Sleep(500);
  end;
  if FileExists(AddBackslash(Carpeta) + 'foxpack.exe') then
    Result := 'FoxPack sigue instalado en ' + Carpeta + ': desinstalalo antes.';
end;

// ---------------------------------------------------------------------------
// FoxStack. Donde esta: COMPRUEBA EL FICHERO, no se cree la clave (FoxCli.iss
// con el taller). Devuelve '' si no hay un FoxStack utilizable.
// ---------------------------------------------------------------------------
function LeerCarpetaStack(): String;
var
  Dir: String;
begin
  Result := '';
  if RegQueryStringValue(HKLM32, 'SOFTWARE\irwinrodriguez.dev\FoxStack', 'InstallDir', Dir) then
  begin
    if FileExists(AddBackslash(Dir) + 'foxstack.exe') then
      Result := RemoveBackslashUnlessRoot(Dir);
  end;
end;

// El puesto es mas viejo que el que llevamos? Se compara como version, no como
// texto. Una version que no se entiende cuenta como vieja: se pone el nuestro.
function StackMasViejo(): Boolean;
var
  Puesta: String;
  vPuesta, vNuestra: Int64;
begin
  Result := True;
  if not RegQueryStringValue(HKLM32, 'SOFTWARE\irwinrodriguez.dev\FoxStack', 'Version', Puesta) then
    Exit;
  if not StrToVersion('{#StackVer}', vNuestra) then
    Exit;
  if not StrToVersion(Puesta, vPuesta) then
    Exit;
  Result := ComparePackedVersion(vPuesta, vNuestra) < 0;
end;

// Se lanza SU instalador en silencio en vez de copiar sus ficheros: FoxStack
// tambien es una clave, el PATH y el permiso de providers\. Nunca un MsgBox:
// FoxPack sin FoxStack sigue siendo FoxPack, y un fallo aqui solo va al log.
procedure InstalarStack();
var
  Codigo: Integer;
begin
  ExtractTemporaryFile('{#SetupStack}');
  Log('FoxPack: instalando FoxStack {#StackVer}');
  if not Exec(ExpandConstant('{tmp}\{#SetupStack}'), '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART',
              '', SW_HIDE, ewWaitUntilTerminated, Codigo) then
    Log('FoxPack: no se pudo ejecutar el setup de FoxStack; FoxPack se instala sin el')
  else if Codigo <> 0 then
    Log('FoxPack: el setup de FoxStack termino con ' + IntToStr(Codigo) + '; FoxPack se instala sin el')
  else
    Log('FoxPack: FoxStack instalado en ' + LeerCarpetaStack());
end;

// Los cuatro casos de FoxCli.iss con el taller.
procedure PonerStack();
begin
  if LeerCarpetaStack() = '' then
    InstalarStack()                      // no esta, o la clave apunta al vacio
  else if StackMasViejo() then
    InstalarStack()                      // esta, pero mas viejo
  else
    Log('FoxPack: FoxStack ya esta en ' + LeerCarpetaStack() + ', igual o mas nuevo; no se toca');
end;

function JsonTexto(S: String): String;
begin
  StringChangeEx(S, '\', '\\', True);
  StringChangeEx(S, '"', '\"', True);
  Result := '"' + S + '"';
end;

// providers\foxpack\provider.json, SIEMPRE, tambien al actualizar: reescribirlo
// es lo que hace que un FoxStack arrancado recargue el proveedor. Lo ultimo de
// la instalacion, con foxpack.exe ya en su sitio.
procedure EscribirProveedor();
var
  Stack, Carpeta, Json: String;
begin
  Stack := LeerCarpetaStack();
  if Stack = '' then
  begin
    Log('FoxPack: sin FoxStack; no se registra el proveedor');
    Exit;
  end;
  Carpeta := Stack + '\providers\foxpack';
  if not ForceDirectories(Carpeta) then
  begin
    Log('FoxPack: no se pudo crear ' + Carpeta);
    Exit;
  end;
  Json := '{' + #13#10 +
    '  "id": "foxpack",' + #13#10 +
    '  "kind": "cli",' + #13#10 +
    '  "family": "stack",' + #13#10 +
    '  "exe": ' + JsonTexto(ExpandConstant('{app}\foxpack.exe')) + ',' + #13#10 +
    '  "description": "FoxPack: libraries for VFP projects, downloaded from GitHub at a fixed version"' + #13#10 +
    '}' + #13#10;
  if SaveStringsToUTF8FileWithoutBOM(Carpeta + '\provider.json', [Json], False) then
    Log('FoxPack: proveedor escrito en ' + Carpeta + '\provider.json')
  else
    Log('FoxPack: no se pudo escribir ' + Carpeta + '\provider.json');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := DesinstalarAnterior();
  if Result = '' then
    PonerStack();
end;

// ---------------------------------------------------------------------------
// Cerrar la carpeta (regla 14). icacls por SID: S-1-5-32-544 administradores,
// S-1-5-18 SYSTEM, S-1-5-32-545 usuarios. /inheritance:r quita lo heredado de
// C:\Programas, que incluye «Usuarios autentificados: Modificar».
// ---------------------------------------------------------------------------
procedure CerrarCarpeta();
var
  Codigo: Integer;
begin
  if not Exec(ExpandConstant('{sys}\icacls.exe'),
              '"' + ExpandConstant('{app}') + '" /inheritance:r ' +
              '/grant:r *S-1-5-32-544:(OI)(CI)F *S-1-5-18:(OI)(CI)F *S-1-5-32-545:(OI)(CI)RX',
              '', SW_HIDE, ewWaitUntilTerminated, Codigo) or (Codigo <> 0) then
  begin
    Log('FoxPack: icacls devolvio ' + IntToStr(Codigo));
    SuppressibleMsgBox('No se pudieron ajustar los permisos de ' + ExpandConstant('{app}') +
                       '. Cualquier usuario podria modificar FoxPack.', mbError, MB_OK, IDOK);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    CerrarCarpeta();
    EscribirProveedor();
  end;
end;

// ---------------------------------------------------------------------------
// El PATH del sistema, entre punto y coma y sin distinguir mayusculas.
// ---------------------------------------------------------------------------
function LeerPath(): String;
begin
  if not RegQueryStringValue(HKLM, 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
                             'Path', Result) then
    Result := '';
end;

// Esta ya la carpeta en el PATH? Se busca con los punto y coma alrededor
// para no confundir C:\FoxPack con C:\FoxPackViejo.
function FaltaEnPath(Carpeta: String): Boolean;
begin
  Result := Pos(';' + Uppercase(Carpeta) + ';', ';' + Uppercase(LeerPath()) + ';') = 0;
end;

// Al desinstalar, el proveedor se quita solo si es NUESTRO: su provider.json
// apunta a un exe de esta carpeta. Uno que alguien registro a mano con el
// mismo id y otro exe se queda (como FoxKit.iss, ronda 93 del canal FoxStack).
procedure QuitarProveedor(Stack: String);
var
  Carpeta, Nuestra: String;
  Json: AnsiString;
begin
  Carpeta := Stack + '\providers\foxpack';
  if not DirExists(Carpeta) then
    Exit;
  // La carpeta de FoxPack como va escrita en el JSON: las barras, dobladas.
  Nuestra := ExpandConstant('{app}\');
  StringChangeEx(Nuestra, '\', '\\', True);
  if LoadStringFromFile(Carpeta + '\provider.json', Json) and
     (Pos(Uppercase(Nuestra), Uppercase(String(Json))) = 0) then
  begin
    Log('FoxPack: ' + Carpeta + ' no apunta a ' + ExpandConstant('{app}') + '; se queda');
    Exit;
  end;
  if DelTree(Carpeta, True, True, True) then
    Log('FoxPack: quitado ' + Carpeta + '; FoxStack se queda')
  else
    Log('FoxPack: no se pudo quitar ' + Carpeta);
end;

// Al desinstalar, el proveedor de FoxStack (solo el nuestro, y FoxStack se
// queda) y la carpeta fuera del PATH (la anadio el instalador).
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Ruta, Carpeta, Stack: String;
  P: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    Stack := LeerCarpetaStack();
    if Stack <> '' then
      QuitarProveedor(Stack);
  end;
  if CurUninstallStep <> usPostUninstall then
    Exit;
  Ruta := ';' + LeerPath() + ';';
  Carpeta := ';' + ExpandConstant('{app}') + ';';
  P := Pos(Uppercase(Carpeta), Uppercase(Ruta));
  if P = 0 then
    Exit;
  Delete(Ruta, P, Length(Carpeta) - 1);
  Ruta := Copy(Ruta, 2, Length(Ruta) - 2);
  RegWriteExpandStringValue(HKLM, 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
                            'Path', Ruta);
end;
