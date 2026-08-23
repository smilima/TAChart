{
 *****************************************************************************
  This file is part of the Delphi/VCL port of TAChart.

  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  Stand-ins for the small number of LCL and FPC RTL declarations that TAChart
  uses outside the drawing back-end: the non-visual timer, the tick counter, a
  couple of virtual key codes, the TFPList enumerator, and two SysUtils/StrUtils
  routines that Free Pascal has and Delphi does not.
}

unit TALCLCompat;

{$I TAChartDefines.inc}

interface

uses
  Winapi.Windows, System.Classes, System.SysUtils, System.DateUtils,
  Vcl.ExtCtrls;

type
  // LCL's TCustomTimer and the VCL's TTimer have the same published surface
  // (Enabled, Interval, OnTimer), so an alias is enough.
  TCustomTimer = Vcl.ExtCtrls.TTimer;

  { TChartListEnumerator -- replaces FPC's TFPListEnumerator.

    TAChart derives typed enumerators from it (see TAChartUtils'
    TTypedFPListEnumerator<T>) to give TChartToolset, TChartAxisList and
    friends their for-in support. }
  TChartListEnumerator = class
  strict private
    FList: TList;
    FPosition: Integer;
  public
    constructor Create(AList: TList);
    function GetCurrent: Pointer;
    function MoveNext: Boolean;
    property Current: Pointer read GetCurrent;
  end;

const
  // LCL defines VK_UNKNOWN for "no key"; the Windows unit has no equivalent.
  VK_UNKNOWN = 0;

  // Already macros in winuser.h. {$NODEFINE} keeps them out of TALCLCompat.hpp
  // so C++Builder does not expand VK_SHIFT into `static const ... 0x10 = ...`.
  {$NODEFINE VK_SHIFT}
  {$NODEFINE VK_CONTROL}
  {$NODEFINE VK_MENU}
  {$NODEFINE VK_ESCAPE}
  {$NODEFINE VK_SPACE}
  {$NODEFINE SM_CYMENUCHECK}
  VK_SHIFT   = Winapi.Windows.VK_SHIFT;
  VK_CONTROL = Winapi.Windows.VK_CONTROL;
  VK_MENU    = Winapi.Windows.VK_MENU;
  VK_ESCAPE  = Winapi.Windows.VK_ESCAPE;
  VK_SPACE   = Winapi.Windows.VK_SPACE;

  SM_CYMENUCHECK = Winapi.Windows.SM_CYMENUCHECK;

{$NODEFINE GetTickCount64}
{$NODEFINE GetSystemMetrics}
function GetTickCount64: UInt64; inline;
function GetSystemMetrics(nIndex: Integer): Integer; inline;

// FPC's SysUtils.TSystemTime has plain field names and is portable; Delphi's is
// the Win32 SYSTEMTIME record with w-prefixed fields.  This keeps the calendar
// label code in TAIntervalSources readable and platform independent.
type
  TChartSystemTime = record
    Year, Month, Day, Hour, Minute, Second, Millisecond: Word;
  end;

procedure DateTimeToChartSystemTime(AValue: TDateTime;
  out ASystemTime: TChartSystemTime);

// Free Pascal has this in StrUtils; Delphi does not.
function IntToRoman(AValue: Integer): String;

implementation

{ TChartListEnumerator }

constructor TChartListEnumerator.Create(AList: TList);
begin
  inherited Create;
  FList := AList;
  FPosition := -1;
end;

function TChartListEnumerator.GetCurrent: Pointer;
begin
  Result := FList[FPosition];
end;

function TChartListEnumerator.MoveNext: Boolean;
begin
  Inc(FPosition);
  Result := FPosition < FList.Count;
end;

function GetTickCount64: UInt64;
begin
  Result := Winapi.Windows.GetTickCount64;
end;

procedure DateTimeToChartSystemTime(AValue: TDateTime;
  out ASystemTime: TChartSystemTime);
begin
  System.DateUtils.DecodeDateTime(AValue,
    ASystemTime.Year, ASystemTime.Month, ASystemTime.Day,
    ASystemTime.Hour, ASystemTime.Minute, ASystemTime.Second,
    ASystemTime.Millisecond);
end;

function IntToRoman(AValue: Integer): String;
const
  VALUES: array[0..12] of Integer =
    (1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1);
  NUMERALS: array[0..12] of String =
    ('M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I');
var
  i: Integer;
begin
  Result := '';
  for i := Low(VALUES) to High(VALUES) do
    while AValue >= VALUES[i] do begin
      Result := Result + NUMERALS[i];
      AValue := AValue - VALUES[i];
    end;
end;

function GetSystemMetrics(nIndex: Integer): Integer;
begin
  Result := Winapi.Windows.GetSystemMetrics(nIndex);
end;

end.
