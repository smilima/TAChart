{
 *****************************************************************************
  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  Author: Alexander Klenin

  Delphi/VCL port notes
  ---------------------
  The Lazarus form comes from a .lfm and relies on LCL grid features the VCL
  does not have (per-column ellipsis buttons, goAutoAddRows,
  goFixedRowNumbering).  This version builds the form in code, numbers the
  rows itself, pops the colour dialog on a double-click in the Color column,
  and offers Insert/Add/Delete row through the context menu.
}

unit TADataPointsEditor;

{$I TAChartDefines.inc}

interface

uses
  System.Classes, System.Types, System.UITypes,
  Vcl.Forms, Vcl.Controls, Vcl.Grids, Vcl.Menus, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.Graphics,
  DesignIntf, DesignEditors;

type

  { TDataPointsEditorForm }

  TDataPointsEditorForm = class(TForm)
  strict private
    FGrid: TStringGrid;
    FButtonPanel: TPanel;
    FOkButton: TButton;
    FCancelButton: TButton;
    FMenuRows: TPopupMenu;
    FColorDialog: TColorDialog;
    FCurrentRow: Integer;
    FDataPoints: TStrings;
    FYCount: Integer;
    procedure BuildControls;
    function ColorColumn: Integer; inline;
    procedure GridDblClick(Sender: TObject);
    procedure GridDrawCell(Sender: TObject; ACol, ARow: Integer;
      ARect: TRect; AState: TGridDrawState);
    procedure MenuRowsPopup(Sender: TObject);
    procedure MiAddRowClick(Sender: TObject);
    procedure MiDeleteRowClick(Sender: TObject);
    procedure MiInsertRowClick(Sender: TObject);
  public
    constructor CreateNew(AOwner: TComponent; Dummy: Integer = 0); override;
    procedure InitData(AYCount: Integer; ADataPoints: TStrings);
    procedure ExtractData(out AModified: Boolean);
  end;

  { TDataPointsPropertyEditor }

  TDataPointsPropertyEditor = class(TPropertyEditor)
  public
    procedure Edit; override;
    function GetAttributes: TPropertyAttributes; override;
    function GetValue: string; override;
  end;

implementation

uses
  System.SysUtils, System.Math,
  TAChartStrConsts, TAChartUtils, TASources;

{ TDataPointsEditorForm }

constructor TDataPointsEditorForm.CreateNew(AOwner: TComponent; Dummy: Integer);
begin
  inherited CreateNew(AOwner, Dummy);
  BuildControls;
end;

procedure TDataPointsEditorForm.BuildControls;

  function MakeMenuItem(const ACaption: String;
    AOnClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(Self);
    Result.Caption := ACaption;
    Result.OnClick := AOnClick;
    FMenuRows.Items.Add(Result);
  end;

begin
  Caption := desDatapointEditor;
  BorderStyle := bsSizeable;
  Position := poScreenCenter;
  Width := 420;
  Height := 340;

  FButtonPanel := TPanel.Create(Self);
  FButtonPanel.Parent := Self;
  FButtonPanel.Align := alBottom;
  FButtonPanel.Height := 38;
  FButtonPanel.BevelOuter := bvNone;

  FOkButton := TButton.Create(Self);
  FOkButton.Parent := FButtonPanel;
  FOkButton.Caption := 'OK';
  FOkButton.ModalResult := mrOk;
  FOkButton.Default := true;
  FOkButton.SetBounds(FButtonPanel.Width - 170, 7, 80, 25);
  FOkButton.Anchors := [akRight, akTop];

  FCancelButton := TButton.Create(Self);
  FCancelButton.Parent := FButtonPanel;
  FCancelButton.Caption := 'Cancel';
  FCancelButton.ModalResult := mrCancel;
  FCancelButton.Cancel := true;
  FCancelButton.SetBounds(FButtonPanel.Width - 86, 7, 80, 25);
  FCancelButton.Anchors := [akRight, akTop];

  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.FixedCols := 1;
  FGrid.FixedRows := 1;
  FGrid.DefaultRowHeight := 20;
  FGrid.Options := FGrid.Options +
    [goColSizing, goEditing, goAlwaysShowEditor, goTabs] - [goRowSizing];
  FGrid.OnDrawCell := GridDrawCell;
  FGrid.OnDblClick := GridDblClick;

  FMenuRows := TPopupMenu.Create(Self);
  FMenuRows.OnPopup := MenuRowsPopup;
  MakeMenuItem(desInsertRow, MiInsertRowClick);
  MakeMenuItem('Add row', MiAddRowClick);
  MakeMenuItem(desDeleteRow, MiDeleteRowClick);
  FGrid.PopupMenu := FMenuRows;

  FColorDialog := TColorDialog.Create(Self);
end;

function TDataPointsEditorForm.ColorColumn: Integer;
begin
  Result := FYCount + 2;
end;

procedure TDataPointsEditorForm.InitData(
  AYCount: Integer; ADataPoints: TStrings);
var
  i, j: Integer;
  parts: TStringList;
begin
  FYCount := Max(AYCount, 1);
  FDataPoints := ADataPoints;

  // Fixed number column, X, Y1..Yn, Color, Text.
  FGrid.ColCount := FYCount + 4;
  FGrid.RowCount := Max(ADataPoints.Count + 1, 2);
  FGrid.ColWidths[0] := 32;
  FGrid.Cells[1, 0] := 'X';
  if FYCount = 1 then
    FGrid.Cells[2, 0] := 'Y'
  else
    for i := 1 to FYCount do
      FGrid.Cells[1 + i, 0] := 'Y' + IntToStr(i);
  FGrid.Cells[ColorColumn, 0] := desColor;
  FGrid.Cells[ColorColumn + 1, 0] := desText;
  for i := 1 to FGrid.ColCount - 1 do
    FGrid.ColWidths[i] := 80;

  parts := TStringList.Create;
  try
    parts.Delimiter := '|';
    parts.StrictDelimiter := true;
    for i := 0 to ADataPoints.Count - 1 do begin
      parts.DelimitedText := ADataPoints[i];
      for j := 0 to Min(parts.Count, FGrid.ColCount - 1) - 1 do
        FGrid.Cells[j + 1, i + 1] := parts[j];
    end;
  finally
    parts.Free;
  end;
end;

procedure TDataPointsEditorForm.ExtractData(out AModified: Boolean);
var
  i, j: Integer;
  parts: TStringList;
  s, oldDataPoints: String;
begin
  oldDataPoints := FDataPoints.Text;
  FDataPoints.BeginUpdate;
  parts := TStringList.Create;
  try
    parts.Delimiter := '|';
    parts.StrictDelimiter := true;
    FDataPoints.Clear;
    for i := 1 to FGrid.RowCount - 1 do begin
      parts.Clear;
      for j := 1 to FGrid.ColCount - 1 do
        parts.Add(FGrid.Cells[j, i]);
      s := parts.DelimitedText;
      // Skip rows that are entirely empty.
      if Trim(StringReplace(s, '|', '', [rfReplaceAll])) <> '' then
        FDataPoints.Add(s);
    end;
  finally
    parts.Free;
    FDataPoints.EndUpdate;
    AModified := FDataPoints.Text <> oldDataPoints;
  end;
end;

procedure TDataPointsEditorForm.GridDblClick(Sender: TObject);
begin
  if (FGrid.Row < 1) or (FGrid.Col <> ColorColumn) then exit;
  FColorDialog.Color := TColor(
    StrToIntDef(FGrid.Cells[FGrid.Col, FGrid.Row], Integer(TColors.Red)));
  if not FColorDialog.Execute then exit;
  FGrid.Cells[FGrid.Col, FGrid.Row] := IntToColorHex(FColorDialog.Color);
end;

procedure TDataPointsEditorForm.GridDrawCell(Sender: TObject;
  ACol, ARow: Integer; ARect: TRect; AState: TGridDrawState);
var
  c: Integer;
  s: String;
begin
  // Row numbers in the fixed column.
  if (ACol = 0) and (ARow >= 1) then begin
    s := IntToStr(ARow);
    FGrid.Canvas.TextRect(ARect,
      ARect.Right - FGrid.Canvas.TextWidth(s) - 4,
      (ARect.Top + ARect.Bottom - FGrid.Canvas.TextHeight(s)) div 2, s);
    exit;
  end;
  // Colour swatch at the right edge of the Color column.
  if (ARow >= 1) and (ACol = ColorColumn) and
     TryStrToInt(FGrid.Cells[ACol, ARow], c) then begin
    FGrid.Canvas.Pen.Color := clBlack;
    FGrid.Canvas.Brush.Color := TColor(c);
    InflateRect(ARect, -2, -2);
    ARect.Left := ARect.Right - 12;
    FGrid.Canvas.Rectangle(ARect);
  end;
end;

procedure TDataPointsEditorForm.MenuRowsPopup(Sender: TObject);
var
  cell: TGridCoord;
  p: TPoint;
begin
  p := FGrid.ScreenToClient(Mouse.CursorPos);
  cell := FGrid.MouseCoord(p.X, p.Y);
  FCurrentRow := cell.Y;
  if InRange(FCurrentRow, 1, FGrid.RowCount - 1) then
    FGrid.Row := FCurrentRow;
end;

procedure TDataPointsEditorForm.MiAddRowClick(Sender: TObject);
begin
  FGrid.RowCount := FGrid.RowCount + 1;
  FGrid.Row := FGrid.RowCount - 1;
end;

procedure TDataPointsEditorForm.MiDeleteRowClick(Sender: TObject);
var
  i, j: Integer;
begin
  if FGrid.RowCount <= 2 then begin
    FGrid.Rows[1].Clear;
    exit;
  end;
  if not InRange(FCurrentRow, 1, FGrid.RowCount - 1) then exit;
  for i := FCurrentRow to FGrid.RowCount - 2 do
    for j := 0 to FGrid.ColCount - 1 do
      FGrid.Cells[j, i] := FGrid.Cells[j, i + 1];
  FGrid.RowCount := FGrid.RowCount - 1;
end;

procedure TDataPointsEditorForm.MiInsertRowClick(Sender: TObject);
var
  i, j: Integer;
begin
  if not InRange(FCurrentRow, 1, FGrid.RowCount - 1) then exit;
  FGrid.RowCount := FGrid.RowCount + 1;
  for i := FGrid.RowCount - 2 downto FCurrentRow do
    for j := 0 to FGrid.ColCount - 1 do
      FGrid.Cells[j, i + 1] := FGrid.Cells[j, i];
  FGrid.Rows[FCurrentRow].Clear;
end;

{ TDataPointsPropertyEditor }

procedure TDataPointsPropertyEditor.Edit;
var
  dataModified: Boolean;
begin
  with TDataPointsEditorForm.CreateNew(nil) do
    try
      InitData(
        (GetComponent(0) as TListChartSource).YCount,
        TStrings(GetOrdValue));
      if ShowModal = mrOk then begin
        ExtractData(dataModified);
        if dataModified then Modified;
      end;
    finally
      Free;
    end;
end;

function TDataPointsPropertyEditor.GetAttributes: TPropertyAttributes;
begin
  Result := [paDialog, paMultiSelect, paReadOnly, paRevertable];
end;

function TDataPointsPropertyEditor.GetValue: string;
begin
  Result := TStrings(GetOrdValue).Text;
end;

end.
