; The Windows setup program, when Inno Setup 6 is installed (build.ps1 finds ISCC.exe and passes the defines):
;
;   ISCC.exe /DAppVersion=0.1.0 /DStageDir=<the staged Ceres directory> /DOutputDir=<dist> /DOutputName=<name> ceres.iss
;
; It installs for the current user, without administrator rights, into %LOCALAPPDATA%\Programs\Ceres (the same
; place install.ps1 uses), sets CERES_PATH to that directory and puts it on the user's PATH; its uninstaller, in
; Settings > Apps, takes all of it away again. Without Inno Setup, build.ps1 makes a setup program with IExpress
; instead, which runs install.ps1.

#ifndef AppVersion
  #error Pass /DAppVersion=<version>
#endif
#ifndef StageDir
  #error Pass /DStageDir=<the staged Ceres directory>
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif
#ifndef OutputName
  #define OutputName "ceres-" + AppVersion + "-windows-x64-setup"
#endif

[Setup]
AppId={{7C1E6C1B-3E7A-4F55-9B0B-6A2D1D0C3E51}
AppName=Ceres
AppVersion={#AppVersion}
AppVerName=Ceres {#AppVersion}
AppPublisher=Ceres
DefaultDirName={localappdata}\Programs\Ceres
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ChangesEnvironment=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile={#StageDir}\LICENSE.txt
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
Compression=lzma2
SolidCompression=yes
UninstallDisplayName=Ceres {#AppVersion}
WizardStyle=modern

[Files]
; The whole package but the zip installer's own scripts: this setup does their job, and its uninstaller replaces
; theirs.
Source: "{#StageDir}\*"; DestDir: "{app}"; Excludes: "install.ps1,install.cmd,uninstall.ps1,uninstall.cmd"; Flags: recursesubdirs createallsubdirs ignoreversion

[InstallDelete]
; An earlier version's library and shell go before this one's are copied: a header that is gone must not stay.
Type: filesandordirs; Name: "{app}\stdlib"
Type: filesandordirs; Name: "{app}\shell"

[Registry]
Root: HKCU; Subkey: "Environment"; ValueType: string; ValueName: "CERES_PATH"; ValueData: "{app}"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; Check: NotOnPath(ExpandConstant('{app}'))

[Code]
function NotOnPath(Directory: string): Boolean;
var
  Path: string;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', Path) then
    Result := True
  else
    Result := Pos(';' + Lowercase(Directory) + ';', ';' + Lowercase(Path) + ';') = 0;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Path, Directory: string;
  Start: Integer;
begin
  if CurUninstallStep <> usPostUninstall then
    Exit;
  if not RegQueryStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', Path) then
    Exit;
  Directory := ExpandConstant('{app}');
  Path := ';' + Path + ';';
  Start := Pos(';' + Lowercase(Directory) + ';', Lowercase(Path));
  if Start = 0 then
    Exit;
  Delete(Path, Start, Length(Directory) + 1);
  Path := Copy(Path, 2, Length(Path) - 2);
  RegWriteExpandStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', Path);
end;
