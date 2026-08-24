#define MyAppName "Bills Maker"
#define MyAppVersion "1.1.24"
#define MyAppPublisher "Bills Maker"
#define MyAppExeName "bills_maker.exe"

[Setup]
AppId={{4D09B0D5-0C8D-4D74-994A-F9E02A3AB1F4}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\Bills Maker
DefaultGroupName=Bills Maker
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\release-native
OutputBaseFilename=Bills-Maker-Setup-native-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern dynamic
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear un acceso directo en el escritorio"; GroupDescription: "Accesos directos:"; Flags: unchecked

[Files]
Source: "..\..\release-native\Bills-Maker-Windows-native-1.1.24\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Bills Maker"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\Bills Maker"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir Bills Maker"; Flags: nowait postinstall skipifsilent
