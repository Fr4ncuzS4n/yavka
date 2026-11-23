; Инсталлятор Windows: собирается релизным workflow (job windows)
; через Inno Setup. Версия передаётся при вызове:
;   iscc /DAppVersion=0.1.1 installer.iss
; Версия берётся из pubspec.yaml без номера сборки (0.1.1+2 → 0.1.1).

[Setup]
AppId={{8F3C2D91-4A7E-4B6F-9C1D-2E5A8B7F6C01}}
AppName=Явка
AppVersion={#AppVersion}
AppPublisher=Fr4ncuzS4n
AppPublisherURL=https://github.com/Fr4ncuzS4n/yavka
DefaultDirName={autopf}\Yavka
DefaultGroupName=Явка
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename=yavka-windows-x64-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
; Путь к иконке — относительно этого файла.
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\yavka.exe

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; \
  GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Сборка Flutter: папка Release целиком (exe, DLL и data).
; Путь — относительно этого файла.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
  Flags: recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Явка"; Filename: "{app}\yavka.exe"
Name: "{autodesktop}\Явка"; Filename: "{app}\yavka.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\yavka.exe"; Description: "Запустить Явку"; \
  Flags: nowait postinstall skipifsilent
