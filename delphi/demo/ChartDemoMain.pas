{
  TAChart for Delphi -- demo.

  Builds a chart entirely in code so the demo needs no .dfm, exercising the
  series types, the axis/legend/title machinery and the interactive tools.

  Run with:  ChartDemo.exe --render out.png
  to render the chart to a PNG and exit, which is handy for smoke testing a
  freshly built package.
}

unit ChartDemoMain;

interface

uses
  System.Classes, System.SysUtils, System.Math, System.Types,
  Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.ExtCtrls, Vcl.StdCtrls,
  Vcl.Imaging.pngimage,
  TAGraph, TASeries, TAMultiSeries, TARadialSeries, TAFuncSeries,
  TACustomSeries, TASources, TAChartUtils, TAChartAxisUtils, TALegend,
  TATools, TAChartListbox, TATypes, TAStyles, TAFitUtils;

type
  TDemoForm = class(TForm)
  strict private
    FChart: TChart;
    FListbox: TChartListbox;
    FToolset: TChartToolset;
    procedure BuildChart;
    procedure BuildTools;
    procedure CalcBell(const AX: Double; out AY: Double);
  public
    constructor CreateNew(AOwner: TComponent; Dummy: Integer = 0); override;
    procedure RenderToFile(const AFileName: String);
    // Second chart used by the smoke test: the radial, statistical and
    // fitting series, which exercise different drawing paths.
    procedure RenderExtrasToFile(const AFileName: String);
    property Chart: TChart read FChart;
  end;

implementation

const
  N_POINTS = 40;

constructor TDemoForm.CreateNew(AOwner: TComponent; Dummy: Integer);
begin
  inherited CreateNew(AOwner, Dummy);
  Caption := 'TAChart for Delphi - demo';
  Width := 900;
  Height := 560;
  Position := poScreenCenter;

  FListbox := TChartListbox.Create(Self);
  FListbox.Parent := Self;
  FListbox.Align := alRight;
  FListbox.Width := 180;

  FChart := TChart.Create(Self);
  FChart.Parent := Self;
  FChart.Align := alClient;

  FListbox.Chart := FChart;

  BuildChart;
  BuildTools;
end;

procedure TDemoForm.BuildChart;
var
  line: TLineSeries;
  area: TAreaSeries;
  bar: TBarSeries;
  pie: TPieSeries;
  fn: TFuncSeries;
  src: TListChartSource;
  i: Integer;
  x: Double;
begin
  FChart.Title.Visible := true;
  FChart.Title.Text.Text := 'TAChart on the VCL';
  FChart.Title.Font.Size := 12;
  FChart.Title.Font.Style := [fsBold];
  FChart.Foot.Visible := true;
  FChart.Foot.Text.Text := 'ported from the Lazarus original';

  FChart.Legend.Visible := true;
  FChart.Legend.Alignment := laBottomCenter;
  FChart.Legend.ColumnCount := 4;
  FChart.Frame.Visible := true;
  FChart.AxisList.BottomAxis.Title.Caption := 'x';
  FChart.AxisList.BottomAxis.Title.Visible := true;
  FChart.AxisList.LeftAxis.Title.Caption := 'y';
  FChart.AxisList.LeftAxis.Title.Visible := true;
  FChart.AxisList.LeftAxis.Grid.Visible := true;

  // --- area series, drawn first so it sits behind everything else ----------
  area := TAreaSeries.Create(FChart);
  area.Title := 'Area';
  area.AreaBrush.Color := $00E8D0B0;
  area.AreaLinesPen.Style := psClear;
  for i := 0 to N_POINTS - 1 do begin
    x := i / 4;
    area.AddXY(x, 3 + 2 * Sin(x / 2));
  end;
  FChart.AddSeries(area);

  // --- bar series ----------------------------------------------------------
  bar := TBarSeries.Create(FChart);
  bar.Title := 'Bars';
  bar.BarBrush.Color := $00C08040;
  bar.BarWidthPercent := 60;
  for i := 0 to 9 do
    bar.AddXY(i, 1 + (i mod 4));
  FChart.AddSeries(bar);

  // --- line series with point markers, fed from a shared source ------------
  src := TListChartSource.Create(FChart);
  for i := 0 to N_POINTS - 1 do begin
    x := i / 4;
    src.Add(x, 5 + 3 * Cos(x));
  end;
  line := TLineSeries.Create(FChart);
  line.Title := 'Line';
  line.Source := src;
  line.LinePen.Width := 2;
  line.LinePen.Color := clNavy;
  line.ShowPoints := true;
  line.Pointer.Style := psCircle;
  line.Pointer.Brush.Color := clWhite;
  FChart.AddSeries(line);

  // --- analytic function ---------------------------------------------------
  fn := TFuncSeries.Create(FChart);
  fn.Title := 'Function';
  fn.Pen.Color := clGreen;
  fn.Pen.Width := 2;
  fn.OnCalculate := CalcBell;
  FChart.AddSeries(fn);

  // --- pie series on its own, hidden by default so it does not overlap -----
  pie := TPieSeries.Create(FChart);
  pie.Title := 'Pie';
  pie.Active := false;
  pie.AddXY(0, 3, 'North');
  pie.AddXY(0, 5, 'South');
  pie.AddXY(0, 2, 'East');
  pie.AddXY(0, 4, 'West');
  pie.Marks.Style := smsLabel;
  FChart.AddSeries(pie);
end;

procedure TDemoForm.CalcBell(const AX: Double; out AY: Double);
begin
  AY := 4 + 4 * Exp(-Sqr(AX - 5) / 6);
end;

procedure TDemoForm.BuildTools;
var
  zoom: TZoomDragTool;
  pan: TPanDragTool;
  crosshair: TDataPointCrosshairTool;
begin
  FToolset := TChartToolset.Create(Self);
  FChart.Toolset := FToolset;

  zoom := TZoomDragTool.Create(Self);
  zoom.Toolset := FToolset;
  zoom.Shift := [ssLeft];

  pan := TPanDragTool.Create(Self);
  pan.Toolset := FToolset;
  pan.Shift := [ssRight];

  crosshair := TDataPointCrosshairTool.Create(Self);
  crosshair.Toolset := FToolset;
  crosshair.Shift := [ssShift];
end;

procedure TDemoForm.RenderExtrasToFile(const AFileName: String);
var
  ch: TChart;
  pie: TPieSeries;
  polar: TPolarSeries;
  box: TBoxAndWhiskerSeries;
  spline: TCubicSplineSeries;
  fit: TFitSeries;
  src: TListChartSource;
  bmp: TBitmap;
  png: TPngImage;
  i: Integer;
  x: Double;
begin
  ch := TChart.Create(Self);
  try
    ch.Parent := Self;
    ch.Visible := false;
    ch.Width := 900;
    ch.Height := 560;
    ch.Title.Visible := true;
    ch.Title.Text.Text := 'Radial, statistical and fitting series';
    ch.Legend.Visible := true;
    ch.Legend.Alignment := laBottomCenter;
    ch.Legend.ColumnCount := 4;

    // Pie: goes through the RadialPie drawer entry point.
    pie := TPieSeries.Create(ch);
    pie.Title := 'Pie';
    pie.AddXY(0, 3, 'North');
    pie.AddXY(0, 5, 'South');
    pie.AddXY(0, 2, 'East');
    pie.AddXY(0, 4, 'West');
    pie.Marks.Style := smsLabelPercent;
    pie.Exploded := true;
    ch.AddSeries(pie);

    // Polar.
    polar := TPolarSeries.Create(ch);
    polar.Title := 'Polar';
    polar.LinePen.Color := clRed;
    for i := 0 to 120 do
      polar.AddXY(i * Pi / 30, 2 + Cos(3 * i * Pi / 30));
    ch.AddSeries(polar);

    // Box and whisker.
    box := TBoxAndWhiskerSeries.Create(ch);
    box.Title := 'Box';
    for i := 0 to 3 do
      box.AddXY(i * 2, i - 2, [i - 1, i, i + 1, i + 2]);
    ch.AddSeries(box);

    // Cubic spline through scattered points (uses the ported NumLib code).
    src := TListChartSource.Create(ch);
    for i := 0 to 8 do begin
      x := i;
      src.Add(x, Sin(x / 2) * 3);
    end;
    spline := TCubicSplineSeries.Create(ch);
    spline.Title := 'Spline';
    spline.Source := src;
    spline.Pen.Color := clPurple;
    spline.Pen.Width := 2;
    ch.AddSeries(spline);

    // Least squares polynomial fit (also NumLib).
    fit := TFitSeries.Create(ch);
    fit.Title := 'Fit';
    fit.Source := src;
    fit.FitEquation := fePolynomial;
    fit.ParamCount := 4;
    fit.Pen.Color := clOlive;
    fit.Pen.Width := 2;
    ch.AddSeries(fit);

    bmp := TBitmap.Create;
    try
      bmp.PixelFormat := pf24bit;
      bmp.SetSize(ch.Width, ch.Height);
      ch.PaintOnCanvas(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height));
      png := TPngImage.Create;
      try
        png.Assign(bmp);
        png.SaveToFile(AFileName);
      finally
        png.Free;
      end;
    finally
      bmp.Free;
    end;
  finally
    ch.Free;
  end;
end;

procedure TDemoForm.RenderToFile(const AFileName: String);
var
  bmp: TBitmap;
  png: TPngImage;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(FChart.Width, FChart.Height);
    FChart.PaintOnCanvas(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height));
    png := TPngImage.Create;
    try
      png.Assign(bmp);
      png.SaveToFile(AFileName);
    finally
      png.Free;
    end;
  finally
    bmp.Free;
  end;
end;

end.
