{
 *****************************************************************************
  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  Authors: Alexander Klenin, Werner Pamler

  Delphi/VCL port notes
  ---------------------
  * The caller owns the OpenGL context: make it current and set up a 2D
    projection with the origin in the top-left corner before Chart.Draw, e.g.

        glViewport(0, 0, w, h);
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity;
        glOrtho(0, w, h, 0, -1, 1);   // y axis pointing down
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity;
        Chart.Draw(TOpenGLDrawer.Create, Rect(0, 0, w, h));

  * Text: the Lazarus original renders glyphs with LazFreeType (or GLUT's
    fixed 8x13 font when compiled without it).  Neither exists in Delphi, so
    this port rasterises text with GDI into luminance-alpha textures - the
    same texture pipeline as upstream's FreeType path, including the cache and
    rotated output.  Because the textures are built with GDI there is no font
    directory to configure: InitFonts/DoneFonts are provided as no-ops for
    source compatibility with Lazarus demos.

  * Texture cache entries hold GL texture ids, which are only valid while a
    context is current; the cache is cleared through ChartGLFreeTextures
    (called automatically when the drawer is destroyed with a live context).
}

unit TADrawerOpenGL;

{$I TAChartDefines.inc}

interface

uses
  Winapi.Windows, Winapi.OpenGL, System.Classes, System.SysUtils, System.Types,
  Vcl.Graphics,
  TAFPTypes, TAChartUtils, TADrawUtils;

type

  { TOpenGLDrawer }

  TOpenGLDrawer = class(TBasicDrawer, IChartDrawer)
  strict private
    FBrushColor: TFPColor;
    FFontColor: TFPColor;
    FPenColor: TFPColor;
    FPenStyle: TFPPenStyle;
    FPenWidth: Integer;
    FFontName: String;
    FFontSize: Integer;
    FFontStyle: TFontStyles;
    FFontAngle: Double;    // degrees
    FPos: TPoint;
    procedure ChartGLColor(AColor: TFPColor);
    procedure ChartGLPenStyle(APenStyle: TFPPenStyle);
    procedure InternalPolyline(
      const APoints: array of TPoint; AStartIndex, ANumPts, AMode: Integer);
    procedure SetBrush(ABrush: TFPCustomBrush);
    procedure SetFont(AFont: TFPCustomFont);
    procedure SetPen(APen: TFPCustomPen);
  strict protected
    function GetFontAngle: Double; override;
    function SimpleTextExtent(const AText: String): TPoint; override;
    procedure SimpleTextOut(AX, AY: Integer; const AText: String); override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddToFontOrientation(ADelta: Integer);
    procedure ClippingStart; overload;
    procedure ClippingStart(const AClipRect: TRect); overload;
    procedure ClippingStop;
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
    procedure SetTransparency(ATransparency: TChartTransparency);
  end;

// No-ops, kept for source compatibility with the Lazarus version, where they
// configure the FreeType font search path.
procedure InitFonts(const AFontDir: String = '');
procedure DoneFonts;

// Deletes every cached text texture.  Call when the GL context that the chart
// was drawn on is about to be destroyed.
procedure ChartGLFreeTextures;

implementation

uses
  System.Math, TAGeometry;

{ ---------------------------------------------------------------------------
  GDI-based text-texture helper (replaces upstream's TGLFreeTypeHelper)
  --------------------------------------------------------------------------- }

type
  TTextureCacheItem = class
    TextureID: GLuint;
    TextWidth: Integer;
    TextHeight: Integer;
  end;

  TGLChartTextHelper = class
  strict private
    FBmp: TBitmap;
    FTextureCache: TStringList;
    function BuildTextureName(const AText: String): String;
    procedure CreateTexture(const AText: String; out ATextWidth, ATextHeight,
      ATextureWidth, ATextureHeight: Integer; out ATextureID: GLuint);
    function FindTexture(const AText: String; out ATextWidth, ATextHeight,
      ATextureWidth, ATextureHeight: Integer): GLuint;
  public
    constructor Create;
    destructor Destroy; override;
    procedure FreeTextures;
    procedure RenderText(const AText: String);
    procedure SetFont(const AFontName: String; AFontSize: Integer;
      AStyle: TFontStyles);
    procedure TextExtent(const AText: String; out AWidth, AHeight: Integer);
  end;

var
  VTextHelper: TGLChartTextHelper = nil;

function TextHelper: TGLChartTextHelper;
begin
  if VTextHelper = nil then
    VTextHelper := TGLChartTextHelper.Create;
  Result := VTextHelper;
end;

function NextPowerOf2(n: Integer): Integer;
begin
  Result := 1;
  while Result < n do
    Result := Result * 2;
end;

constructor TGLChartTextHelper.Create;
begin
  FBmp := TBitmap.Create;
  FBmp.PixelFormat := pf32bit;
  // Plain antialiasing; ClearType would leak subpixel colours into the
  // single-channel coverage data.
  FBmp.Canvas.Font.Quality := fqAntialiased;
  FTextureCache := TStringList.Create;
  FTextureCache.Sorted := true;
  FTextureCache.OwnsObjects := true;
end;

destructor TGLChartTextHelper.Destroy;
begin
  FreeTextures;
  FreeAndNil(FTextureCache);
  FreeAndNil(FBmp);
  inherited;
end;

procedure TGLChartTextHelper.FreeTextures;
var
  i: Integer;
  item: TTextureCacheItem;
begin
  // Texture ids belong to the GL context; without a current context there is
  // nothing to delete (and the ids died with the context anyway).
  if wglGetCurrentContext <> 0 then
    for i := 0 to FTextureCache.Count - 1 do begin
      item := TTextureCacheItem(FTextureCache.Objects[i]);
      if item.TextureID <> 0 then
        glDeleteTextures(1, @item.TextureID);
    end;
  FTextureCache.Clear;
end;

function TGLChartTextHelper.BuildTextureName(const AText: String): String;
var
  style: Integer;
begin
  style := 0;
  if fsBold in FBmp.Canvas.Font.Style then Inc(style, 1);
  if fsItalic in FBmp.Canvas.Font.Style then Inc(style, 2);
  if fsUnderline in FBmp.Canvas.Font.Style then Inc(style, 4);
  if fsStrikeOut in FBmp.Canvas.Font.Style then Inc(style, 8);
  Result := Format('%s|%d|%d|%s',
    [FBmp.Canvas.Font.Name, FBmp.Canvas.Font.Size, style, AText]);
end;

procedure TGLChartTextHelper.CreateTexture(const AText: String;
  out ATextWidth, ATextHeight, ATextureWidth, ATextureHeight: Integer;
  out ATextureID: GLuint);
var
  data: array of Byte;
  x, y: Integer;
  sz: TSize;
  line: PCardinal;
  coverage: Cardinal;
begin
  sz := FBmp.Canvas.TextExtent(AText);
  ATextWidth := sz.cx;
  ATextHeight := sz.cy;
  ATextureWidth := NextPowerOf2(Max(ATextWidth, 1));
  ATextureHeight := NextPowerOf2(Max(ATextHeight, 1));

  // White text on black; any channel is then the glyph coverage.
  FBmp.SetSize(ATextureWidth, ATextureHeight);
  FBmp.Canvas.Brush.Style := bsSolid;
  FBmp.Canvas.Brush.Color := clBlack;
  FBmp.Canvas.FillRect(Rect(0, 0, ATextureWidth, ATextureHeight));
  FBmp.Canvas.Font.Color := clWhite;
  FBmp.Canvas.Brush.Style := bsClear;
  FBmp.Canvas.TextOut(0, 0, AText);

  SetLength(data, 2 * ATextureWidth * ATextureHeight);
  for y := 0 to ATextureHeight - 1 do begin
    line := FBmp.ScanLine[y];
    for x := 0 to ATextureWidth - 1 do begin
      coverage := (line^ shr 8) and $FF;  // green channel
      data[2 * (x + y * ATextureWidth)] := 255;              // luminosity
      data[2 * (x + y * ATextureWidth) + 1] := Byte(coverage); // alpha
      Inc(line);
    end;
  end;

  glGenTextures(1, @ATextureID);
  glBindTexture(GL_TEXTURE_2D, ATextureID);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, ATextureWidth, ATextureHeight, 0,
    GL_LUMINANCE_ALPHA, GL_UNSIGNED_BYTE, @data[0]);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
end;

function TGLChartTextHelper.FindTexture(const AText: String;
  out ATextWidth, ATextHeight, ATextureWidth, ATextureHeight: Integer): GLuint;
var
  idx: Integer;
  item: TTextureCacheItem;
  txname: String;
begin
  txname := BuildTextureName(AText);
  idx := FTextureCache.IndexOf(txname);
  if idx = -1 then begin
    CreateTexture(
      AText, ATextWidth, ATextHeight, ATextureWidth, ATextureHeight, Result);
    item := TTextureCacheItem.Create;
    item.TextureID := Result;
    item.TextWidth := ATextWidth;
    item.TextHeight := ATextHeight;
    FTextureCache.AddObject(txname, item);
  end
  else begin
    item := TTextureCacheItem(FTextureCache.Objects[idx]);
    Result := item.TextureID;
    ATextWidth := item.TextWidth;
    ATextHeight := item.TextHeight;
    ATextureWidth := NextPowerOf2(Max(ATextWidth, 1));
    ATextureHeight := NextPowerOf2(Max(ATextHeight, 1));
  end;
end;

procedure TGLChartTextHelper.RenderText(const AText: String);
var
  textureID: GLuint;
  w, h, w2, h2: Integer;
  sx, sy: Single;
begin
  textureID := FindTexture(AText, w, h, w2, h2);
  sx := w / w2;
  sy := h / h2;
  glEnable(GL_TEXTURE_2D);
  glBindTexture(GL_TEXTURE_2D, textureID);
  glBegin(GL_QUADS);
    glTexCoord2f(0.0, sy);  glVertex2f(0, h);
    glTexCoord2f(sx, sy);   glVertex2f(w, h);
    glTexCoord2f(sx, 0.0);  glVertex2f(w, 0);
    glTexCoord2f(0.0, 0.0); glVertex2f(0, 0);
  glEnd();
  glDisable(GL_TEXTURE_2D);
end;

procedure TGLChartTextHelper.SetFont(const AFontName: String;
  AFontSize: Integer; AStyle: TFontStyles);
begin
  FBmp.Canvas.Font.Name := AFontName;
  FBmp.Canvas.Font.Size := AFontSize;
  FBmp.Canvas.Font.Style := AStyle;
  FBmp.Canvas.Font.Quality := fqAntialiased;
end;

procedure TGLChartTextHelper.TextExtent(const AText: String;
  out AWidth, AHeight: Integer);
var
  sz: TSize;
begin
  sz := FBmp.Canvas.TextExtent(AText);
  AWidth := sz.cx;
  AHeight := sz.cy;
end;

procedure InitFonts(const AFontDir: String);
begin
  // GDI needs no font directory.
end;

procedure DoneFonts;
begin
  ChartGLFreeTextures;
end;

procedure ChartGLFreeTextures;
begin
  if VTextHelper <> nil then
    VTextHelper.FreeTextures;
end;

{ ---------------------------------------------------------------------------
  TOpenGLDrawer
  --------------------------------------------------------------------------- }

function GLGetFontOrientationFunc(AFont: TFPCustomFont): Integer;
begin
  Result := AFont.Orientation;
end;

function GLChartColorToFPColor(AChartColor: TChartColor): TFPColor;
begin
  Result := ChartColorToFPColor(ColorToRGB(AChartColor));
end;

constructor TOpenGLDrawer.Create;
begin
  inherited Create;
  FGetFontOrientationFunc := GLGetFontOrientationFunc;
  FChartColorToFPColorFunc := GLChartColorToFPColor;
  FPenStyle := psSolid;
  FPenWidth := 1;
  FFontName := 'Arial';
  FFontSize := 10;
end;

destructor TOpenGLDrawer.Destroy;
begin
  ChartGLFreeTextures;
  inherited;
end;

procedure TOpenGLDrawer.AddToFontOrientation(ADelta: Integer);
begin
  FFontAngle := FFontAngle + ADelta / ORIENTATION_UNITS_PER_DEG;
end;

procedure TOpenGLDrawer.ChartGLColor(AColor: TFPColor);
begin
  with AColor do
    glColor4us(Red, Green, Blue, (255 - FTransparency) shl 8);
end;

procedure TOpenGLDrawer.ChartGLPenStyle(APenStyle: TFPPenStyle);
var
  pattern: Word;
begin
  case APenStyle of
    psClear      : pattern := $0000;
    psDot        : pattern := $3333; // 0011001100110011
    psDash       : pattern := $00FF; // 0000000011111111
    psDashDot    : pattern := $18FF; // 0001100011111111
    psDashDotDot : pattern := $1B3F; // 0001101100111111
    else begin
      glDisable(GL_LINE_STIPPLE);    // psSolid, psInsideFrame
      exit;
    end;
  end;
  glLineStipple(1, pattern);
  glEnable(GL_LINE_STIPPLE);
end;

procedure TOpenGLDrawer.ClippingStart(const AClipRect: TRect);
type
  TGLClipPlaneEqn = record A, B, C, D: GLdouble; end;
var
  cp: TGLClipPlaneEqn;
begin
  cp := Default(TGLClipPlaneEqn);
  cp.A := 1.0;
  cp.D := -AClipRect.Left;
  glClipPlane(GL_CLIP_PLANE0, @cp);
  cp.A := -1.0;
  cp.D := AClipRect.Right;
  glClipPlane(GL_CLIP_PLANE1, @cp);
  cp.A := 0.0;
  cp.B := 1.0;
  cp.D := -AClipRect.Top;
  glClipPlane(GL_CLIP_PLANE2, @cp);
  cp.B := -1.0;
  cp.D := AClipRect.Bottom;
  glClipPlane(GL_CLIP_PLANE3, @cp);
  ClippingStart;
end;

procedure TOpenGLDrawer.ClippingStart;
begin
  glEnable(GL_CLIP_PLANE0);
  glEnable(GL_CLIP_PLANE1);
  glEnable(GL_CLIP_PLANE2);
  glEnable(GL_CLIP_PLANE3);
end;

procedure TOpenGLDrawer.ClippingStop;
begin
  glDisable(GL_CLIP_PLANE0);
  glDisable(GL_CLIP_PLANE1);
  glDisable(GL_CLIP_PLANE2);
  glDisable(GL_CLIP_PLANE3);
end;

procedure TOpenGLDrawer.Ellipse(AX1, AY1, AX2, AY2: Integer);
var
  p: TPointArray;
begin
  p := TesselateEllipse(Rect(AX1, AY1, AX2, AY2), 4);
  Polygon(p, 0, Length(p));
end;

procedure TOpenGLDrawer.FillRect(AX1, AY1, AX2, AY2: Integer);
begin
  ChartGLColor(FBrushColor);
  glRecti(AX1, AY1, AX2, AY2);
end;

function TOpenGLDrawer.GetBrushColor: TChartColor;
begin
  Result := FPColorToChartColor(FBrushColor);
end;

function TOpenGLDrawer.GetFontAngle: Double;
begin
  Result := 0.0;
end;

procedure TOpenGLDrawer.InternalPolyline(
  const APoints: array of TPoint; AStartIndex, ANumPts, AMode: Integer);
var
  i: Integer;
begin
  if FPenStyle = psClear then exit;
  ChartGLColor(FPenColor);
  glBegin(AMode);
  for i := AStartIndex to AStartIndex + ANumPts - 1 do
    glVertex2iv(@APoints[i]);
  glEnd();
end;

procedure TOpenGLDrawer.Line(AX1, AY1, AX2, AY2: Integer);
begin
  if FPenStyle = psClear then exit;
  glBegin(GL_LINES);
  ChartGLColor(FPenColor);
  glVertex2i(AX1, AY1);
  glVertex2i(AX2, AY2);
  glEnd();
end;

procedure TOpenGLDrawer.Line(const AP1, AP2: TPoint);
begin
  Line(AP1.X, AP1.Y, AP2.X, AP2.Y);
end;

procedure TOpenGLDrawer.LineTo(AX, AY: Integer);
begin
  Line(FPos.X, FPos.Y, AX, AY);
  FPos := Point(AX, AY);
end;

procedure TOpenGLDrawer.MoveTo(AX, AY: Integer);
begin
  FPos := Point(AX, AY);
end;

procedure TOpenGLDrawer.Polygon(
  const APoints: array of TPoint; AStartIndex, ANumPts: Integer);
var
  i: Integer;
begin
  glBegin(GL_POLYGON);
  ChartGLColor(FBrushColor);
  for i := AStartIndex to AStartIndex + ANumPts - 1 do
    glVertex2iv(@APoints[i]);
  glEnd();
  InternalPolyline(APoints, AStartIndex, ANumPts, GL_LINE_LOOP);
end;

procedure TOpenGLDrawer.Polyline(
  const APoints: array of TPoint; AStartIndex, ANumPts: Integer);
begin
  InternalPolyline(APoints, AStartIndex, ANumPts, GL_LINE_STRIP);
end;

procedure TOpenGLDrawer.PrepareSimplePen(AColor: TChartColor);
begin
  FPenWidth := 1;
  FPenColor := FChartColorToFPColorFunc(AColor);
  FPenStyle := psSolid;
  glLineWidth(FPenWidth);
  ChartGLPenStyle(FPenStyle);
end;

procedure TOpenGLDrawer.PutImage(AX, AY: Integer; AImage: TFPCustomImage);
var
  x, y: Integer;
  c: TFPColor;
begin
  // Rarely used; draw the pixels directly.
  glBegin(GL_POINTS);
  for y := 0 to AImage.Height - 1 do
    for x := 0 to AImage.Width - 1 do begin
      c := AImage[x, y];
      if c.Alpha > 0 then begin
        glColor4us(c.Red, c.Green, c.Blue, c.Alpha);
        glVertex2i(AX + x, AY + y);
      end;
    end;
  glEnd();
end;

procedure TOpenGLDrawer.PutPixel(AX, AY: Integer; AColor: TChartColor);
begin
  ChartGLColor(FChartColorToFPColorFunc(AColor));
  glBegin(GL_POINTS);
  glVertex2i(AX, AY);
  glEnd;
end;

procedure TOpenGLDrawer.RadialPie(
  AX1, AY1, AX2, AY2: Integer; AStartAngle16Deg, AAngleLength16Deg: Integer);
var
  e: TEllipse;
  p: TPointArray;
begin
  e.InitBoundingBox(AX1, AY1, AX2, AY2);
  p := e.TesselateRadialPie(
    Deg16ToRad(AStartAngle16Deg), Deg16ToRad(AAngleLength16Deg), 4);
  Polygon(p, 0, Length(p));
end;

procedure TOpenGLDrawer.Rectangle(AX1, AY1, AX2, AY2: Integer);
begin
  ChartGLColor(FBrushColor);
  glRecti(AX1, AY1, AX2, AY2);
  if FPenStyle = psClear then exit;
  ChartGLColor(FPenColor);
  glBegin(GL_LINE_LOOP);
  glVertex2i(AX1, AY1);
  glVertex2i(AX2, AY1);
  glVertex2i(AX2, AY2);
  glVertex2i(AX1, AY2);
  glEnd();
end;

procedure TOpenGLDrawer.Rectangle(const ARect: TRect);
begin
  Rectangle(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);
end;

procedure TOpenGLDrawer.ResetFont;
begin
  FFontAngle := 0;
end;

procedure TOpenGLDrawer.SetAntialiasingMode(AValue: TChartAntialiasingMode);
begin
  case AValue of
    amOn: begin
      glEnable(GL_LINE_SMOOTH);
      glEnable(GL_POLYGON_SMOOTH);
    end;
    amOff: begin
      glDisable(GL_LINE_SMOOTH);
      glDisable(GL_POLYGON_SMOOTH);
    end;
  end;
end;

procedure TOpenGLDrawer.SetBrush(ABrush: TFPCustomBrush);
begin
  FBrushColor := FChartColorToFPColorFunc(ColorOrMono(ABrush.Color));
end;

procedure TOpenGLDrawer.SetBrushColor(AColor: TChartColor);
begin
  FBrushColor := FChartColorToFPColorFunc(ColorOrMono(AColor));
end;

procedure TOpenGLDrawer.SetBrushParams(
  AStyle: TFPBrushStyle; AColor: TChartColor);
begin
  SetBrushColor(AColor);
  Unused(AStyle);
end;

procedure TOpenGLDrawer.SetFont(AFont: TFPCustomFont);
begin
  FFontName := AFont.Name;
  if SameText(FFontName, 'default') then
    FFontName := 'Arial';
  FFontSize := IfThen(AFont.Size = 0, 10, AFont.Size);
  FFontStyle := AFont.Style;
  if FMonochromeColor <> clTAColor then
    FFontColor := FChartColorToFPColorFunc(FMonochromeColor)
  else
    FFontColor := FChartColorToFPColorFunc(ColorToRGB(AFont.Color));
  FFontAngle := FGetFontOrientationFunc(AFont) / ORIENTATION_UNITS_PER_DEG;
  TextHelper.SetFont(FFontName, FFontSize, FFontStyle);
end;

procedure TOpenGLDrawer.SetPen(APen: TFPCustomPen);
begin
  FPenWidth := APen.Width;
  FPenColor := FChartColorToFPColorFunc(ColorOrMono(APen.Color));
  FPenStyle := APen.Style;
  glLineWidth(FPenWidth);
  ChartGLPenStyle(FPenStyle);
end;

procedure TOpenGLDrawer.SetPenParams(AStyle: TFPPenStyle; AColor: TChartColor);
begin
  FPenStyle := AStyle;
  FPenColor := FChartColorToFPColorFunc(ColorOrMono(AColor));
  ChartGLPenStyle(AStyle);
end;

procedure TOpenGLDrawer.SetTransparency(ATransparency: TChartTransparency);
begin
  inherited;
  if FTransparency > 0 then begin
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  end
  else
    glDisable(GL_BLEND);
end;

function TOpenGLDrawer.SimpleTextExtent(const AText: String): TPoint;
begin
  TextHelper.TextExtent(AText, Result.X, Result.Y);
end;

procedure TOpenGLDrawer.SimpleTextOut(AX, AY: Integer; const AText: String);
begin
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  ChartGLColor(FFontColor);
  glMatrixMode(GL_MODELVIEW);
  glPushMatrix;
  glTranslatef(AX, AY, 0);
  glRotatef(-FFontAngle, 0, 0, 1);
  TextHelper.RenderText(AText);
  glPopMatrix;
  if FTransparency = 0 then
    glDisable(GL_BLEND);
end;

initialization

finalization
  FreeAndNil(VTextHelper);

end.
