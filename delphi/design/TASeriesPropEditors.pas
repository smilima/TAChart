{
 *****************************************************************************
  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************
}

unit TASeriesPropEditors;

{$I TAChartDefines.inc}

interface

uses
  System.Classes, DesignIntf, DesignEditors;

type
  { TAxisIndexPropertyEditor -- shows the series' axis indices by axis name
    instead of as bare numbers. }
  TAxisIndexPropertyEditor = class(TIntegerProperty)
  public
    function GetAttributes: TPropertyAttributes; override;
    function GetValue: String; override;
    procedure GetValues(Proc: TGetStrProc); override;
    procedure SetValue(const AValue: String); override;
  end;

implementation

uses
  System.Math, System.SysUtils,
  TAChartUtils, TACustomSeries, TAGraph;

function AxisOwner(AEditor: TPropertyEditor): TChart;
var
  s: TObject;
begin
  Result := nil;
  s := AEditor.GetComponent(0);
  if s is TCustomChartSeries then
    Result := TCustomChartSeries(s).ParentChart;
end;

{ TAxisIndexPropertyEditor }

function TAxisIndexPropertyEditor.GetAttributes: TPropertyAttributes;
begin
  Result := [paMultiSelect, paValueList, paRevertable];
end;

function TAxisIndexPropertyEditor.GetValue: String;
var
  ch: TChart;
  v: Integer;
begin
  v := GetOrdValue;
  ch := AxisOwner(Self);
  Result := IntToStr(v) + ' ';
  if (ch <> nil) and InRange(v, 0, ch.AxisList.Count - 1) then
    Result := Result + ch.AxisList[v].DisplayName
  else
    Result := Result + 'None';
end;

procedure TAxisIndexPropertyEditor.GetValues(Proc: TGetStrProc);
var
  ch: TChart;
  i: Integer;
begin
  Proc('-1 None');
  ch := AxisOwner(Self);
  if ch = nil then exit;
  for i := 0 to ch.AxisList.Count - 1 do
    Proc(IntToStr(i) + ' ' + ch.AxisList[i].DisplayName);
end;

procedure TAxisIndexPropertyEditor.SetValue(const AValue: String);
var
  v, code: Integer;
  s: String;
begin
  // The displayed value is "<index> <axis name>"; take the leading number.
  s := Trim(AValue);
  code := Pos(' ', s);
  if code > 0 then
    s := Copy(s, 1, code - 1);
  v := StrToIntDef(s, Low(TChartAxisIndex));
  SetOrdValue(Max(v, Low(TChartAxisIndex)));
end;

end.
