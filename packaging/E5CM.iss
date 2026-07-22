#define MyAppName "E5CM"
#ifndef MyAppVersion
#define MyAppVersion "godot-2.0.3"
#endif
#ifndef MyAppFileVersion
#define MyAppFileVersion "2.0.3.0"
#endif
#define MyAppPublisher "E5CM"
#define MyAppExeName "E5CM.exe"

[Setup]
AppId={{FBCDB651-746D-45D1-AFA5-2E9B3262899D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={userdocs}\E5CM
DefaultGroupName=E5CM
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\release
OutputBaseFilename=E5CM-Setup-{#MyAppVersion}
SetupIconFile=..\assets\branding\e5cm.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/normal
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
VersionInfoVersion={#MyAppFileVersion}
VersionInfoCompany=E5CM
VersionInfoDescription=E5CM Installer
VersionInfoProductName=E5CM
VersionInfoProductVersion={#MyAppFileVersion}

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\release\E5CM\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autodesktop}\E5CM"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\E5CM"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\E5CM（兼容模式）"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--rendering-method gl_compatibility"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 E5CM"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 E5CM"; Flags: nowait postinstall skipifsilent
