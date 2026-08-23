{
 *****************************************************************************
  This file is part of the Delphi/VCL port of TAChart.

  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  The series gallery: the design-time editor for a chart's series.

  It replaces the earlier list-and-menu editor (TASeriesEditor).  Instead of
  listing the series already on the chart by name, the window shows every
  registered series class as a tile with a live sample chart, and adding one
  is a matter of picking a tile and pressing OK.  The samples come from
  TASeriesGallery, which draws them with TAChart's own drawer - there is no
  dependency on any other charting library.

  A newly registered series class needs no change here: the gallery is built
  from SeriesClassRegistry every time it opens.

  Designing this form
  -------------------
  The layout is in TASeriesEditorUnit.dfm and can be reworked freely in the
  Delphi form designer.  Keep the control names - the code looks them up - and
  keep GalleryGrid.DefaultDrawing false, since every tile is painted by
  GalleryGridDrawCell.  Tile size is set by the grid's DefaultColWidth and
  DefaultRowHeight; the preview bitmap is sized to fit whatever you choose.
}

unit TASeriesEditorUnit;

{$I TAChartDefines.inc}

interface

uses
  System.Classes, System.Types,
  Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics, Vcl.Grids,
  Vcl.StdCtrls,
  DesignIntf, DesignEditors,
  TAGraph;

type

  { TSeriesGalleryForm }

  TSeriesGalleryForm = class(TForm)
    GalleryGrid: TDrawGrid;
    ButtonPanel: TPanel;
    OKButton: TButton;
    CancelButton: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure GalleryGridDblClick(Sender: TObject);
    procedure GalleryGridDrawCell(Sender: TObject; ACol, ARow: Integer;
      ARect: TRect; AState: TGridDrawState);
    procedure GalleryGridSelectCell(Sender: TObject; ACol, ARow: Integer;
      var CanSelect: Boolean);
  strict private
    // Captions of the registered classes; Objects[] carries the registry index.
    FEntries: TStringList;
    // One preview per entry, rendered on first paint and cached from then on.
    FPreviews: TList;
    function CellToEntry(ACol, ARow: Integer): Integer;
    function GetSelectedIndex: Integer;
    function PreviewOf(AEntry: Integer): TBitmap;
    procedure LayOutTiles;
    procedure UpdateOKButton;
  public
    // The class the user picked, or nil when nothing is selected.
    function SelectedClass: TSeriesClass;
    property SelectedIndex: Integer read GetSelectedIndex;
  end;

  { TSeriesComponentEditor -- the chart's "Edit series" verb. }

  TSeriesComponentEditor = class(TComponentEditor)
  public
    procedure ExecuteVerb(Index: Integer); override;
    function GetVerb(Index: Integer): string; override;
    function GetVerbCount: Integer; override;
  end;

  { TSeriesPropertyEditor -- the same window from the Object Inspector. }

  TSeriesPropertyEditor = class(TPropertyEditor)
  public
    procedure Edit; override;
    function GetAttributes: TPropertyAttributes; override;
    function GetValue: string; override;
  end;

implementation

uses
  System.SysUtils, System.Math, System.UITypes,
  TAChartStrConsts, TASeriesGallery;

{$R *.dfm}

const
  TILE_MARGIN = 4;
  CAPTION_HEIGHT = 18;

{ Adding }

// Shows the gallery and, if the user picks a class, creates that series and
// hands it to AChart.  Shared by the component and the property editor.
procedure AddSeriesFromGallery(AChart: TTAChart; const ADesigner: IDesigner);
var
  gallery: TSeriesGalleryForm;
  cls: TSeriesClass;
  s: TBasicChartSeries;
begin
  if AChart = nil then
    raise Exception.Create('Series gallery: there is no chart to add to.');
  if ADesigner = nil then
    raise Exception.Create('Series gallery: no designer is available.');

  cls := nil;
  gallery := TSeriesGalleryForm.Create(Application);
  try
    if gallery.ShowModal = mrOk then
      cls := gallery.SelectedClass;
  finally
    gallery.Free;
  end;
  if cls = nil then exit;

  // The series belongs to the same owner as the chart - the designed form -
  // so the designer streams it into the .dfm.
  s := cls.Create(AChart.Owner);
  try
    s.Name := ADesigner.UniqueName(
      AChart.Name + Copy(s.ClassName, 2, Length(s.ClassName) - 1));
    AChart.AddSeries(s);
  except
    s.Free;
    raise;
  end;
  ADesigner.Modified;
  ADesigner.SelectComponent(s);
end;

{ TSeriesGalleryForm }

procedure TSeriesGalleryForm.FormCreate(Sender: TObject);
var
  i: Integer;
  caption: String;
begin
  FEntries := TStringList.Create;
  FPreviews := TList.Create;

  for i := 0 to SeriesClassRegistry.Count - 1 do begin
    caption := SeriesClassRegistry.GetCaption(i);
    // An empty caption marks a deprecated class - the old menu skipped those
    // and so does the gallery.
    if caption = '' then Continue;
    FEntries.AddObject(caption, TObject(i));
    FPreviews.Add(nil);
  end;

  GalleryGrid.DefaultDrawing := false;
  Caption := sesSeriesEditorTitle;
  LayOutTiles;
  UpdateOKButton;
end;

procedure TSeriesGalleryForm.FormDestroy(Sender: TObject);
var
  i: Integer;
begin
  if FPreviews <> nil then
    for i := 0 to FPreviews.Count - 1 do
      TObject(FPreviews[i]).Free;
  FreeAndNil(FPreviews);
  FreeAndNil(FEntries);
end;

procedure TSeriesGalleryForm.FormResize(Sender: TObject);
begin
  LayOutTiles;
end;

procedure TSeriesGalleryForm.LayOutTiles;
var
  cols, avail: Integer;
begin
  if FEntries = nil then exit;
  // Fit as many whole tiles across as the window allows, leaving room for the
  // vertical scrollbar so the last column is never clipped.
  avail := GalleryGrid.ClientWidth;
  cols := Max(1, avail div GalleryGrid.DefaultColWidth);
  GalleryGrid.ColCount := cols;
  GalleryGrid.RowCount := Max(1, Ceil(FEntries.Count / cols));
  GalleryGrid.Invalidate;
end;

function TSeriesGalleryForm.CellToEntry(ACol, ARow: Integer): Integer;
begin
  Result := ARow * GalleryGrid.ColCount + ACol;
  if (Result < 0) or (Result >= FEntries.Count) then
    Result := -1;
end;

function TSeriesGalleryForm.GetSelectedIndex: Integer;
begin
  if FEntries = nil then
    Result := -1
  else
    Result := CellToEntry(GalleryGrid.Col, GalleryGrid.Row);
end;

function TSeriesGalleryForm.SelectedClass: TSeriesClass;
var
  i: Integer;
begin
  Result := nil;
  i := SelectedIndex;
  if i < 0 then exit;
  Result := TSeriesClass(
    SeriesClassRegistry.GetClass(Integer(FEntries.Objects[i])));
end;

function TSeriesGalleryForm.PreviewOf(AEntry: Integer): TBitmap;
var
  w, h: Integer;
begin
  Result := TBitmap(FPreviews[AEntry]);
  if Result <> nil then exit;

  w := GalleryGrid.DefaultColWidth - 2 * TILE_MARGIN;
  h := GalleryGrid.DefaultRowHeight - CAPTION_HEIGHT - 2 * TILE_MARGIN;
  Result := TSeriesPreview.Render(
    TSeriesClass(SeriesClassRegistry.GetClass(Integer(FEntries.Objects[AEntry]))),
    Max(1, w), Max(1, h), clWindow);
  FPreviews[AEntry] := Result;
end;

procedure TSeriesGalleryForm.GalleryGridDrawCell(Sender: TObject;
  ACol, ARow: Integer; ARect: TRect; AState: TGridDrawState);
var
  cv: TCanvas;
  entry: Integer;
  bmp: TBitmap;
  selected: Boolean;
  captionRect: TRect;
  captionText: String;
begin
  cv := GalleryGrid.Canvas;
  entry := CellToEntry(ACol, ARow);
  selected := (gdSelected in AState) and (entry >= 0);

  // A selected tile is framed and sits on the button face, the way the sample
  // galleries people are used to show the current pick.
  cv.Brush.Style := bsSolid;
  if selected then
    cv.Brush.Color := clBtnFace
  else
    cv.Brush.Color := clWindow;
  cv.FillRect(ARect);
  if entry < 0 then exit;

  cv.Font := GalleryGrid.Font;
  cv.Font.Color := clNavy;
  cv.Brush.Style := bsClear;
  captionRect := Rect(
    ARect.Left + TILE_MARGIN, ARect.Top + 2,
    ARect.Right - TILE_MARGIN, ARect.Top + CAPTION_HEIGHT);
  captionText := FEntries[entry];
  cv.TextRect(captionRect, captionText,
    [tfSingleLine, tfEndEllipsis, tfVerticalCenter]);
  cv.Brush.Style := bsSolid;

  bmp := PreviewOf(entry);
  if bmp <> nil then
    cv.Draw(ARect.Left + TILE_MARGIN, ARect.Top + CAPTION_HEIGHT, bmp);

  if selected then begin
    cv.Brush.Style := bsClear;
    cv.Pen.Color := clHighlight;
    cv.Pen.Width := 2;
    cv.Rectangle(ARect.Left + 1, ARect.Top + 1, ARect.Right - 1, ARect.Bottom - 1);
    cv.Pen.Width := 1;
    cv.Brush.Style := bsSolid;
  end;
end;

procedure TSeriesGalleryForm.GalleryGridSelectCell(Sender: TObject;
  ACol, ARow: Integer; var CanSelect: Boolean);
begin
  // The last row is usually part empty; those cells are not selectable.
  CanSelect := CellToEntry(ACol, ARow) >= 0;
  // This fires with the cell being moved to, so it is already the right one
  // to judge the OK button by.
  OKButton.Enabled := CanSelect;
end;

procedure TSeriesGalleryForm.UpdateOKButton;
begin
  OKButton.Enabled := SelectedIndex >= 0;
end;

procedure TSeriesGalleryForm.GalleryGridDblClick(Sender: TObject);
begin
  if SelectedIndex >= 0 then
    ModalResult := mrOk;
end;

{ TSeriesComponentEditor }

function TSeriesComponentEditor.GetVerbCount: Integer;
begin
  Result := 1;
end;

function TSeriesComponentEditor.GetVerb(Index: Integer): string;
begin
  if Index = 0 then
    Result := sesSeriesEditorTitle + '...'
  else
    Result := '';
end;

procedure TSeriesComponentEditor.ExecuteVerb(Index: Integer);
begin
  if Index <> 0 then exit;
  AddSeriesFromGallery(GetComponent as TTAChart, Designer);
end;

{ TSeriesPropertyEditor }

procedure TSeriesPropertyEditor.Edit;
begin
  AddSeriesFromGallery(GetComponent(0) as TTAChart, Designer);
end;

function TSeriesPropertyEditor.GetAttributes: TPropertyAttributes;
begin
  Result := [paDialog, paReadOnly];
end;

function TSeriesPropertyEditor.GetValue: string;
var
  c: Integer;
begin
  c := (TObject(GetOrdValue) as TChartSeriesList).Count;
  if c = 1 then
    Result := '1 item'
  else
    Result := IntToStr(c) + ' items';
end;

end.
