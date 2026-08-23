{
 *****************************************************************************
  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  Authors: Alexander Klenin

  Delphi/VCL port notes
  ---------------------
  * The pen state is kept in a plain record: upstream instantiates a
    TFPCustomPen as a value holder, which maps to a VCL TPen here and would
    drag a GDI handle along for no benefit.
  * Strings are written to the stream as UTF-8 (Delphi strings are UTF-16).
  * Text is XML-escaped; the original writes it raw, which produces invalid
    SVG for labels containing '<', '>' or '&'.
  * PutImage encodes through Vcl.Imaging.pngimage and System.NetEncoding
    instead of FPWritePNG/Base64.
}

unit TADrawerSVG;

{$I TAChartDefines.inc}

interface

uses
  System.Classes, System.Types, Vcl.Graphics,
  TAFPTypes, TAChartUtils, TADrawUtils, TAGraph;

type
  TSVGFont = record
    Name: String;
    Color: TFPColor;
    Size: Integer;
    Orientation: Integer;  // angle * 10 (90 deg --> 900), > 0 if ccw.
    Bold: Boolean;
    Italic: Boolean;
    Underline: Boolean;
    StrikeThrough: Boolean;
  end;

  TSVGPen = record
    Color: TFPColor;
    Style: TFPPenStyle;
    Width: Integer;
  end;

  { TSVGDrawer }

  TSVGDrawer = class(TBasicDrawer, IChartDrawer)
  strict private
    FAntialiasingMode: TChartAntialiasingMode;
    FBrushColor: TFPColor;
    FBrushStyle: TFPBrushStyle;
    FClippingPathId: Integer;
    FFont: TSVGFont;
    FPatterns: TStrings;
    FPen: TSVGPen;
    FPrevPos: TPoint;
    FStream: TStream;

    function FontSize: Integer; inline;
    function OpacityStr: String;
    function PointsToStr(
      const APoints: array of TPoint; AStartIndex, ANumPts: Integer): String;

    procedure SetBrush(ABrush: TFPCustomBrush);
    procedure SetFont(AFont: TFPCustomFont);
    procedure SetPen(APen: TFPCustomPen);

    function StyleFill: String;
    function StyleStroke: String;

    procedure WriteFmt(const AFormat: String; const AParams: array of const);
    procedure WriteStr(const AString: String);
  strict protected
    function GetFontAngle: Double; override;
    function SimpleTextExtent(const AText: String): TPoint; override;
    procedure SimpleTextOut(AX, AY: Integer; const AText: String); override;
  public
    constructor Create(AStream: TStream; AWriteDocType: Boolean);
    destructor Destroy; override;
  public
    procedure AddToFontOrientation(ADelta: Integer);
    procedure ClippingStart; overload;
    procedure ClippingStart(const AClipRect: TRect); overload;
    procedure ClippingStop;
    procedure DrawingBegin(const ABoundingBox: TRect); override;
    procedure DrawingEnd; override;
    procedure Ellipse(AX1, AY1, AX2, AY2: Integer);
    procedure FillRect(AX1, AY1, AX2, AY2: Integer);
    function GetBrushColor: TChartColor;
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
  end;

// Not a class helper: TADrawerWMF already installs one on TTAChart, and
// Delphi only honours a single helper per class at any point in the code.
procedure SaveChartToSVGFile(AChart: TTAChart; const AFileName: String);

implementation

uses
  System.Math, System.SysUtils, System.NetEncoding,
  Vcl.Imaging.pngimage,
  TAGeometry;

const
  RECT_FMT =
    '<rect x="%d" y="%d" width="%d" height="%d" style="%s"/>';
var
  fmtSettings: TFormatSettings;

function EscapeXML(const AText: String): String;
begin
  Result := AText;
  Result := StringReplace(Result, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
end;

function ColorToHex(AColor: TFPColor): String;
begin
  if FPColorsEqual(AColor, colBlack) then
    Result := 'black'
  else if FPColorsEqual(AColor, colWhite) then
    Result := 'white'
  else
    with AColor do
      Result := Format('#%.2x%.2x%.2x', [Red shr 8, Green shr 8, Blue shr 8]);
end;

function DP2S(AValue: TDoublePoint): String;
begin
  Result := Format('%g,%g', [AValue.X, AValue.Y], fmtSettings);
end;

function SVGGetFontOrientationFunc(AFont: TFPCustomFont): Integer;
begin
  Result := AFont.Orientation;
end;

function SVGChartColorToFPColor(AChartColor: TChartColor): TFPColor;
begin
  Result := ChartColorToFPColor(ColorToRGB(AChartColor));
end;

{ TSVGDrawer }

procedure TSVGDrawer.AddToFontOrientation(ADelta: Integer);
begin
  FFont.Orientation := FFont.Orientation + ADelta;
end;

procedure TSVGDrawer.ClippingStart(const AClipRect: TRect);
begin
  FClippingPathId := FClippingPathId + 1;
  WriteFmt('<clipPath id="clip%d">', [FClippingPathId]);
  with AClipRect do
    WriteFmt(RECT_FMT, [Left, Top, Right - Left, Bottom - Top, '']);
  WriteStr('</clipPath>');
  ClippingStart;
end;

procedure TSVGDrawer.ClippingStart;
begin
  WriteFmt('<g clip-path="url(#clip%d)">', [FClippingPathId]);
end;

procedure TSVGDrawer.ClippingStop;
begin
  WriteStr('</g>');
end;

constructor TSVGDrawer.Create(AStream: TStream; AWriteDocType: Boolean);
begin
  inherited Create;
  FStream := AStream;
  FPatterns := TStringList.Create;
  FPen.Style := psSolid;
  FPen.Width := 1;
  FGetFontOrientationFunc := SVGGetFontOrientationFunc;
  FChartColorToFPColorFunc := SVGChartColorToFPColor;
  if AWriteDocType then begin
    WriteStr('<?xml version="1.0"?>');
    WriteStr('<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.0//EN"');
    WriteStr('"http://www.w3.org/TR/2001/REC-SVG-20010904/DTD/svg10.dtd">');
  end;
end;

destructor TSVGDrawer.Destroy;
begin
  FreeAndNil(FPatterns);
  inherited Destroy;
end;

procedure TSVGDrawer.DrawingBegin(const ABoundingBox: TRect);
begin
  FAntialiasingMode := amDontCare;
  with ABoundingBox do
    WriteFmt(
      '<svg ' +
      'xmlns="http://www.w3.org/2000/svg" ' +
      'xmlns:xlink="http://www.w3.org/1999/xlink" ' +
      'width="%dpx" height="%dpx" viewBox="%d %d %d %d">',
      [Right - Left, Bottom - Top, Left, Top, Right, Bottom]);
  FClippingPathId := 0;
end;

procedure TSVGDrawer.DrawingEnd;
var
  i: Integer;
begin
  if FAntialiasingMode <> amDontCare then
    WriteStr('</g>');
  if FPatterns.Count > 0 then begin
    WriteStr('<defs>');
    for i := 0 to FPatterns.Count - 1 do
      WriteFmt(
        '<pattern id="bs%d" width="8" height="8" patternUnits="userSpaceOnUse">' +
        '%s</pattern>',
        [i, FPatterns[i]]);
    WriteStr('</defs>');
    FPatterns.Clear;
  end;
  WriteStr('</svg>');
end;

procedure TSVGDrawer.Ellipse(AX1, AY1, AX2, AY2: Integer);
var
  e: TEllipse;
begin
  e.InitBoundingBox(AX1, AY1, AX2, AY2);
  WriteFmt(
    '<ellipse cx="%g" cy="%g" rx="%g" ry="%g" style="%s"/>',
    [e.FC.X, e.FC.Y, e.FR.X, e.FR.Y, StyleFill + StyleStroke]);
end;

procedure TSVGDrawer.FillRect(AX1, AY1, AX2, AY2: Integer);
begin
  WriteFmt(RECT_FMT, [AX1, AY1, AX2 - AX1, AY2 - AY1, StyleFill]);
end;

function TSVGDrawer.FontSize: Integer;
begin
  Result := IfThen(FFont.Size = 0, 8, FFont.Size);
end;

function TSVGDrawer.GetBrushColor: TChartColor;
begin
  Result := FPColorToChartColor(FBrushColor);
end;

function TSVGDrawer.GetFontAngle: Double;
begin
  Result := FFont.Orientation;
end;

procedure TSVGDrawer.Line(AX1, AY1, AX2, AY2: Integer);
begin
  WriteFmt(
    '<line x1="%d" y1="%d" x2="%d" y2="%d" style="%s"/>',
    [AX1, AY1, AX2, AY2, StyleStroke]);
end;

procedure TSVGDrawer.Line(const AP1, AP2: TPoint);
begin
  Line(AP1.X, AP1.Y, AP2.X, AP2.Y);
end;

procedure TSVGDrawer.LineTo(AX, AY: Integer);
begin
  Line(FPrevPos.X, FPrevPos.Y, AX, AY);
  FPrevPos := Point(AX, AY);
end;

procedure TSVGDrawer.MoveTo(AX, AY: Integer);
begin
  FPrevPos := Point(AX, AY);
end;

function TSVGDrawer.OpacityStr: String;
begin
  if FTransparency = 0 then
    Result := ''
  else
    Result := FloatToStr((255 - FTransparency) / 256, fmtSettings);
end;

function TSVGDrawer.PointsToStr(
  const APoints: array of TPoint; AStartIndex, ANumPts: Integer): String;
var
  i: Integer;
begin
  if ANumPts < 0 then
    ANumPts := Length(APoints) - AStartIndex;
  Result := '';
  for i := 0 to ANumPts - 1 do
    with APoints[i + AStartIndex] do
      Result := Result + Format('%d %d ', [X, Y]);
end;

procedure TSVGDrawer.Polygon(
  const APoints: array of TPoint; AStartIndex, ANumPts: Integer);
begin
  WriteFmt(
    '<polygon points="%s" style="%s"/>',
    [PointsToStr(APoints, AStartIndex, ANumPts), StyleFill + StyleStroke]);
end;

procedure TSVGDrawer.Polyline(
  const APoints: array of TPoint; AStartIndex, ANumPts: Integer);
begin
  WriteFmt(
    '<polyline points="%s" style="fill: none; %s"/>',
    [PointsToStr(APoints, AStartIndex, ANumPts), StyleStroke]);
end;

procedure TSVGDrawer.PrepareSimplePen(AColor: TChartColor);
begin
  FPen.Color := FChartColorToFPColorFunc(ColorOrMono(AColor));
  FPen.Style := psSolid;
  FPen.Width := 1;
end;

procedure TSVGDrawer.PutImage(AX, AY: Integer; AImage: TFPCustomImage);
var
  bmp: TBitmap;
  png: TPngImage;
  ms: TMemoryStream;
  x, y: Integer;
  c: TFPColor;
  line: PCardinal;
  encoded: String;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(AImage.Width, AImage.Height);
    bmp.AlphaFormat := afDefined;
    for y := 0 to AImage.Height - 1 do begin
      line := bmp.ScanLine[y];
      for x := 0 to AImage.Width - 1 do begin
        c := AImage[x, y];
        // BGRA with straight alpha.
        line^ :=
          Cardinal(c.Blue shr 8) or
          (Cardinal(c.Green shr 8) shl 8) or
          (Cardinal(c.Red shr 8) shl 16) or
          (Cardinal(c.Alpha shr 8) shl 24);
        Inc(line);
      end;
    end;
    png := TPngImage.Create;
    ms := TMemoryStream.Create;
    try
      png.Assign(bmp);
      png.SaveToStream(ms);
      // CharsPerLine = 0: no line breaks inside the data URI.
      with TBase64Encoding.Create(0) do
        try
          encoded := EncodeBytesToString(ms.Memory, ms.Size);
        finally
          Free;
        end;
      WriteFmt(
        '<image x="%d" y="%d" width="%d" height="%d" ' +
        'xlink:href="data:image/png;base64,%s"/>',
        [AX, AY, AImage.Width, AImage.Height, encoded]);
    finally
      ms.Free;
      png.Free;
    end;
  finally
    bmp.Free;
  end;
end;

procedure TSVGDrawer.PutPixel(AX, AY: Integer; AColor: TChartColor);
var
  stroke: String;
begin
  stroke := 'stroke:' +
    ColorToHex(FChartColorToFPColorFunc(ColorOrMono(AColor))) +
    ';stroke-width:1;';
  WriteFmt(RECT_FMT, [AX, AY, 1, 1, stroke]);
end;

procedure TSVGDrawer.RadialPie(
  AX1, AY1, AX2, AY2: Integer; AStartAngle16Deg, AAngleLength16Deg: Integer);
var
  e: TEllipse;
  p1, p2: TDoublePoint;
begin
  e.InitBoundingBox(AX1, AY1, AX2, AY2);
  p1 := e.GetPoint(Deg16ToRad(AStartAngle16Deg));
  p2 := e.GetPoint(Deg16ToRad(AStartAngle16Deg + AAngleLength16Deg));
  WriteFmt(
    '<path d="M%s L%s A%s 0 0,0 %s Z" style="%s"/>',
    [DP2S(e.FC), DP2S(p1), DP2S(e.FR), DP2S(p2), StyleFill + StyleStroke]);
end;

procedure TSVGDrawer.Rectangle(AX1, AY1, AX2, AY2: Integer);
begin
  WriteFmt(
    RECT_FMT, [AX1, AY1, AX2 - AX1, AY2 - AY1, StyleFill + StyleStroke]);
end;

procedure TSVGDrawer.Rectangle(const ARect: TRect);
begin
  with ARect do
    Rectangle(Left, Top, Right, Bottom);
end;

procedure TSVGDrawer.ResetFont;
begin
  FFont.Orientation := 0;
end;

procedure TSVGDrawer.SetAntialiasingMode(AValue: TChartAntialiasingMode);
const
  AM_TO_CSS: array [amOn .. amOff] of String =
    ('geometricPrecision', 'crispEdges');
begin
  if FAntialiasingMode = AValue then exit;
  if FAntialiasingMode <> amDontCare then
    WriteStr('</g>');
  FAntialiasingMode := AValue;
  if FAntialiasingMode <> amDontCare then
    WriteFmt('<g style="shape-rendering: %s">', [AM_TO_CSS[FAntialiasingMode]]);
end;

procedure TSVGDrawer.SetBrush(ABrush: TFPCustomBrush);
begin
  FBrushColor := FChartColorToFPColorFunc(ColorOrMono(ABrush.Color));
  FBrushStyle := ABrush.Style;
end;

procedure TSVGDrawer.SetBrushColor(AColor: TChartColor);
begin
  FBrushColor := FChartColorToFPColorFunc(ColorOrMono(AColor));
end;

procedure TSVGDrawer.SetBrushParams(
  AStyle: TFPBrushStyle; AColor: TChartColor);
begin
  FBrushColor := FChartColorToFPColorFunc(ColorOrMono(AColor));
  FBrushStyle := AStyle;
end;

procedure TSVGDrawer.SetFont(AFont: TFPCustomFont);
begin
  FFont.Name := AFont.Name;
  FFont.Size := IfThen(AFont.Size = 0, 8, AFont.Size);
  if FMonochromeColor <> clTAColor then
    FFont.Color := FChartColorToFPColorFunc(FMonochromeColor)
  else
    FFont.Color := FChartColorToFPColorFunc(ColorToRGB(AFont.Color));
  FFont.Orientation := FGetFontOrientationFunc(AFont);
  FFont.Bold := fsBold in AFont.Style;
  FFont.Italic := fsItalic in AFont.Style;
  FFont.Underline := fsUnderline in AFont.Style;
  FFont.StrikeThrough := fsStrikeOut in AFont.Style;
end;

procedure TSVGDrawer.SetPen(APen: TFPCustomPen);
begin
  FPen.Color := FChartColorToFPColorFunc(ColorOrMono(APen.Color));
  FPen.Style := APen.Style;
  FPen.Width := APen.Width;
end;

procedure TSVGDrawer.SetPenParams(AStyle: TFPPenStyle; AColor: TChartColor);
begin
  FPen.Color := FChartColorToFPColorFunc(ColorOrMono(AColor));
  FPen.Style := AStyle;
end;

function TSVGDrawer.SimpleTextExtent(const AText: String): TPoint;
begin
  // SVG has no way to determine text size; use the same heuristics
  // as the Lazarus original.
  Result.X := FontSize * Length(AText) * 2 div 3;
  Result.Y := FontSize;
end;

procedure TSVGDrawer.SimpleTextOut(AX, AY: Integer; const AText: String);
var
  p: TPoint;
  stext: String;
  sstyle: String;
begin
  p := RotatePoint(Point(0, FontSize), OrientToRad(-FFont.Orientation)) +
    Point(AX, AY);
  stext := Format('x="%d" y="%d"', [p.X, p.Y]);
  if FFont.Orientation <> 0 then
    stext := stext + Format(
      ' transform="rotate(%g,%d,%d)"',
      [-FFont.Orientation * 0.1, p.X, p.Y], fmtSettings);

  sstyle := Format('fill:%s; font-family:''%s''; font-size:%dpt;',
    [ColorToHex(FFont.Color), FFont.Name, FontSize]);
  if FFont.Bold then
    sstyle := sstyle + ' font-weight:bold;';
  if FFont.Italic then
    sstyle := sstyle + ' font-style:oblique;';
  if FFont.Underline and FFont.StrikeThrough then
    sstyle := sstyle + ' text-decoration:underline,line-through;'
  else if FFont.Underline then
    sstyle := sstyle + ' text-decoration:underline;'
  else if FFont.StrikeThrough then
    sstyle := sstyle + ' text-decoration:line-through;';
  if OpacityStr <> '' then
    sstyle := sstyle + 'fill-opacity:' + OpacityStr + ';';

  WriteFmt('<text %s style="%s">%s</text>', [stext, sstyle, EscapeXML(AText)]);
end;

function TSVGDrawer.StyleFill: String;

  function AddPattern(const APattern: String): String;
  var
    i: Integer;
  begin
    i := FPatterns.IndexOf(APattern);
    if i < 0 then
      i := FPatterns.Add(APattern);
    Result := Format('url(#bs%d)', [i]);
  end;

const
  PATTERNS: array [TFPBrushStyle] of String = (
    '', '',
    'M0,4 h8',              // bsHorizontal
    'M4,0 v8',              // bsVertical
    'M0,0 l8,8',            // bsFDiagonal
    'M0,8 l8,-8',           // bsBDiagonal
    'M0,4 h8 M4,0 v8',      // bsCross
    'M0,0 l8,8 M0,8 l8,-8');// bsDiagCross
var
  fill: String;
begin
  case FBrushStyle of
    bsClear: begin Result := 'fill: none;'; exit; end;
    bsHorizontal..bsDiagCross:
      fill := AddPattern(Format(
        '<path d="%s" stroke="%s"/>',
        [PATTERNS[FBrushStyle], ColorToHex(FBrushColor)]));
    else
      fill := ColorToHex(FBrushColor);
  end;
  Result :=
    Format('fill:%s;', [fill]) +
    FormatIfNotEmpty('fill-opacity:%s;', OpacityStr);
end;

function TSVGDrawer.StyleStroke: String;
const
  PEN_DASHARRAY: array [TFPPenStyle] of String =
    ('', '2,2', '1,1', '2,1,1,1', '2,1,1,1,1,1', '', '', '', '');
begin
  if FPen.Style = psClear then begin
    Result := 'stroke: none';
    exit;
  end;
  Result := 'stroke:' + ColorToHex(FPen.Color) + ';';
  if FPen.Width <> 1 then
    Result := Result + 'stroke-width:' + IntToStr(FPen.Width) + ';';
  Result := Result +
    FormatIfNotEmpty('stroke-dasharray:%s;', PEN_DASHARRAY[FPen.Style]) +
    FormatIfNotEmpty('stroke-opacity:%s;', OpacityStr);
end;

procedure TSVGDrawer.WriteFmt(const AFormat: String; const AParams: array of const);
begin
  WriteStr(Format(AFormat, AParams));
end;

procedure TSVGDrawer.WriteStr(const AString: String);
var
  bytes: TBytes;
begin
  bytes := TEncoding.UTF8.GetBytes(AString + sLineBreak);
  if Length(bytes) > 0 then
    FStream.WriteBuffer(bytes[0], Length(bytes));
end;

procedure SaveChartToSVGFile(AChart: TTAChart; const AFileName: String);
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(AFileName, fmCreate);
  try
    AChart.Draw(
      TSVGDrawer.Create(fs, true), Rect(0, 0, AChart.Width, AChart.Height));
  finally
    fs.Free;
  end;
end;

initialization

  fmtSettings := FormatSettings;
  fmtSettings.DecimalSeparator := '.';

end.
