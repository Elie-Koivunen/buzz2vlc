; buzz2vlc installer for Windows (Inno Setup 6). packaging/build.py compiles it with:
;   /DAppVersion=1.0.0  /DSourceDir=<the PyInstaller folder>  /DRepoDir=<the repository>
;   /DIconFile=<buzz2vlc.ico>  /DOutputDir=<folder>  /DVlcVersion=3.0.24  /DVlcSha256=<hex>
;
; Checks for VLC media player. When it is missing, a wizard page offers to download VLC's
; official 64-bit Windows Installer package (MSI) from videolan.org, accepted only with the
; expected SHA-256, and install it with msiexec (a standard silent mode, /qn, and a log).
; Installs for the current user by default (no administrator rights needed);
; "Install for all users" is offered on the first page.
;
; Command line, besides Inno Setup's own (/SILENT, /VERYSILENT, /DIR=, /CURRENTUSER,
; /ALLUSERS, /LOG= ...):
;   /INSTALLVLC=1   in a silent install, also download and install VLC when it is missing

#ifndef AppVersion
  #error Pass /DAppVersion=<version>
#endif
#ifndef SourceDir
  #error Pass /DSourceDir=<the built program folder>
#endif
#ifndef RepoDir
  #error Pass /DRepoDir=<the repository folder>
#endif
#ifndef IconFile
  #error Pass /DIconFile=<buzz2vlc.ico>
#endif
#ifndef OutputDir
  #error Pass /DOutputDir=<folder>
#endif
#ifndef VlcVersion
  #error Pass /DVlcVersion=<VLC version offered for download>
#endif
#ifndef VlcSha256
  #error Pass /DVlcSha256=<SHA-256 of that VLC MSI package>
#endif

#define AppName "buzz2vlc"
#define AppUrl "https://github.com/Elie-Koivunen/buzz2vlc"
#define VlcUrl "https://download.videolan.org/pub/videolan/vlc/" + VlcVersion + "/win64/vlc-" + VlcVersion + "-win64.msi"

[Setup]
AppId={{37AF4F58-BC38-4727-932F-7E2541569035}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Elie Koivunen
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
LicenseFile={#RepoDir}\LICENSE
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\buzz2vlc.exe
UninstallDisplayName={#AppName} {#AppVersion}
OutputDir={#OutputDir}
OutputBaseFilename=buzz2vlc-{#AppVersion}-windows-x64-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; an earlier version's program files, so no stale library stays behind
Type: filesandordirs; Name: "{app}\_internal"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\buzz2vlc.exe"; Comment: "Control VLC players with a PS2/PS3 Buzz controller"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\buzz2vlc.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\buzz2vlc.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
var
  VlcPage: TInputOptionWizardPage;
  DownloadPage: TDownloadWizardPage;

{ The vlc.exe buzz2vlc would use, or '' when VLC media player is not installed.
  Same places the program itself looks: VLC's registry key, then Program Files. }
function VlcExe(): String;
var
  Path: String;
begin
  Result := '';
  if RegQueryStringValue(HKLM64, 'SOFTWARE\VideoLAN\VLC', '', Path) and FileExists(Path) then
    Result := Path
  else if RegQueryStringValue(HKLM32, 'SOFTWARE\VideoLAN\VLC', '', Path) and FileExists(Path) then
    Result := Path
  else if FileExists(ExpandConstant('{commonpf64}\VideoLAN\VLC\vlc.exe')) then
    Result := ExpandConstant('{commonpf64}\VideoLAN\VLC\vlc.exe')
  else if FileExists(ExpandConstant('{commonpf32}\VideoLAN\VLC\vlc.exe')) then
    Result := ExpandConstant('{commonpf32}\VideoLAN\VLC\vlc.exe');
end;

function OnDownloadProgress(const Url, FileName: String; const Progress, ProgressMax: Int64): Boolean;
begin
  if (ProgressMax > 0) and (Progress = ProgressMax) then
    Log('Downloaded ' + FileName);
  Result := True;
end;

{ Installs the downloaded VLC package with msiexec and waits for it; msiexec writes its
  own log to %TEMP%\buzz2vlc-vlc-install.log. Interactive: VLC's own install wizard, which
  asks for administrator rights when it starts installing. Silent: no UI (/qn), so msiexec
  itself is started with administrator rights ("runas": a UAC prompt unless Setup already
  has them). ShellExec, not Exec: only ShellExec can elevate. }
procedure RunVlcSetup(Silent: Boolean);
var
  Verb, Params: String;
  ResultCode: Integer;
begin
  Params := '/i "' + ExpandConstant('{tmp}\vlc-setup.msi') + '" /norestart /l*v "' +
    ExpandConstant('{%TEMP}\buzz2vlc-vlc-install.log') + '"';
  if Silent then
  begin
    Verb := 'runas';
    Params := Params + ' /qn';
  end
  else
    Verb := '';
  Log('Starting msiexec ' + Params);
  if ShellExec(Verb, ExpandConstant('{sys}\msiexec.exe'), Params, '', SW_SHOW, ewWaitUntilTerminated, ResultCode) then
    Log('msiexec finished with exit code ' + IntToStr(ResultCode) + ' (0 = installed, 3010 = installed, restart needed, 1602 = cancelled)')
  else
    Log('msiexec could not be started: ' + SysErrorMessage(ResultCode));
end;

procedure InitializeWizard;
begin
  VlcPage := CreateInputOptionPage(wpSelectTasks,
    'VLC media player',
    'buzz2vlc plays your playlists in VLC media player.',
    'VLC media player was not found on this computer, and buzz2vlc needs it.' + #13#10#13#10 +
    'Setup can download the official VLC {#VlcVersion} package (64-bit, about 63 MB) from ' +
    'videolan.org, check that it is genuine, and install it for you. Installing VLC needs ' +
    'administrator rights; Windows will ask.',
    True, False);
  VlcPage.Add('Download and install VLC {#VlcVersion} now (recommended)');
  VlcPage.Add('Skip: I will install VLC myself');
  VlcPage.SelectedValueIndex := 0;
  DownloadPage := CreateDownloadPage(SetupMessage(msgWizardPreparing), SetupMessage(msgPreparingDesc), @OnDownloadProgress);
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = VlcPage.ID) and (VlcExe() <> '');
end;

{ Interactive installs only: Inno Setup calls NextButtonClick in silent installs too
  (it simulates the clicks), where VLC's install wizard would wait for a user who isn't
  there. Silent installs go through PrepareToInstall below instead. }
function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = wpReady) and not WizardSilent and (VlcExe() = '') and (VlcPage.SelectedValueIndex = 0) then
  begin
    DownloadPage.Clear;
    DownloadPage.Add('{#VlcUrl}', 'vlc-setup.msi', '{#VlcSha256}');
    DownloadPage.Show;
    try
      try
        DownloadPage.Download;
        DownloadPage.SetText('Installing VLC media player...',
          'Follow VLC''s installer. buzz2vlc setup continues when it closes.');
        RunVlcSetup(False);
      except
        if DownloadPage.AbortedByUser then
          Log('The VLC download was cancelled')
        else
          SuppressibleMsgBox('VLC media player could not be downloaded: ' + AddPeriod(GetExceptionMessage),
            mbError, MB_OK, IDOK);
      end;
    finally
      DownloadPage.Hide;
    end;
    if VlcExe() = '' then
      SuppressibleMsgBox('VLC media player is still not installed. buzz2vlc will be installed anyway; ' +
        'install VLC from https://www.videolan.org/vlc/ before using it.', mbInformation, MB_OK, IDOK);
  end;
end;

{ Silent installs show no pages: /INSTALLVLC=1 asks for the same VLC download here. }
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if WizardSilent and (VlcExe() = '') then
  begin
    if ExpandConstant('{param:INSTALLVLC|0}') = '1' then
    begin
      try
        DownloadTemporaryFile('{#VlcUrl}', 'vlc-setup.msi', '{#VlcSha256}', @OnDownloadProgress);
        RunVlcSetup(True);
      except
        Log('VLC media player could not be downloaded: ' + GetExceptionMessage);
      end;
      if VlcExe() = '' then
        Log('VLC media player is still not installed')
      else
        Log('VLC media player is installed: ' + VlcExe());
    end
    else
      Log('VLC media player was not found; /INSTALLVLC=1 installs it in a silent install');
  end;
end;
