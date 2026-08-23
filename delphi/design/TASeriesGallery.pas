{
 *****************************************************************************
  This file is part of the Delphi/VCL port of TAChart.

  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  Sample renderings of the registered series classes, for the series gallery.

  Each preview is a real TTAChart drawn onto a bitmap through TCanvasDrawer -
  the same path the chart uses to paint itself - so a preview always looks like
  what the series will actually produce.  Nothing here depends on any other
  charting library.

  Most series only need a handful of XY points.  The ones that carry several Y
  values per point (bubble, box-and-whisker, open-high-low-close, vector field)
  or that draw from an event rather than a source (function, parametric curve,
  colour map, user-drawn) get their own sample in SetUpSampleData.  A class
  that still fails to draw is not allowed to take the gallery down with it: the
  caller gets a blank tile instead.
}

unit TASeriesGallery;

{$I TAChartDefines.inc}

interface

uses
  System.Classes, System.Types,
  Vcl.Graphics,
  TAGraph;

type

  { TSeriesPreview }

  TSeriesPreview = class
  public
    // Renders ASeriesClass into a new bitmap the caller owns.  Never raises;
    // a class that cannot draw yields a bitmap filled with ABackColor.
    class function Render(ASeriesClass: TSeriesClass;
      AWidth, AHeight: Integer; ABackColor: TColor): TBitmap;
  end;

implementation

uses
  System.SysUtils, System.Math, System.UITypes,
  TAChartUtils, TAGeometry, TADrawUtils, TATypes, TASources,
  TACustomSeries, TASeries, TAMultiSeries, TARadialSeries, TAFuncSeries;

type
  { Supplies the event handlers the function-driven series need.  A plain
    object rather than class methods, so the method pointers are unambiguous. }
  TSampleCalculations = class
    procedure Func(const AX: Double; out AY: Double);
    procedure Parametric(const AT: Double; out AX, AY: Double);
    procedure Func3D(const AX, AY: Double; out AZ: Double);
    procedure UserDraw(ACanvas: TCanvas; const ARect: TRect);
  end;

var
  VSample: TSampleCalculations = nil;

const
  // A short, gently varying series reads well at thumbnail size.
  SAMPLE_X_COUNT = 6;
  SAMPLE_Y: array [0 .. SAMPLE_X_COUNT - 1] of Double = (3, 5, 4, 7, 5, 8);
  // Alternating band colours, the convention for a Manhattan plot.
  MANHATTAN_BANDS: array [0 .. 1] of TColor = (clNavy, clGray);

{ TSampleCalculations }

procedure TSampleCalculations.Func(const AX: Double; out AY: Double);
begin
  AY := Sin(AX);
end;

procedure TSampleCalculations.Parametric(const AT: Double; out AX, AY: Double);
begin
  // A Lissajous figure - unmistakably a parametric curve at any size.
  AX := Sin(2 * AT);
  AY := Sin(3 * AT);
end;

procedure TSampleCalculations.Func3D(const AX, AY: Double; out AZ: Double);
begin
  AZ := Sin(AX) * Cos(AY);
end;

procedure TSampleCalculations.UserDraw(ACanvas: TCanvas; const ARect: TRect);
var
  i, n, x, y0, y1: Integer;
begin
  // Stand-in artwork: the point is to show that the series hands you a canvas.
  n := 12;
  ACanvas.Pen.Color := clNavy;
  ACanvas.Pen.Width := 2;
  for i := 0 to n - 1 do begin
    x := ARect.Left + ((ARect.Right - ARect.Left) * i) div (n - 1);
    y0 := (ARect.Top + ARect.Bottom) div 2;
    y1 := y0 - Round((ARect.Bottom - ARect.Top) * 0.35 * Sin(i * Pi / 4));
    ACanvas.MoveTo(x, y0);
    ACanvas.LineTo(x, y1);
  end;
end;

{ Sample data }

// A fixed, repeatable scatter in 0..1.  Random would make each repaint of the
// gallery look slightly different.
function Scatter(AIndex, ASalt: Integer): Double;
var
  v: Double;
begin
  v := Sin(AIndex * 12.9898 + ASalt * 78.233) * 43758.5453;
  Result := Frac(Abs(v));
end;

// Builds a value -> colour source for the colour map, owned by AOwner so the
// caller does not have to free it.
function MakePalette(AOwner: TComponent;
  const AColors: array of TColor): TListChartSource;
var
  i: Integer;
begin
  Result := TListChartSource.Create(AOwner);
  for i := 0 to High(AColors) do
    Result.Add(i / High(AColors) * 2 - 1, 0, '', AColors[i]);
end;

procedure SetUpSampleData(ASeries: TBasicChartSeries);
var
  i: Integer;
begin
  // Order matters: the multi-value series are all TTAChartSeries descendants,
  // so they have to be matched before the plain XY fallback.
  if ASeries is TTABubbleSeries then begin
    for i := 0 to 4 do
      TTABubbleSeries(ASeries).AddXY(i, SAMPLE_Y[i], 0.35 + 0.12 * (i mod 3));
  end

  else if ASeries is TBoxAndWhiskerSeries then begin
    for i := 0 to 3 do
      TBoxAndWhiskerSeries(ASeries).AddXY(
        i, 1 + i * 0.5, 2.5 + i * 0.5, 4 + i * 0.5, 5.5 + i * 0.5, 7 + i * 0.5);
  end

  else if ASeries is TOpenHighLowCloseSeries then begin
    for i := 0 to 4 do
      TOpenHighLowCloseSeries(ASeries).AddXOHLC(
        i, 3 + i * 0.4, 5 + i * 0.4, 2 + i * 0.4, 4 + i * 0.4);
  end

  else if ASeries is TFieldSeries then begin
    for i := 0 to 3 do
      TFieldSeries(ASeries).AddVector(
        i, 2 + (i mod 2), 0.6, 0.5 - 0.3 * (i mod 2));
  end

  else if ASeries is TManhattanSeries then begin
    // Manhattan plots one pixel per point; a handful of points is invisible.
    // Four banded groups of dense points give the shape it is named for.
    for i := 0 to 1599 do
      TManhattanSeries(ASeries).AddXY(
        i / 400, Scatter(i, 1) * (1 + 3 * Sqr(Scatter(i, 2))), '',
        MANHATTAN_BANDS[(i div 400) mod Length(MANHATTAN_BANDS)]);
  end

  else if ASeries is TConstantLine then
    TConstantLine(ASeries).Position := 4

  else if ASeries is TUserDrawnSeries then
    TUserDrawnSeries(ASeries).OnDraw := VSample.UserDraw

  else if ASeries is TFuncSeries then begin
    TFuncSeries(ASeries).OnCalculate := VSample.Func;
    TFuncSeries(ASeries).Extent.FixTo(DoubleRect(0, -1.2, 2 * Pi, 1.2));
  end

  else if ASeries is TParametricCurveSeries then begin
    TParametricCurveSeries(ASeries).OnCalculate := VSample.Parametric;
    TParametricCurveSeries(ASeries).ParamMin := 0;
    TParametricCurveSeries(ASeries).ParamMax := 2 * Pi;
  end

  else if ASeries is TColorMapSeries then begin
    TColorMapSeries(ASeries).OnCalculate := VSample.Func3D;
    TColorMapSeries(ASeries).Extent.FixTo(DoubleRect(-3, -3, 3, 3));
    TColorMapSeries(ASeries).StepX := 4;
    TColorMapSeries(ASeries).StepY := 4;
    // Without a ColorSource every cell comes back clTAColor and the map draws
    // blank, so give it a small blue-yellow-red palette to interpolate over.
    TColorMapSeries(ASeries).ColorSource :=
      MakePalette(ASeries, [clNavy, clAqua, clYellow, clRed]);
    TColorMapSeries(ASeries).Interpolate := true;
  end

  else if ASeries is TTAChartSeries then begin
    // Line, area, bar, pie, polar, splines, fit - anything that just wants
    // XY points.
    for i := 0 to SAMPLE_X_COUNT - 1 do
      TTAChartSeries(ASeries).AddXY(i, SAMPLE_Y[i]);
  end;

  // An area series defaults to a white brush, which is invisible against the
  // gallery background, so give it the fill the tile is meant to show off.
  if ASeries is TTAAreaSeries then begin
    TTAAreaSeries(ASeries).AreaBrush.Color := $00D8A05A;  // muted blue
    TTAAreaSeries(ASeries).AreaContourPen.Color := clNavy;
  end;
end;

procedure SetUpChart(AChart: TTAChart; ABackColor: TColor);
var
  i: Integer;
begin
  // A thumbnail has no room for a legend or a title; the gallery draws the
  // class caption itself.
  AChart.Legend.Visible := false;
  AChart.Title.Visible := false;
  AChart.Foot.Visible := false;
  AChart.Frame.Visible := false;
  AChart.BackColor := ABackColor;
  AChart.Color := ABackColor;
  AChart.AntialiasingMode := amOn;

  AChart.MarginsExternal.Left := 2;
  AChart.MarginsExternal.Top := 2;
  AChart.MarginsExternal.Right := 4;
  AChart.MarginsExternal.Bottom := 2;

  for i := 0 to AChart.AxisList.Count - 1 do begin
    AChart.AxisList[i].Marks.LabelFont.Size := 6;
    AChart.AxisList[i].Grid.Visible := true;
  end;
end;

{ TSeriesPreview }

class function TSeriesPreview.Render(ASeriesClass: TSeriesClass;
  AWidth, AHeight: Integer; ABackColor: TColor): TBitmap;
var
  chart: TTAChart;
  s: TBasicChartSeries;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AWidth, AHeight);
  Result.Canvas.Brush.Style := bsSolid;
  Result.Canvas.Brush.Color := ABackColor;
  Result.Canvas.FillRect(Rect(0, 0, AWidth, AHeight));
  if ASeriesClass = nil then exit;

  try
    chart := TTAChart.Create(nil);
    try
      chart.Width := AWidth;
      chart.Height := AHeight;
      SetUpChart(chart, ABackColor);

      s := ASeriesClass.Create(chart);
      SetUpSampleData(s);
      chart.AddSeries(s);

      chart.PaintOnCanvas(Result.Canvas, Rect(0, 0, AWidth, AHeight));
    finally
      chart.Free;
    end;
  except
    // A series that needs more setup than a gallery can guess must not break
    // the gallery.  The blank tile still carries the class caption.
    on E: Exception do begin
      Result.Canvas.Brush.Style := bsSolid;
      Result.Canvas.Brush.Color := ABackColor;
      Result.Canvas.FillRect(Rect(0, 0, AWidth, AHeight));
    end;
  end;
end;

initialization
  VSample := TSampleCalculations.Create;

finalization
  FreeAndNil(VSample);

end.
