; APL-WIN-014 post-incident enterprise installer candidate.
; This variant deliberately uses UseSetupLdr=no so Setup is NOT copied to and
; re-executed from TEMP. It is a multi-file installer bundle, not the public
; single-EXE 0.2.3 artifact.
#if Ver != 0x06070100
  #error Exact Inno Setup 6.7.1 is required
#endif
#ifndef AppVersion
  #error AppVersion must be supplied
#endif
#ifndef PayloadDir
  #error PayloadDir must be supplied
#endif
#ifndef RuntimeLabel
  #error RuntimeLabel must be supplied
#endif
#ifndef SetupBaseName
  #error SetupBaseName must be supplied
#endif

#define AppName "Arvectum Proxy Launcher"
#define AppPublisher "ООО «Арвектум»"
#define AppPublisherURL "https://arvectum.com"
#define AppSupportURL "https://github.com/arvectum1/proxy-launcher/issues"
#define AppDir "{userdocs}\ArvectumProxyLauncher"
#define RuntimeDir "{app}\runtime\" + RuntimeLabel
#define RuntimeExe RuntimeDir + "\Arvectum Proxy Launcher.exe"

[Setup]
AppId={{6A5A0706-4015-4EAF-BFA1-25EF435C9E1B}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppPublisherURL}
AppSupportURL={#AppSupportURL}
DefaultDirName={#AppDir}
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
OutputBaseFilename={#SetupBaseName}
OutputDir=..\out\appcontrol-installer
SetupIconFile=..\assets\arvectum.ico
UninstallDisplayIcon={#RuntimeExe}
Uninstallable=yes
UseSetupLdr=no
CloseApplications=force
CloseApplicationsFilter=*.exe,*.dll,*.pyd
RestartApplications=no
Compression=lzma2
SolidCompression=yes
UninstallLogging=yes

[Files]
; Static onedir runtime: every executable DLL/PYD is present before first launch.
; No product PowerShell helper and no product executable is extracted to {tmp}.
Source: "{#PayloadDir}\runtime\*"; DestDir: "{#RuntimeDir}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#PayloadDir}\appcontrol_installer_manifest.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\THIRD_PARTY_NOTICES.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\THIRD_PARTY_LICENSES\*"; DestDir: "{app}\THIRD_PARTY_LICENSES"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Arvectum Proxy Launcher"; Filename: "{#RuntimeExe}"; WorkingDir: "{#RuntimeDir}"
Name: "{autodesktop}\Arvectum Proxy Launcher"; Filename: "{#RuntimeExe}"; WorkingDir: "{#RuntimeDir}"

[UninstallDelete]
; Versioned static runtimes are isolated to avoid destructive pre-install cleanup.
Type: filesandordirs; Name: "{app}\runtime"
Type: files; Name: "{app}\appcontrol_installer_manifest.json"
Type: files; Name: "{app}\.arvectum-install-owner"
Type: dirifempty; Name: "{app}"

[Code]
function ExistingLauncher(): String;
var
  Candidate: String;
begin
  Candidate := ExpandConstant('{#RuntimeExe}');
  if FileExists(Candidate) then begin
    Result := Candidate;
    exit;
  end;

  // Migration path from sealed 0.2.3 layout.
  Candidate := ExpandConstant('{app}\Arvectum Proxy Launcher.exe');
  if FileExists(Candidate) then begin
    Result := Candidate;
    exit;
  end;

  Result := '';
end;

function RunRollback(const ExePath: String; var ErrorText: String): Boolean;
var
  ExitCode: Integer;
begin
  if ExePath = '' then begin
    Result := True;
    exit;
  end;

  Log('Running owned Launcher rollback before installer lifecycle mutation: ' + ExePath);
  Result := Exec(ExePath, '--rollback', ExtractFileDir(ExePath), SW_HIDE, ewWaitUntilTerminated, ExitCode);
  if (not Result) or (ExitCode <> 0) then begin
    ErrorText := 'Existing Launcher network rollback failed; lifecycle mutation is blocked. Exit code: ' + IntToStr(ExitCode);
    Result := False;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ErrorText: String;
begin
  Result := '';
  if not RunRollback(ExistingLauncher(), ErrorText) then
    Result := ErrorText;
end;

function IsOwnedRunValue(const Value: String): Boolean;
var
  L: String;
begin
  L := Lowercase(Value);
  Result := (Pos('arvectum proxy launcher.exe', L) > 0) and (Pos('--start', L) > 0);
end;

procedure RemoveOwnedRunValue(const ValueName: String);
var
  Value: String;
begin
  if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', ValueName, Value) then begin
    if IsOwnedRunValue(Value) then begin
      if RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', ValueName) then
        Log('Removed owned Run value: ' + ValueName)
      else
        Log('WARNING: failed to remove owned Run value: ' + ValueName);
    end else
      Log('Foreign/unknown Run value preserved: ' + ValueName);
  end;
end;

function SchTasksPath(): String;
begin
  if IsWin64 then
    Result := ExpandConstant('{sysnative}\schtasks.exe')
  else
    Result := ExpandConstant('{sys}\schtasks.exe');
end;

function LegacyTaskOwned(): Boolean;
var
  ExitCode, I: Integer;
  Output: TExecOutput;
  Text: String;
begin
  Result := False;
  try
    if not ExecAndCaptureOutput(SchTasksPath(), '/Query /TN "ArvectumProxyLauncher" /XML', '', SW_SHOWNORMAL, ewWaitUntilTerminated, ExitCode, Output) then
      exit;
    if (ExitCode <> 0) or Output.Error then
      exit;
    Text := '';
    if GetArrayLength(Output.StdOut) > 0 then begin
      for I := 0 to GetArrayLength(Output.StdOut) - 1 do
        Text := Text + Output.StdOut[I] + #10;
    end;
    Text := Lowercase(Text);
    Result := (Pos('arvectum proxy launcher.exe', Text) > 0) and (Pos('--start', Text) > 0);
  except
    Log('Legacy task ownership probe failed: ' + GetExceptionMessage);
    Result := False;
  end;
end;

procedure RemoveOwnedLegacyTask();
var
  ExitCode: Integer;
begin
  if not LegacyTaskOwned() then begin
    Log('Legacy scheduled task absent or not provably owned; preserved.');
    exit;
  end;
  if not Exec(SchTasksPath(), '/Delete /F /TN "ArvectumProxyLauncher"', '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then
    Log('WARNING: schtasks delete could not be started')
  else if ExitCode <> 0 then
    Log('WARNING: owned legacy task delete failed with exit code ' + IntToStr(ExitCode))
  else
    Log('Owned legacy scheduled task removed.');
end;

function InitializeUninstall(): Boolean;
var
  ErrorText: String;
begin
  Result := RunRollback(ExistingLauncher(), ErrorText);
  if not Result then begin
    SuppressibleMsgBox(ErrorText, mbError, MB_OK, IDOK);
    exit;
  end;

  RemoveOwnedRunValue('ArvectumProxyLauncher');
  RemoveOwnedRunValue('ArvectumProxyLauncherRecovery');
  RemoveOwnedLegacyTask();
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    SaveStringToFile(ExpandConstant('{app}\.arvectum-install-owner'), 'ARVECTUM_PROXY_LAUNCHER_INSTALL_OWNER' + #13#10, False);
  end;
end;
