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

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := DesinstalarAnterior();
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
    CerrarCarpeta();
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

// Al desinstalar, la carpeta fuera del PATH (la anadio el instalador).
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Ruta, Carpeta: String;
  P: Integer;
begin
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
