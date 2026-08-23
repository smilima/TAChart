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
    { PCI vendor: $10DE NVIDIA, $1002/$1022 AMD, $8086 Intel. }
    VendorId: Word;
    { Bytes of memory belonging to the adapter itself.  Windows records this
      only for adapters that have their own memory, so a non-zero value is
      what really separates a discrete adapter from an integrated one -
      including an Intel Arc, which a vendor-name test gets wrong. }
    DedicatedMemory: UInt64;
    { True when the adapter has dedicated memory.  Unlike the old name test
      this comes from the driver, so it can be branched on. }
    IsDiscrete: Boolean;
    { Ranking score, larger is more capable.  See RankAdapters. }
    Score: UInt64;
    { Retained for source compatibility; now mirrors IsDiscrete. }
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

{ Every adapter, most capable first.  Ranked on what the driver reports -
  dedicated memory, then vendor class - rather than on the adapter name. }
function RankAdapters: TChartAdapterInfoArray;

{ The most capable adapter.  False when none could be read at all. }
function BestAdapter(out AAdapter: TChartAdapterInfo): Boolean;

{ True when AGLRenderer - what OpenGL reports for the context in use - names
  the same adapter as AAdapter.  Drivers decorate the renderer string
  ('... /PCIe/SSE2'), so the comparison is deliberately lenient. }
function RendererMatchesAdapter(const AGLRenderer: string;
  const AAdapter: TChartAdapterInfo): Boolean;

{ Asks Windows to run AExePath on the most capable adapter.

  Returns True when the preference had to be changed, which also means the
  running process is still on the old adapter: Windows resolves this at
  process start, so only the next launch picks it up.  Returns False when the
  preference was already right, or when there is nothing to choose between.

  AExePath must be the application's own executable.  At design time
  HostExecutablePath is the IDE, so a design-time caller has to pass the
  project's output path rather than setting a preference for bds.exe. }
function PreferBestGPU(const AExePath: string): Boolean;

type
  { What the application intends to draw.  The adapter that suits it is not
    always the most capable one - see PreferenceForWorkload. }
  TChartGPUWorkload = record
    PointCount: Int64;   // the largest series the application will draw
    Decimated: Boolean;  // whether that series reduces before drawing
  end;

var
  { Point counts at or above which the discrete adapter is the faster choice.
    Measured on a switchable-graphics laptop - an RTX 5050 against the Intel
    part it shares the display with - vsync off and the GPU drained,
    milliseconds per frame, discrete / integrated:

                     full detail            decimated
        100,000    3.42 / 2.46  integrated  3.79 / 1.46  integrated
      1,000,000    1.50 / 1.59  tie         1.60 / 1.23  integrated
      5,000,000    2.84 / 5.55  discrete    1.42 / 1.23  integrated
     10,000,000    5.26 / 10.88 discrete    2.85 / 3.33  discrete

    Drawing every vertex is real work, and the discrete adapter takes the lead
    somewhere between one and five million.  A decimated series is a few
    thousand vertices however long it is, so there is nothing for a larger GPU
    to do, and on a laptop the finished frame still has to be copied back to
    the display the integrated adapter owns - which is why the integrated one
    stays ahead there until the reduction itself becomes the expensive part.

    Variables rather than constants, so an application on different hardware
    can retune them without rebuilding TAChart. }
  ChartGPUFullDetailThreshold: Int64 = 2000000;
  ChartGPUDecimatedThreshold: Int64 = 8000000;

{ The adapter class that suits AWorkload.  Deliberately not the same question
  as BestAdapter, which answers "which is the most capable": in the
  configuration most charts run in - decimation on - the most capable adapter
  is the slower one. }
function PreferenceForWorkload(
  const AWorkload: TChartGPUWorkload): TChartGPUPreference;

{ Records the preference PreferenceForWorkload asks for.  Returns True when it
  had to be changed, which also means the running process is still on the
  previous adapter: Windows resolves this at process start, so only the next
  launch picks it up.  An application that wants the choice to take effect has
  to restart itself; it cannot be changed from inside. }
function ApplyWorkloadPreference(const AExePath: string;
  const AWorkload: TChartGPUWorkload): Boolean;

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
{ 'PCI\VEN_10DE&DEV_2D98&...' -> $10DE.  Case varies between entries. }
function ParseVendorId(const AMatchingDeviceId: string): Word;
var
  S: string;
  P: Integer;
begin
  Result := 0;
  S := UpperCase(AMatchingDeviceId);
  P := Pos('VEN_', S);
  if P = 0 then
    Exit;
  Inc(P, 4);
  if Length(S) < P + 3 then
    Exit;
  Result := Word(StrToIntDef('$' + Copy(S, P, 4), 0));
end;

//------------------------------------------------------------------------------
{ Memory belonging to the adapter itself, or 0 when it has none.

  Only qwMemorySize answers this.  MemorySize looks like the same thing and is
  not: Windows writes it for integrated adapters too, reporting the system
  memory they borrow - this machine's Intel part claims 2 GB that way - so
  treating it as dedicated memory would classify every integrated adapter as
  discrete.  It is deliberately not consulted.

  The value is a REG_QWORD, which TRegistry has no reader for, so it is
  fetched through the API.  Some drivers write it as REG_BINARY instead. }
function ReadDedicatedMemory(AReg: TRegistry): UInt64;
const
  VALUE_NAME = 'HardwareInformation.qwMemorySize';
  REG_QWORD_ = 11;
var
  DataType, Size: DWORD;
  Buf: UInt64;
begin
  Result := 0;
  Buf := 0;
  Size := SizeOf(Buf);
  DataType := 0;
  if RegQueryValueEx(AReg.CurrentKey, PChar(VALUE_NAME), nil, @DataType,
       PByte(@Buf), @Size) <> ERROR_SUCCESS then
    Exit;
  case DataType of
    REG_QWORD_:
      Result := Buf;
    REG_BINARY:
      if Size >= SizeOf(UInt64) then
        Result := Buf
      else if Size >= SizeOf(Cardinal) then
        Result := PCardinal(@Buf)^;
    REG_DWORD:
      Result := PCardinal(@Buf)^;
  end;
end;

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
        if Reg.ValueExists('MatchingDeviceId') then
          Info.VendorId := ParseVendorId(Reg.ReadString('MatchingDeviceId'));
        Info.DedicatedMemory := ReadDedicatedMemory(Reg);
        { Dedicated memory is the driver's own answer, and the reliable one.
          The name test only stands in for an older discrete part that records
          no qwMemorySize at all. }
        Info.IsDiscrete := (Info.DedicatedMemory > 0) or LooksDiscrete(Desc);
        Info.LikelyDiscrete := Info.IsDiscrete;
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
{ How capable an adapter looks, from what the driver records about it.

  Dedicated memory dominates: an adapter with memory of its own is a discrete
  one, and among discrete adapters more memory tracks the bigger part closely
  enough for choosing a default.  Vendor only breaks ties between adapters
  that report the same memory, and only to prefer a vendor that ships discrete
  parts at all.  Nothing here matches on the marketing name, so a part this
  code has never heard of still ranks correctly. }
function ScoreAdapter(const AInfo: TChartAdapterInfo): UInt64;
const
  DISCRETE_BASE = UInt64(1) shl 60;
  VENDOR_BONUS  = UInt64(1) shl 40;
begin
  Result := 0;
  if AInfo.IsDiscrete then
    Result := Result + DISCRETE_BASE;
  { Megabytes, so the memory term cannot reach the vendor term. }
  Result := Result + (AInfo.DedicatedMemory div (1024 * 1024));
  case AInfo.VendorId of
    $10DE, $1002, $1022: Result := Result + VENDOR_BONUS;   // NVIDIA, AMD
  end;
end;

//------------------------------------------------------------------------------
function RankAdapters: TChartAdapterInfoArray;
var
  I, J: Integer;
  Tmp: TChartAdapterInfo;
begin
  Result := DetectAdapters;
  for I := 0 to High(Result) do
    Result[I].Score := ScoreAdapter(Result[I]);
  // Insertion sort: there are never more than a handful of adapters.
  for I := 1 to High(Result) do
  begin
    Tmp := Result[I];
    J := I - 1;
    while (J >= 0) and (Result[J].Score < Tmp.Score) do
    begin
      Result[J + 1] := Result[J];
      Dec(J);
    end;
    Result[J + 1] := Tmp;
  end;
end;

//------------------------------------------------------------------------------
function BestAdapter(out AAdapter: TChartAdapterInfo): Boolean;
var
  Ranked: TChartAdapterInfoArray;
begin
  Ranked := RankAdapters;
  Result := Length(Ranked) > 0;
  if Result then
    AAdapter := Ranked[0]
  else
    AAdapter := Default(TChartAdapterInfo);
end;

//------------------------------------------------------------------------------
function RendererMatchesAdapter(const AGLRenderer: string;
  const AAdapter: TChartAdapterInfo): Boolean;
var
  R, D: string;
begin
  { The driver appends its own decorations, e.g.
      'NVIDIA GeForce RTX 5050 Laptop GPU/PCIe/SSE2'
    against a registry description of
      'NVIDIA GeForce RTX 5050 Laptop GPU'
    so containment either way is the right test rather than equality. }
  Result := false;
  R := UpperCase(Trim(AGLRenderer));
  D := UpperCase(Trim(AAdapter.Description));
  if (R = '') or (D = '') then
    Exit;
  Result := (Pos(D, R) > 0) or (Pos(R, D) > 0);
end;

//------------------------------------------------------------------------------
function PreferenceForWorkload(
  const AWorkload: TChartGPUWorkload): TChartGPUPreference;
var
  Threshold: Int64;
begin
  { One adapter means nothing to ask for, and recording a preference would
    only mislead. }
  if not HasSwitchableGraphics then
  begin
    Result := gpSystemDefault;
    Exit;
  end;

  if AWorkload.Decimated then
    Threshold := ChartGPUDecimatedThreshold
  else
    Threshold := ChartGPUFullDetailThreshold;

  if AWorkload.PointCount >= Threshold then
    Result := gpHighPerformance
  else
    Result := gpPowerSaving;
end;

//------------------------------------------------------------------------------
function ApplyWorkloadPreference(const AExePath: string;
  const AWorkload: TChartGPUWorkload): Boolean;
var
  Wanted: TChartGPUPreference;
begin
  Result := false;
  Wanted := PreferenceForWorkload(AWorkload);
  if Wanted = gpSystemDefault then
    Exit;
  if GetGPUPreference(AExePath) = Wanted then
    Exit;
  SetGPUPreference(AExePath, Wanted);
  Result := true;
end;

//------------------------------------------------------------------------------
function PreferBestGPU(const AExePath: string): Boolean;
var
  Ranked: TChartAdapterInfoArray;
  Wanted: TChartGPUPreference;
begin
  Result := false;
  Ranked := RankAdapters;
  { With one adapter there is nothing to choose, and setting a preference
    would only be misleading. }
  if Length(Ranked) < 2 then
    Exit;

  { Windows takes a class of adapter, not a named one, so the most this can
    say is 'the high-performance one'.  That is enough: the ranking above is
    what decides whether the high-performance adapter is actually the better
    one, and on every switchable-graphics machine it is. }
  if Ranked[0].IsDiscrete then
    Wanted := gpHighPerformance
  else
    Wanted := gpPowerSaving;

  if GetGPUPreference(AExePath) = Wanted then
    Exit;
  SetGPUPreference(AExePath, Wanted);
  Result := true;
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
