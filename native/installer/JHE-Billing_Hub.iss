#define MyAppName "JHE Billing Hub"
#define MyAppVersion "1.1.24"
#define MyAppPublisher "JHE Billing Hub"
#define MyAppExeName "bills_maker.exe"

[Setup]
AppId={{4D09B0D5-0C8D-4D74-994A-F9E02A3AB1F4}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\JHE Billing Hub
DefaultGroupName=JHE Billing Hub
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\releases
OutputBaseFilename=JHE-Billing-Hub-Setup-native-{#MyAppVersion}
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
Source: "..\..\releases\JHE-Billing-Hub-Windows-native-1.1.24\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\JHE Billing Hub"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\JHE Billing Hub"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir JHE Billing Hub"; Flags: nowait postinstall skipifsilent
