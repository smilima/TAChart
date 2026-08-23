{
 *****************************************************************************
  This file is part of the Delphi/VCL port of TAChart.

  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  Ported from the TGraph component (Source\TG.GPU.pas), where this code was
  written and proven.  Types carry TAChart's TChart... prefix so one project
  can use both components without a name clash.
}

unit TAGPU;

{$I TAChartDefines.inc}

{ TAChart — graphics adapter discovery and per-application GPU preference.

  On a hybrid laptop (an integrated Intel or AMD adapter driving the display
  plus a discrete NVIDIA or AMD one) Windows decides which GPU an OpenGL
  application renders on. Left alone it picks the integrated adapter, which on
  a large fast line costs an order of magnitude or more.

  What can and cannot be done from here, precisely:

  - The choice is made by the driver shim when the process starts. Nothing a
    DLL or package does later can move an existing OpenGL context to another
    adapter, so there is no runtime "switch GPU now".
  - The two mechanisms that do work are (a) symbols exported from the
    executable, which must be present at link time and are therefore the
    application's job, not a package's, and (b) the per-application preference
    under HKCU\Software\Microsoft\DirectX\UserGpuPreferences, which any code
    can write and which takes effect the next time that executable starts.
    This unit implements (b).
  - Windows offers "power saving" or "high performance" rather than a named
    adapter, so this cannot pin a specific card - it asks for the class of
    adapter and the driver resolves it.

  DetectAdapters lists what is installed, which is what makes the choice
  meaningful to a developer at design time. Confirm the outcome with
  TCustomGraph.GLRenderer, never by assuming a preference took. }

interface

type
  { What to ask Windows for on behalf of an executable. }
  TChartGPUPreference = (
    gpSystemDefault,     // no entry: Windows decides, which means integrated
    gpPowerSaving,       // GpuPreference=1
    gpHighPerformance    // GpuPreference=2, the discrete adapter
  );

  TChartAdapterInfo = record
    Description: string;    // e.g. 'NVIDIA GeForce RTX 5050 Laptop GPU'
    DriverVersion: string;
    DriverDate: string;
    { True for adapters whose description matches a known discrete vendor
      family. A heuristic for presentation only - never branch behaviour on
      it, because the driver, not this unit, resolves the preference. }
    LikelyDiscrete: Boolean;
  end;
  TChartAdapterInfoArray = array of TChartAdapterInfo;

{ Every display adapter with an installed driver, integrated ones included.
  Reads the driver class key, so it works at design time and in a compiled
  application, needs no COM or WMI, and does not require a display to be
  attached - which matters, because the discrete adapter usually has none. }
function DetectAdapters: TChartAdapterInfoArray;

{ True when more than one adapter is installed, i.e. there is a choice to
  make. Single-GPU desktops get no benefit from any of this. }
function HasSwitchableGraphics: Boolean;

{ The running executable. At design time this is the IDE, not the application
  being designed - see SetGPUPreference. }
function HostExecutablePath: string;

function GetGPUPreference(const AExePath: string): TChartGPUPreference;

{ Writes (or clears, for gpSystemDefault) the preference for AExePath under
  HKEY_CURRENT_USER. No elevation needed. Takes effect the next time that
  executable starts; it cannot affect the current process.

  AExePath must be the application's own executable. Passing the IDE's path
  would set the preference for the IDE, so a design-time caller has to supply
  the project's output path rather than HostExecutablePath. }
procedure SetGPUPreference(const AExePath: string;
  APreference: TChartGPUPreference);

implementation

uses
  System.SysUtils, System.Classes, System.Win.Registry, Winapi.Windows;

const
  { The display adapter device class. }
  DisplayClassKey =
    'SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}';
  PreferenceKey = 'Software\Microsoft\DirectX\UserGpuPreferences';

//------------------------------------------------------------------------------
function LooksDiscrete(const ADescription: string): Boolean;
var
  S: string;
begin
  S := LowerCase(ADescription);
  { Intel has no discrete part in this family, and the integrated AMD parts
    carry 'Radeon(TM) Graphics' without a model number. Deliberately crude:
    it only decides how the list is presented. }
  Result := (Pos('nvidia', S) > 0) or (Pos('geforce', S) > 0) or
    (Pos('quadro', S) > 0) or (Pos('rtx', S) > 0) or
    (Pos('radeon rx', S) > 0) or (Pos('arc', S) > 0);
end;

//------------------------------------------------------------------------------
function DetectAdapters: TChartAdapterInfoArray;
var
  Reg: TRegistry;
  Keys: TStringList;
  I, N: Integer;
  Desc: string;
  Info: TChartAdapterInfo;
begin
  Result := nil;
  Reg := TRegistry.Create(KEY_READ or KEY_WOW64_64KEY);
  Keys := TStringList.Create;
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if not Reg.OpenKeyReadOnly(DisplayClassKey) then
      Exit;
    Reg.GetKeyNames(Keys);
    Reg.CloseKey;
    N := 0;
    for I := 0 to Keys.Count - 1 do
    begin
      // Adapter instances are the four-digit subkeys; skip Configuration etc.
      if (Length(Keys[I]) <> 4) or not CharInSet(Keys[I][1], ['0'..'9']) then
        Continue;
      if not Reg.OpenKeyReadOnly(DisplayClassKey + '\' + Keys[I]) then
        Continue;
      try
        if not Reg.ValueExists('DriverDesc') then
          Continue;
        Desc := Reg.ReadString('DriverDesc');
        if Desc = '' then
          Continue;
        Info := Default(TChartAdapterInfo);
        Info.Description := Desc;
        if Reg.ValueExists('DriverVersion') then
          Info.DriverVersion := Reg.ReadString('DriverVersion');
        if Reg.ValueExists('DriverDate') then
          Info.DriverDate := Reg.ReadString('DriverDate');
        Info.LikelyDiscrete := LooksDiscrete(Desc);
        SetLength(Result, N + 1);
        Result[N] := Info;
        Inc(N);
      finally
        Reg.CloseKey;
      end;
    end;
  finally
    Keys.Free;
    Reg.Free;
  end;
end;

//------------------------------------------------------------------------------
function HasSwitchableGraphics: Boolean;
begin
  Result := Length(DetectAdapters) > 1;
end;

//------------------------------------------------------------------------------
function HostExecutablePath: string;
begin
  Result := ParamStr(0);
end;

//------------------------------------------------------------------------------
function GetGPUPreference(const AExePath: string): TChartGPUPreference;
var
  Reg: TRegistry;
  Value: string;
begin
  Result := gpSystemDefault;
  if AExePath = '' then
    Exit;
  Reg := TRegistry.Create(KEY_READ or KEY_WOW64_64KEY);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKeyReadOnly(PreferenceKey) then
      Exit;
    try
      if not Reg.ValueExists(AExePath) then
        Exit;
      Value := LowerCase(Reg.ReadString(AExePath));
      if Pos('gpupreference=2', Value) > 0 then
        Result := gpHighPerformance
      else if Pos('gpupreference=1', Value) > 0 then
        Result := gpPowerSaving;
    finally
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

//------------------------------------------------------------------------------
procedure SetGPUPreference(const AExePath: string;
  APreference: TChartGPUPreference);
var
  Reg: TRegistry;
begin
  if AExePath = '' then
    Exit;
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE or KEY_WOW64_64KEY);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKey(PreferenceKey, True) then
      Exit;
    try
      case APreference of
        gpPowerSaving:
          Reg.WriteString(AExePath, 'GpuPreference=1;');
        gpHighPerformance:
          Reg.WriteString(AExePath, 'GpuPreference=2;');
      else
        // gpSystemDefault means "no opinion", so remove the entry entirely
        // rather than writing GpuPreference=0.
        if Reg.ValueExists(AExePath) then
          Reg.DeleteValue(AExePath);
      end;
    finally
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

end.
