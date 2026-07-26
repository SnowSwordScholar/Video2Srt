#define AppName "Video2Srt"

#ifndef AppVersion
#define AppVersion "1.0.0"
#endif

#ifndef VersionInfoVersion
#define VersionInfoVersion "1.0.0.0"
#endif

#ifndef PackageRoot
#define PackageRoot "..\build\Video2Srt-package"
#endif

#ifndef OutputDir
#define OutputDir "..\dist\installer"
#endif

#ifndef OutputBaseFilename
#define OutputBaseFilename "Video2Srt-Setup"
#endif

[Setup]
AppId={{D50E9B13-6B63-4638-AE78-4EE659CE9E79}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Video2Srt Contributors
AppPublisherURL=https://github.com/
AppSupportURL=https://github.com/
AppUpdatesURL=https://github.com/
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
SetupIconFile=..\flutter_app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Video2Srt.exe
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
VersionInfoCompany=Video2Srt Contributors
VersionInfoDescription=Video2Srt Setup
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#VersionInfoVersion}
VersionInfoVersion={#VersionInfoVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#PackageRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\Video2Srt.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\Video2Srt.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Video2Srt.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
