; =============================================================================
; FoxPack.iss -- instala la CLI de FoxPack
;
; QUE INSTALA
;   foxpack.exe con su DLL y el runtime de VFP (lo que arma pack.ps1: ocho
;   ficheros, activacion COM por manifiesto y sin registro), el README, la
;   licencia y docs\foxpack.md.
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
DefaultDirName={autopf}\FoxPack
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
