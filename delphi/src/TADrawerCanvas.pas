{
 *****************************************************************************
  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  Authors: Alexander Klenin

  Delphi/VCL port note
  --------------------
  This is the one unit of the port that is a rewrite rather than a translation.
  The Lazarus original leans on LCL extensions to TCanvas that the VCL does not
  have - settable Clipping/ClipRect, Line, RadialPie, AntialiasingMode, indexed
  Colors, TextStyle and LoadFromIntfImage.  Everything above IChartDrawer is
  unchanged; only the mapping onto the canvas lives here.
}

unit TADrawerCanvas;

{$I TAChartDefines.inc}

interface

uses
  Winapi.Windows, System.Classes, System.SysUtils, System.Types,
  Vcl.Graphics,
  TAFPTypes, TAChartUtils, TADrawUtils;

type
  IChartTCanvasDrawer = interface
  ['{6D8E5591-6788-4D2D-9FE6-596D5157C3C2}']
    function GetCanvas: TCanvas;
    property Canvas: TCanvas read GetCanvas;
  end;

  { TCanvasDrawer }

  TCanvasDrawer = class(
    TBasicDrawer, IChartDrawer, IChartTCanvasDrawer)
  strict private
    FClipRect: TRect;
    FClipping: Boolean;
    FSavedClipRgn: HRGN;
    FHasSavedClipRgn: Boolean;
    procedure ApplyClipping(ACanvas: TCanvas);
    procedure RestoreClipping(ACanvas: TCanvas);
    procedure SetBrush(ABrush: TFPCustomBrush);
    procedure SetFont(AFont: TFPCustomFont);
    procedure SetPen(APen: TFPCustomPen);
    procedure DrawSimpleText(ACanvas: TCanvas; AX, AY: Integer;
      const AText: String);
  strict protected
    FCanvas: TCanvas;
    FBuffer: TBitmap;
    function GetFontAngle: Double; override;
    function SimpleTextExtent(const AText: String): TPoint; override;
    procedure SimpleTextOut(AX, AY: Integer; const AText: String); override;
  public
    procedure AddToFontOrientation(ADelta: Integer);
    procedure ClippingStart; overload;
    procedure ClippingStart(const AClipRect: TRect); overload;
    procedure ClippingStop;
    constructor Create(ACanvas: TCanvas);
    destructor Destroy; override;
    procedure Ellipse(AX1, AY1, AX2, AY2: Integer);
    procedure FillRect(AX1, AY1, AX2, AY2: Integer);
    function GetBrushColor: TChartColor;
    function GetCanvas: TCanvas; virtual;
    procedure Line(AX1, AY1, AX2, AY2: Integer); overload;
    procedure Line(const AP1, AP2: TPoint); overload;
    procedure LineTo(AX, AY: Integer); override;
    procedure MoveTo(AX, AY: Integer); override;
    procedure Polygon(
      const APoints: array of TPoint; AStartIndex, ANumPts: Integer); override;
    procedure Polyline(
      const APoints: array of TPoint; AStartIndex, ANumPts: Integer);
    procedure PrepareSimplePen(AColor: TChartColor);
    procedure PutImage(AX, AY: Integer; AImage: TFPCustomImage); override;
    procedure PutPixel(AX, AY: Integer; AColor: TChartColor); override;
    procedure RadialPie(
      AX1, AY1, AX2, AY2: Integer;
      AStartAngle16Deg, AAngleLength16Deg: Integer);
    procedure Rectangle(const ARect: TRect); overload;
    procedure Rectangle(AX1, AY1, AX2, AY2: Integer); overload;
    procedure ResetFont;
    procedure SetAntialiasingMode(AValue: TChartAntialiasingMode);
    procedure SetBrushColor(AColor: TChartColor);
    procedure SetBrushParams(AStyle: TFPBrushStyle; AColor: TChartColor);
    procedure SetPenParams(AStyle: TFPPenStyle; AColor: TChartColor);
    procedure SetTransparency(ATransparency: TChartTransparency);
  end;

  TScaledCanvasDrawer = class(TCanvasDrawer)
  protected
    FCoeff: Double;
  public
    constructor Create(ACanvas: TCanvas; ACoeff: Double; AScaleItems: TScaleItems);
    function Scale(ADistance: Integer): Integer; override;
  end;

  function CanvasGetFontOrientationFunc(AFont: TFPCustomFont): Integer;
  function ChartColorSysToFPColor(AChartColor: TChartColor): TFPColor;

implementation

uses
  System.Math, TAGeometry;

function CanvasGetFontOrientationFunc(AFont: TFPCustomFont): Integer;
begin
  if AFont is TFont then
    Result := TFont(AFont).Orientation
  else
    Result := 0;
end;

function ChartColorSysToFPColor(AChartColor: TChartColor): TFPColor;
begin
  Result := ChartColorToFPColor(ColorToRGB(AChartColor));
end;

// Copies the requested run of points into a contiguous array, because the VCL
// Polygon/Polyline take the whole open array.
function PointSlice(
  const APoints: array of TPoint; AStartIndex, ANumPts: Integer): TPointArray;
var
  i: Integer;
begin
  if ANumPts < 0 then
    ANumPts := Length(APoints) - AStartIndex;
  ANumPts := Min(ANumPts, Length(APoints) - AStartIndex);
  SetLength(Result, Max(ANumPts, 0));
  for i := 0 to High(Result) do
    Result[i] := APoints[AStartIndex + i];
end;

{ TCanvasDrawer }

procedure TCanvasDrawer.AddToFontOrientation(ADelta: Integer);
begin
  with GetCanvas.Font do
    Orientation := Orientation + ADelta;
end;

procedure TCanvasDrawer.ApplyClipping(ACanvas: TCanvas);
var
  rgn: HRGN;
begin
  if not FHasSavedClipRgn then begin
    // GetClipRgn returns 0 when the DC has no clipping region; remember that
    // as an empty handle so ClippingStop can restore the unclipped state.
    FSavedClipRgn := CreateRectRgn(0, 0, 1, 1);
    if GetClipRgn(ACanvas.Handle, FSavedClipRgn) <> 1 then begin
      DeleteObject(FSavedClipRgn);
      FSavedClipRgn := 0;
    end;
    FHasSavedClipRgn := true;
  end;
  rgn := CreateRectRgn(
    FClipRect.Left, FClipRect.Top, FClipRect.Right, FClipRect.Bottom);
  try
    SelectClipRgn(ACanvas.Handle, rgn);
  finally
    DeleteObject(rgn);
  end;
end;

procedure TCanvasDrawer.RestoreClipping(ACanvas: TCanvas);
begin
  if not FHasSavedClipRgn then begin
    SelectClipRgn(ACanvas.Handle, 0);
    exit;
  end;
  SelectClipRgn(ACanvas.Handle, FSavedClipRgn);
  if FSavedClipRgn <> 0 then begin
    DeleteObject(FSavedClipRgn);
    FSavedClipRgn := 0;
  end;
  FHasSavedClipRgn := false;
end;

procedure TCanvasDrawer.ClippingStart(const AClipRect: TRect);
begin
  FClipRect := AClipRect;
  ClippingStart;
end;

procedure TCanvasDrawer.ClippingStart;
begin
  FClipping := true;
  ApplyClipping(GetCanvas);
end;

procedure TCanvasDrawer.ClippingStop;
begin
  if not FClipping then exit;
  FClipping := false;
  RestoreClipping(GetCanvas);
end;

constructor TCanvasDrawer.Create(ACanvas: TCanvas);
begin
  inherited Create;
  FCanvas := ACanvas;
  FBuffer := TBitmap.Create;
  FBuffer.PixelFormat := pf32bit;
end;

destructor TCanvasDrawer.Destroy;
begin
  if FHasSavedClipRgn and (FSavedClipRgn <> 0) then
    DeleteObject(FSavedClipRgn);
  FreeAndNil(FBuffer);
  inherited;
end;

procedure TCanvasDrawer.Ellipse(AX1, AY1, AX2, AY2: Integer);
begin
  GetCanvas.Ellipse(AX1, AY1, AX2, AY2);
end;

procedure TCanvasDrawer.FillRect(AX1, AY1, AX2, AY2: Integer);
begin
  GetCanvas.FillRect(Rect(AX1, AY1, AX2, AY2));
end;

function TCanvasDrawer.GetBrushColor: TChartColor;
begin
  Result := GetCanvas.Brush.Color;
end;

function TCanvasDrawer.GetCanvas: TCanvas;
begin
  // When transparency is off, draw directly on canvas for better speed.
  if FTransparency > 0 then
    Result := FBuffer.Canvas
  else
    Result := FCanvas;
end;

function TCanvasDrawer.GetFontAngle: Double;
begin
  Result := OrientToRad(GetCanvas.Font.Orientation);
end;

procedure TCanvasDrawer.Line(AX1, AY1, AX2, AY2: Integer);
begin
  GetCanvas.MoveTo(AX1, AY1);
  GetCanvas.LineTo(AX2, AY2);
end;

procedure TCanvasDrawer.Line(const AP1, AP2: TPoint);
begin
  Line(AP1.X, AP1.Y, AP2.X, AP2.Y);
end;

procedure TCanvasDrawer.LineTo(AX, AY: Integer);
begin
  GetCanvas.LineTo(AX, AY);
end;

procedure TCanvasDrawer.MoveTo(AX, AY: Integer);
begin
  GetCanvas.MoveTo(AX, AY);
end;

procedure TCanvasDrawer.Polygon(
  const APoints: array of TPoint; AStartIndex, ANumPts: Integer);
var
  pts: TPointArray;
begin
  pts := PointSlice(APoints, AStartIndex, ANumPts);
  if Length(pts) < 2 then exit;
  GetCanvas.Polygon(pts);
end;

procedure TCanvasDrawer.Polyline(
  const APoints: array of TPoint; AStartIndex, ANumPts: Integer);
var
  pts: TPointArray;
begin
  if ANumPts <= 0 then exit;
  pts := PointSlice(APoints, AStartIndex, ANumPts);
  if pts = nil then exit;
  GetCanvas.Polyline(pts);
  // Polyline does not draw the end point.
  with pts[High(pts)] do
    GetCanvas.Pixels[X, Y] := GetCanvas.Pen.Color;
end;

procedure TCanvasDrawer.PrepareSimplePen(AColor: TChartColor);
begin
  with GetCanvas.Pen do begin
    if FXor then
      Color := clWhite
    else
      Color := ColorOrMono(AColor);
    Style := psSolid;
    if FXor then
      Mode := pmXor
    else
      Mode := pmCopy;
    if (scalePen in FScaleItems) then
      Width := Scale(1)
    else
      Width := 1;
  end;
end;

procedure TCanvasDrawer.PutImage(AX, AY: Integer; AImage: TFPCustomImage);
var
  x, y: Integer;
  c: TFPColor;
  cv: TCanvas;
begin
  cv := GetCanvas;
  if AImage is TChartIntfImage then begin
    TChartIntfImage(AImage).DrawTo(cv.Handle, AX, AY);
    exit;
  end;
  // Generic fallback for any other image implementation.
  for y := 0 to AImage.Height - 1 do
    for x := 0 to AImage.Width - 1 do begin
      c := AImage[x, y];
      if c.Alpha > 0 then
        cv.Pixels[AX + x, AY + y] := FPColorToChartColor(c);
    end;
end;

procedure TCanvasDrawer.PutPixel(AX, AY: Integer; AColor: TChartColor);
begin
  GetCanvas.Pixels[AX, AY] := AColor;
end;

procedure TCanvasDrawer.RadialPie(
  AX1, AY1, AX2, AY2: Integer;
  AStartAngle16Deg, AAngleLength16Deg: Integer);
var
  cx, cy, rx, ry: Double;
  a1, a2: Double;
  p1, p2: TPoint;
begin
  if AAngleLength16Deg = 0 then exit;
  cx := (AX1 + AX2) / 2;
  cy := (AY1 + AY2) / 2;
  rx := Abs(AX2 - AX1) / 2;
  ry := Abs(AY2 - AY1) / 2;
  // Angles arrive in 1/16 degree, counter-clockwise, as in the LCL.  GDI's Pie
  // also sweeps counter-clockwise, so only the radial end points are needed.
  a1 := DegToRad(AStartAngle16Deg / 16);
  a2 := DegToRad((AStartAngle16Deg + AAngleLength16Deg) / 16);
  // Enlarge the radius so the radial points are safely outside the ellipse;
  // GDI projects them back onto it.
  rx := rx * 2 + 2;
  ry := ry * 2 + 2;
  p1 := Point(Round(cx + rx * Cos(a1)), Round(cy - ry * Sin(a1)));
  p2 := Point(Round(cx + rx * Cos(a2)), Round(cy - ry * Sin(a2)));
  if AAngleLength16Deg < 0 then
    Winapi.Windows.Pie(GetCanvas.Handle, AX1, AY1, AX2, AY2,
      p2.X, p2.Y, p1.X, p1.Y)
  else
    Winapi.Windows.Pie(GetCanvas.Handle, AX1, AY1, AX2, AY2,
      p1.X, p1.Y, p2.X, p2.Y);
end;

procedure TCanvasDrawer.Rectangle(AX1, AY1, AX2, AY2: Integer);
begin
  GetCanvas.Rectangle(AX1, AY1, AX2, AY2);
end;

procedure TCanvasDrawer.Rectangle(const ARect: TRect);
begin
  GetCanvas.Rectangle(ARect);
end;

procedure TCanvasDrawer.ResetFont;
begin
  GetCanvas.Font.Orientation := 0;
end;

procedure TCanvasDrawer.SetAntialiasingMode(AValue: TChartAntialiasingMode);
begin
  // GDI has no antialiasing switch; the LCL forwards this to the widgetset.
  Unused(AValue);
end;

procedure TCanvasDrawer.SetBrush(ABrush: TFPCustomBrush);
begin
  with GetCanvas.Brush do begin
    Assign(ABrush);
    if FXor then
      Style := bsClear
    else if FMonochromeColor <> clTAColor then
      Color := FMonochromeColor;
  end;
end;

procedure TCanvasDrawer.SetBrushColor(AColor: TChartColor);
begin
  GetCanvas.Brush.Color := ColorOrMono(AColor);
end;

procedure TCanvasDrawer.SetBrushParams(
  AStyle: TFPBrushStyle; AColor: TChartColor);
begin
  GetCanvas.Brush.Color := ColorOrMono(AColor);
  GetCanvas.Brush.Style := AStyle;
end;

procedure TCanvasDrawer.SetFont(AFont: TFPCustomFont);
begin
  with GetCanvas.Font do begin
    Assign(AFont);
    if FMonochromeColor <> clTAColor then
      Color := FMonochromeColor;
    if scaleFont in FScaleItems then
      Size := Scale(IfThen(Size = 0, DEFAULT_FONT_SIZE, Size));
  end;
end;

procedure TCanvasDrawer.SetPen(APen: TFPCustomPen);
begin
  with GetCanvas do begin
    if FXor then begin
      Brush.Style := bsClear;
      if APen = nil then begin
        Pen.Style := psSolid;
        Pen.Width := 1;
      end
      else begin
        Pen.Style := APen.Style;
        Pen.Width := APen.Width;
      end;
      Pen.Mode := pmXor;
      Pen.Color := clWhite;
    end
    else begin
      Pen.Assign(APen);
      if FMonochromeColor <> clTAColor then
        Pen.Color := FMonochromeColor;
    end;
    if scalePen in FScaleItems then
      Pen.Width := Scale(Pen.Width);
  end;
end;

procedure TCanvasDrawer.SetPenParams(AStyle: TFPPenStyle; AColor: TChartColor);
begin
  GetCanvas.Pen.Style := AStyle;
  if not FXor then
    GetCanvas.Pen.Color := ColorOrMono(AColor);
end;

procedure TCanvasDrawer.SetTransparency(ATransparency: TChartTransparency);

  { Flips the alpha byte of every pixel in the buffer.

    The buffer is primed with alpha = $FF; GDI drawing operations zero the
    alpha byte of every pixel they touch, so after the flip the pixels that
    were drawn on carry $FF and the untouched ones carry $00.  That is exactly
    the mask AlphaBlend needs, and because the drawn pixels are fully opaque
    the buffer already satisfies its premultiplied-source requirement.
    Returns True if anything was drawn. }
  function FlipAlpha: Boolean;
  var
    p, pEnd: PCardinal;
    acc: Cardinal;
    stride: Integer;
  begin
    Result := false;
    if (FBuffer.Width <= 0) or (FBuffer.Height <= 0) then exit;
    stride := FBuffer.Width * 4;
    // A bottom-up DIB stores the last row first, so that is the buffer start.
    p := PCardinal(FBuffer.ScanLine[FBuffer.Height - 1]);
    pEnd := PCardinal(PByte(p) + NativeInt(stride) * FBuffer.Height);
    acc := 0;
    while NativeUInt(p) < NativeUInt(pEnd) do begin
      p^ := p^ xor $FF000000;
      acc := acc or p^;
      Inc(p);
    end;
    Result := acc and $FF000000 <> 0;
  end;

var
  bf: TBlendFunction;
begin
  if FTransparency = ATransparency then exit;
  // Drawing with transparency goes onto a 32 bit buffer that is alpha-blended
  // onto the real canvas when the transparency setting changes again.
  if (FTransparency > 0) and FlipAlpha then begin
    bf.BlendOp := AC_SRC_OVER;
    bf.BlendFlags := 0;
    bf.SourceConstantAlpha := 255 - FTransparency;
    bf.AlphaFormat := AC_SRC_ALPHA;
    Winapi.Windows.AlphaBlend(
      FCanvas.Handle, 0, 0, FBuffer.Width, FBuffer.Height,
      FBuffer.Canvas.Handle, 0, 0, FBuffer.Width, FBuffer.Height, bf);
  end;
  inherited;
  if FTransparency > 0 then begin
    FBuffer.SetSize(0, 0);
    FBuffer.PixelFormat := pf32bit;
    FBuffer.SetSize(Max(FCanvas.ClipRect.Right, 1), Max(FCanvas.ClipRect.Bottom, 1));
    if FBuffer.Height > 0 then
      FillChar(FBuffer.ScanLine[FBuffer.Height - 1]^,
        FBuffer.Width * 4 * FBuffer.Height, 0);
    FlipAlpha;
    if FClipping then
      ApplyClipping(FBuffer.Canvas);
  end;
end;

function TCanvasDrawer.SimpleTextExtent(const AText: String): TPoint;
var
  sz: TSize;
begin
  sz := GetCanvas.TextExtent(AText);
  Result := Point(sz.cx, sz.cy);
end;

procedure TCanvasDrawer.DrawSimpleText(
  ACanvas: TCanvas; AX, AY: Integer; const AText: String);
var
  flags: UINT;
  oldMode: Integer;
begin
  // TAChart paints label backgrounds itself, so text is always drawn with a
  // transparent background, matching the LCL's default TTextStyle.
  oldMode := SetBkMode(ACanvas.Handle, TRANSPARENT);
  try
    flags := 0;
    if FRightToLeft then
      flags := ETO_RTLREADING;
    Winapi.Windows.ExtTextOut(
      ACanvas.Handle, AX, AY, flags, nil, PChar(AText), Length(AText), nil);
  finally
    SetBkMode(ACanvas.Handle, oldMode);
  end;
end;

procedure TCanvasDrawer.SimpleTextOut(AX, AY: Integer; const AText: String);

  procedure DrawXorText;
  var
    bmp: TBitmap;
    p, ext, bmpSize: TPoint;
    a: Double;
  begin
    ext := SimpleTextExtent(AText);
    a := OrientToRad(GetCanvas.Font.Orientation);
    bmpSize := SizeToPoint(MeasureRotatedRect(ext, a));
    p := DivPoint(bmpSize, 2) - RotatePoint(DivPoint(ext, 2), -a);

    bmp := TBitmap.Create;
    try
      bmp.SetSize(bmpSize.X, bmpSize.Y);
      bmp.Canvas.Brush.Style := bsSolid;
      bmp.Canvas.Brush.Color := clBlack;
      bmp.Canvas.FillRect(Rect(0, 0, bmpSize.X, bmpSize.Y));
      bmp.Canvas.Font := GetCanvas.Font;
      bmp.Canvas.Font.Color := clWhite;
      DrawSimpleText(bmp.Canvas, p.X, p.Y, AText);
      BitBlt(
        GetCanvas.Handle, AX - p.X, AY - p.Y, bmpSize.X, bmpSize.Y,
        bmp.Canvas.Handle, 0, 0, SRCINVERT);
    finally
      bmp.Free;
    end;
  end;

begin
  if FXor then
    DrawXorText
  else
    DrawSimpleText(GetCanvas, AX, AY, AText);
end;

{ TScaledCanvasDrawer }

constructor TScaledCanvasDrawer.Create(ACanvas: TCanvas; ACoeff: Double;
  AScaleItems: TScaleItems);
begin
  inherited Create(ACanvas);
  FCoeff := ACoeff;
  FScaleItems := AScaleItems;
end;

function TScaledCanvasDrawer.Scale(ADistance: Integer): Integer;
begin
  Result := Round(FCoeff * ADistance);
end;

end.
