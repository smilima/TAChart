{
 *****************************************************************************
  This file is part of the Delphi/VCL port of TAChart.

  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  Ported from the TGraph component (Source\TG.GLContext.pas), where this code was
  written and proven.  Types carry TAChart's TChart... prefix so one project
  can use both components without a name clash.
}

unit TAGLContext;

{$I TAChartDefines.inc}

{ TAChart — OpenGL plumbing.

  TChartGLContext wraps a classic wgl rendering context bound to a VCL control's
  window handle, sets up a 2D pixel-space projection and provides bitmap-font
  text output (wglUseFontBitmaps).

  Fonts are cached per (face, size, style, charset), so every chart element —
  title, axis labels, legend, series labels — can render with its own TFont
  rather than sharing one.

  Rotated text (the left axis title) takes a different route: the string is
  rasterised horizontally by GDI into a DIB, uploaded as a luminance+alpha
  texture and drawn on a rotated quad. Rotating the quad rather than the font
  avoids wglUseFontBitmaps, which does not reliably produce glyph bitmaps for
  escapement-rotated fonts.

  TChartGLRenderContext is the small record handed to every series when it is
  asked to draw itself: the GL context, the plot rectangle, the current axis
  ranges and the font to use for point labels, plus data->pixel helpers. }

interface

uses
  Winapi.Windows, Winapi.OpenGL, System.SysUtils, System.Classes, System.Types,
  System.UITypes, System.Generics.Collections, Vcl.Graphics;

type
  EChartGLError = class(Exception);

  TChartGLColor = record
    R, G, B, A: Single;
  end;

  { Vertex-buffer entry points. These are OpenGL 1.5, so Winapi.OpenGL (which
    stops at 1.1) does not declare them and they must be resolved through
    wglGetProcAddress against the current context. }
  TglGenBuffersProc = procedure(n: Integer; buffers: PCardinal); stdcall;
  TglBindBufferProc = procedure(target: Cardinal; buffer: Cardinal); stdcall;
  TglBufferDataProc = procedure(target: Cardinal; size: NativeInt;
    data: Pointer; usage: Cardinal); stdcall;
  TglBufferSubDataProc = procedure(target: Cardinal; offset, size: NativeInt;
    data: Pointer); stdcall;
  TglDeleteBuffersProc = procedure(n: Integer; buffers: PCardinal); stdcall;

  { WGL_EXT_swap_control.  Not part of OpenGL proper, so like the buffer
    entry points these are resolved against the live context. }
  TwglSwapIntervalEXTProc = function(interval: Integer): BOOL; stdcall;
  TwglGetSwapIntervalEXTProc = function: Integer; stdcall;

  { Display lists plus metrics for one cached font. }
  TChartGLFontData = class
  public
    Base: Cardinal;
    Height: Integer;
    Ascent: Integer;
    Widths: array[0..255] of Integer;
    function TextWidth(const S: string): Integer;
  end;

  { One string rasterised by GDI and uploaded as a texture. Used for rotated
    text: the glyphs are drawn horizontally and the quad is rotated, which
    is far more reliable than asking wglUseFontBitmaps for a rotated font. }
  TChartGLTextTexture = class
  public
    TexId: Cardinal;
    Width: Integer;
    Height: Integer;
    destructor Destroy; override;
  end;

  TChartGLContext = class
  private
    FWindow: HWND;
    FDC: HDC;
    FRC: HGLRC;
    FFonts: TObjectDictionary<string, TChartGLFontData>;
    FTextTextures: TObjectDictionary<string, TChartGLTextTexture>;
    FRenderer: string;
    FVersion: string;
    FVendor: string;
    FInfoRead: Boolean;
    FContextId: Cardinal;
    FVBOChecked: Boolean;
    FHasVBO: Boolean;
    FGenBuffers: TglGenBuffersProc;
    FBindBuffer: TglBindBufferProc;
    FBufferData: TglBufferDataProc;
    FBufferSubData: TglBufferSubDataProc;
    FDeleteBuffers: TglDeleteBuffersProc;
    FSwapControlChecked: Boolean;
    FSwapIntervalProc: TwglSwapIntervalEXTProc;
    FGetSwapIntervalProc: TwglGetSwapIntervalEXTProc;
    procedure LoadVBOEntryPoints;
    procedure LoadSwapControlEntryPoints;
    function GetHasVBO: Boolean;
    function GetHasSwapControl: Boolean;
    function GetSwapInterval: Integer;
    procedure SetSwapInterval(AValue: Integer);
    function FontKey(AFont: TFont): string;
    function AcquireFont(AFont: TFont): TChartGLFontData;
    function AcquireTextTexture(AFont: TFont; const S: string): TChartGLTextTexture;
    procedure ReadInfo;
    function GetRenderer: string;
    function GetVersion: string;
    function GetVendor: string;
  public
    { Creates a double-buffered RGBA context on the given window.
      Raises EChartGLError if any step fails. }
    constructor Create(AWindow: HWND);
    destructor Destroy; override;

    function MakeCurrent: Boolean;
    procedure EndCurrent;
    procedure Swap;

    { Viewport + orthographic projection in pixel space: origin at the
      top-left corner, one unit = one pixel. Also enables alpha blending
      and line smoothing — the baseline state every frame starts from. }
    procedure Setup2D(AWidth, AHeight: Integer);

    { Discards every cached font. Call when the context is rebuilt. }
    procedure ClearFonts;

    { Horizontal text with its baseline starting at X,Y (pixel coordinates). }
    procedure TextOut(const X, Y: Single; const S: string; AFont: TFont);
    { Text rotated 90 degrees counter-clockwise, reading bottom-to-top.
      X,Y is the baseline start (the bottom of the resulting column). }
    procedure TextOutVertical(const X, Y: Single; const S: string; AFont: TFont);

    { Metrics taken from the cached GL font, so measurement always matches
      what TextOut actually draws. }
    function TextWidth(AFont: TFont; const S: string): Integer;
    function TextHeight(AFont: TFont): Integer;

    procedure SetColor(AColor: TColor; const AAlpha: Single = 1.0);

    { ---- Vertex buffer objects ----
      Uploading vertex data to the GPU once and redrawing from there, instead
      of pushing a client-side array across the bus every frame. Callers must
      check HasVBO first and fall back to client arrays when it is False. }
    function CreateArrayBuffer: Cardinal;
    procedure DeleteArrayBuffer(var ABuffer: Cardinal);
    procedure BindArrayBuffer(ABuffer: Cardinal);
    { Allocates/replaces the whole buffer. AData may be nil to allocate only. }
    procedure ArrayBufferData(ASize: NativeInt; AData: Pointer;
      ADynamic: Boolean);
    { Replaces a sub-range without reallocating — used for partial updates. }
    procedure ArrayBufferSubData(AOffset, ASize: NativeInt; AData: Pointer);
    property HasVBO: Boolean read GetHasVBO;

    { ---- Swap control and timing ----
      By default SwapBuffers waits for the display to refresh, which is what
      an interactive chart wants but makes it useless to time: once drawing
      is quicker than the refresh, every frame measures the wait instead.

      Setting SwapInterval to 0 turns that off, and Finish blocks until the
      GPU has actually finished the work rather than merely accepted it, so
      the two together let a caller measure what drawing really costs.  Put
      SwapInterval back to 1 afterwards - leaving it at 0 spins the GPU
      redrawing frames nobody sees. }
    property HasSwapControl: Boolean read GetHasSwapControl;
    property SwapInterval: Integer read GetSwapInterval write SetSwapInterval;
    { Blocks until every command issued so far has completed. }
    procedure Finish;

    property DC: HDC read FDC;
    property RC: HGLRC read FRC;
    { Unique per instance for the life of the process. Resources such as
      vertex buffers belong to one context; comparing this rather than the
      object pointer avoids being fooled when a freed context's address is
      reused by its replacement. }
    property ContextId: Cardinal read FContextId;
    { Driver strings, e.g. 'NVIDIA GeForce RTX 4070' / '4.6.0'. Only valid
      while the context is current. }
    property Renderer: string read GetRenderer;
    property Version: string read GetVersion;
    property Vendor: string read GetVendor;
  end;

  TChartGLRenderContext = record
    GL: TChartGLContext;
    ChartRect: TRect;      // plot area in pixels
    XMin, XMax: Double;    // horizontal axis range
    YMin, YMax: Double;    // vertical axis range
    LabelFont: TFont;      // font series should use for point labels
    ViewportHeight: Integer;  // control height; glScissor counts from the bottom
    function MapX(const AValue: Double): Single;  // data X -> pixel X
    function MapY(const AValue: Double): Single;  // data Y -> pixel Y
  end;

function ChartColorToGL(AColor: TColor; const AAlpha: Single = 1.0): TChartGLColor;

implementation

uses
  System.Math;

const
  // Not declared by Winapi.OpenGL, which only covers OpenGL 1.1.
  GL_CLAMP_TO_EDGE_EXT = $812F;
  GL_ARRAY_BUFFER_ARB = $8892;
  GL_STATIC_DRAW_ARB = $88E4;
  GL_DYNAMIC_DRAW_ARB = $88E8;

var
  { Source of TChartGLContext.ContextId. Contexts are only created on the VCL
    main thread, so a plain counter is sufficient. }
  VChartGLContextSerial: Cardinal = 0;

{ TChartGLTextTexture }

//------------------------------------------------------------------------------
destructor TChartGLTextTexture.Destroy;
begin
  if TexId <> 0 then
    glDeleteTextures(1, @TexId);
  inherited;
end;

//------------------------------------------------------------------------------
function ChartColorToGL(AColor: TColor; const AAlpha: Single): TChartGLColor;
var
  RGBValue: Longint;
begin
  RGBValue := ColorToRGB(AColor);
  Result.R := GetRValue(RGBValue) / 255;
  Result.G := GetGValue(RGBValue) / 255;
  Result.B := GetBValue(RGBValue) / 255;
  Result.A := AAlpha;
end;

{ TChartGLFontData }

//------------------------------------------------------------------------------
function TChartGLFontData.TextWidth(const S: string): Integer;
var
  I, C: Integer;
begin
  Result := 0;
  for I := 1 to Length(S) do
  begin
    C := Ord(S[I]);
    if C > 255 then
      C := Ord('?');
    Inc(Result, Widths[C]);
  end;
end;

{ TChartGLContext }

//------------------------------------------------------------------------------
constructor TChartGLContext.Create(AWindow: HWND);
var
  PFD: TPixelFormatDescriptor;
  PixelFormat: Integer;
begin
  inherited Create;
  Inc(VChartGLContextSerial);
  FContextId := VChartGLContextSerial;
  FWindow := AWindow;
  FFonts := TObjectDictionary<string, TChartGLFontData>.Create([doOwnsValues]);
  FTextTextures := TObjectDictionary<string, TChartGLTextTexture>.Create([doOwnsValues]);
  FDC := GetDC(AWindow);
  if FDC = 0 then
    raise EChartGLError.Create('TAChart: unable to obtain a device context');

  FillChar(PFD, SizeOf(PFD), 0);
  PFD.nSize := SizeOf(PFD);
  PFD.nVersion := 1;
  PFD.dwFlags := PFD_DRAW_TO_WINDOW or PFD_SUPPORT_OPENGL or PFD_DOUBLEBUFFER;
  PFD.iPixelType := PFD_TYPE_RGBA;
  PFD.cColorBits := 24;
  PFD.cDepthBits := 16;
  PFD.iLayerType := PFD_MAIN_PLANE;

  PixelFormat := ChoosePixelFormat(FDC, @PFD);
  if PixelFormat = 0 then
    raise EChartGLError.Create('TAChart: no suitable OpenGL pixel format');
  if not SetPixelFormat(FDC, PixelFormat, @PFD) then
    raise EChartGLError.Create('TAChart: SetPixelFormat failed');

  FRC := wglCreateContext(FDC);
  if FRC = 0 then
    raise EChartGLError.Create('TAChart: wglCreateContext failed');
end;

//------------------------------------------------------------------------------
destructor TChartGLContext.Destroy;
begin
  if FRC <> 0 then
  begin
    if wglMakeCurrent(FDC, FRC) then
      ClearFonts;
    wglMakeCurrent(0, 0);
    wglDeleteContext(FRC);
    FRC := 0;
  end;
  FFonts.Free;
  FTextTextures.Free;
  if FDC <> 0 then
  begin
    ReleaseDC(FWindow, FDC);
    FDC := 0;
  end;
  inherited;
end;

//------------------------------------------------------------------------------
procedure TChartGLContext.ClearFonts;
var
  Data: TChartGLFontData;
begin
  for Data in FFonts.Values do
    if Data.Base <> 0 then
      glDeleteLists(Data.Base, 256);
  FFonts.Clear;
  // TChartGLTextTexture.Destroy releases each texture name; both caches are only
  // valid for the context that created them.
  FTextTextures.Clear;
end;

//------------------------------------------------------------------------------
function TChartGLContext.MakeCurrent: Boolean;
begin
  Result := (FRC <> 0) and wglMakeCurrent(FDC, FRC);
end;

//------------------------------------------------------------------------------
procedure TChartGLContext.EndCurrent;
begin
  wglMakeCurrent(0, 0);
end;

//------------------------------------------------------------------------------
procedure TChartGLContext.Swap;
begin
  SwapBuffers(FDC);
end;

//------------------------------------------------------------------------------
procedure TChartGLContext.Setup2D(AWidth, AHeight: Integer);
begin
  if AWidth < 1 then AWidth := 1;
  if AHeight < 1 then AHeight := 1;
  glViewport(0, 0, AWidth, AHeight);
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  glOrtho(0, AWidth, AHeight, 0, -1, 1);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;
  glDisable(GL_DEPTH_TEST);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glEnable(GL_LINE_SMOOTH);
  glHint(GL_LINE_SMOOTH_HINT, GL_NICEST);
end;

//------------------------------------------------------------------------------
procedure TChartGLContext.ReadInfo;
var
  P: MarshaledAString;
  PrevDC: HDC;
  PrevRC: HGLRC;
  Switched: Boolean;
begin
  if FInfoRead then
    Exit;

  { glGetString only answers for the *current* context, and returns nil
    otherwise. Making this context current here rather than trusting the
    caller to have done it is what stops the strings being cached empty -
    which is what happened when the first query came from a window that had
    not painted yet. }
  PrevDC := wglGetCurrentDC;
  PrevRC := wglGetCurrentContext;
  Switched := (PrevRC <> FRC) and MakeCurrent;
  try
    P := MarshaledAString(glGetString(GL_RENDERER));
    if P <> nil then
      FRenderer := string(AnsiString(P));
    P := MarshaledAString(glGetString(GL_VERSION));
    if P <> nil then
      FVersion := string(AnsiString(P));
    P := MarshaledAString(glGetString(GL_VENDOR));
    if P <> nil then
      FVendor := string(AnsiString(P));
    { Only remember the answer once there is one, so a query made too early
      does not poison the cache for the life of the context. }
    FInfoRead := (FRenderer <> '') or (FVersion <> '') or (FVendor <> '');
  finally
    if Switched and (PrevRC <> 0) then
      wglMakeCurrent(PrevDC, PrevRC);
  end;
end;

//------------------------------------------------------------------------------
function TChartGLContext.GetRenderer: string;
begin
  ReadInfo;
  Result := FRenderer;
end;

//------------------------------------------------------------------------------
function TChartGLContext.GetVersion: string;
begin
  ReadInfo;
  Result := FVersion;
end;

//------------------------------------------------------------------------------
function TChartGLContext.GetVendor: string;
begin
  ReadInfo;
  Result := FVendor;
end;

//------------------------------------------------------------------------------
procedure TChartGLContext.LoadVBOEntryPoints;
begin
  if FVBOChecked then
    Exit;
  FVBOChecked := True;
  // wglGetProcAddress only returns valid pointers while a context is current.
  @FGenBuffers := wglGetProcAddress('glGenBuffers');
  @FBindBuffer := wglGetProcAddress('glBindBuffer');
  @FBufferData := wglGetProcAddress('glBufferData');
  @FBufferSubData := wglGetProcAddress('glBufferSubData');
  @FDeleteBuffers := wglGetProcAddress('glDeleteBuffers');
  if not Assigned(FGenBuffers) then
  begin
    // Older drivers may only expose the ARB-suffixed names.
    @FGenBuffers := wglGetProcAddress('glGenBuffersARB');
    @FBindBuffer := wglGetProcAddress('glBindBufferARB');
    @FBufferData := wglGetProcAddress('glBufferDataARB');
    @FBufferSubData := wglGetProcAddress('glBufferSubDataARB');
    @FDeleteBuffers := wglGetProcAddress('glDeleteBuffersARB');
  end;
  FHasVBO := Assigned(FGenBuffers) and Assigned(FBindBuffer) and
    Assigned(FBufferData) and Assigned(FBufferSubData) and
    Assigned(FDeleteBuffers);
end;

//------------------------------------------------------------------------------
procedure TChartGLContext.LoadSwapControlEntryPoints;
begin
  if FSwapControlChecked then
    Exit;
  FSwapControlChecked := True;
  { wglGetProcAddress only answers for the current context. }
  if wglGetCurrentContext <> FRC then
    if not MakeCurrent then
      Exit;
  FSwapIntervalProc := TwglSwapIntervalEXTProc(
    wglGetProcAddress('wglSwapIntervalEXT'));
  FGetSwapIntervalProc := TwglGetSwapIntervalEXTProc(
    wglGetProcAddress('wglGetSwapIntervalEXT'));
end;

//------------------------------------------------------------------------------
function TChartGLContext.GetHasSwapControl: Boolean;
begin
  LoadSwapControlEntryPoints;
  Result := Assigned(FSwapIntervalProc);
end;

//------------------------------------------------------------------------------
function TChartGLContext.GetSwapInterval: Integer;
begin
  LoadSwapControlEntryPoints;
  if Assigned(FGetSwapIntervalProc) then
    Result := FGetSwapIntervalProc
  else
    Result := -1;    // unknown: the driver does not expose the extension
end;

//------------------------------------------------------------------------------
procedure TChartGLContext.SetSwapInterval(AValue: Integer);
begin
  LoadSwapControlEntryPoints;
  if Assigned(FSwapIntervalProc) then
    FSwapIntervalProc(AValue);
end;

//------------------------------------------------------------------------------
procedure TChartGLContext.Finish;
begin
  if wglGetCurrentContext <> FRC then
    if not MakeCurrent then
      Exit;
  glFinish;
end;

//------------------------------------------------------------------------------
function TChartGLContext.GetHasVBO: Boolean;
begin
  LoadVBOEntryPoints;
  Result := FHasVBO;
end;

//------------------------------------------------------------------------------
function TChartGLContext.CreateArrayBuffer: Cardinal;
begin
  Result := 0;
  if GetHasVBO then
    FGenBuffers(1, @Result);
end;

//------------------------------------------------------------------------------
procedure TChartGLContext.DeleteArrayBuffer(var ABuffer: Cardinal);
begin
  if (ABuffer <> 0) and GetHasVBO then
    FDeleteBuffers(1, @ABuffer);
  ABuffer := 0;
end;

//------------------------------------------------------------------------------
procedure TChartGLContext.BindArrayBuffer(ABuffer: Cardinal);
begin
  if GetHasVBO then
    FBindBuffer(GL_ARRAY_BUFFER_ARB, ABuffer);
end;

//------------------------------------------------------------------------------
procedure TChartGLContext.ArrayBufferData(ASize: NativeInt; AData: Pointer;
  ADynamic: Boolean);
const
  Usage: array[Boolean] of Cardinal = (GL_STATIC_DRAW_ARB, GL_DYNAMIC_DRAW_ARB);
begin
  if GetHasVBO then
    FBufferData(GL_ARRAY_BUFFER_ARB, ASize, AData, Usage[ADynamic]);
end;

//------------------------------------------------------------------------------
procedure TChartGLContext.ArrayBufferSubData(AOffset, ASize: NativeInt;
  AData: Pointer);
begin
  if GetHasVBO then
    FBufferSubData(GL_ARRAY_BUFFER_ARB, AOffset, ASize, AData);
end;

//------------------------------------------------------------------------------
function TChartGLContext.FontKey(AFont: TFont): string;
begin
  Result := Format('%s|%d|%d|%d', [AFont.Name, AFont.Height,
    Byte(AFont.Style), Ord(AFont.Charset)]);
end;

//------------------------------------------------------------------------------
function TChartGLContext.AcquireFont(AFont: TFont): TChartGLFontData;
var
  Key: string;
  OldFont: HFONT;
  Metrics: TTextMetric;
  Data: TChartGLFontData;
begin
  Result := nil;
  if AFont = nil then
    Exit;
  Key := FontKey(AFont);
  if FFonts.TryGetValue(Key, Result) then
    Exit;

  Data := TChartGLFontData.Create;
  OldFont := SelectObject(FDC, AFont.Handle);
  try
    Data.Base := glGenLists(256);
    if (Data.Base = 0) or (not wglUseFontBitmaps(FDC, 0, 256, Data.Base)) then
    begin
      if Data.Base <> 0 then
        glDeleteLists(Data.Base, 256);
      Data.Free;
      Exit;
    end;
    GetTextMetrics(FDC, Metrics);
    Data.Height := Metrics.tmHeight;
    Data.Ascent := Metrics.tmAscent;
    GetCharWidth32(FDC, 0, 255, Data.Widths[0]);
  finally
    SelectObject(FDC, OldFont);
  end;

  FFonts.Add(Key, Data);
  Result := Data;
end;

//------------------------------------------------------------------------------
{ Rasterises S with GDI into a top-down 32-bit DIB and uploads it as a
  luminance+alpha texture: luminance is forced to white so glColor tints the
  text, alpha carries the glyph coverage (and therefore GDI's anti-aliasing). }
function TChartGLContext.AcquireTextTexture(AFont: TFont;
  const S: string): TChartGLTextTexture;
var
  Key: string;
  MemDC: HDC;
  Info: TBitmapInfo;
  Bits: Pointer;
  Bmp, OldBmp: HBITMAP;
  OldFont: HFONT;
  Extent: TSize;
  W, H, I: Integer;
  Src: PCardinal;
  Pixel: Cardinal;
  Buf: TArray<Byte>;
  Data: TChartGLTextTexture;
begin
  Result := nil;
  if (AFont = nil) or (S = '') then
    Exit;
  Key := FontKey(AFont) + '|' + S;
  if FTextTextures.TryGetValue(Key, Result) then
    Exit;

  MemDC := CreateCompatibleDC(FDC);
  if MemDC = 0 then
    Exit;
  try
    OldFont := SelectObject(MemDC, AFont.Handle);
    try
      if not GetTextExtentPoint32(MemDC, PChar(S), Length(S), Extent) then
        Exit;
      W := Extent.cx;
      H := Extent.cy;
      if (W <= 0) or (H <= 0) then
        Exit;

      FillChar(Info, SizeOf(Info), 0);
      Info.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
      Info.bmiHeader.biWidth := W;
      Info.bmiHeader.biHeight := -H;   // negative => top-down rows
      Info.bmiHeader.biPlanes := 1;
      Info.bmiHeader.biBitCount := 32;
      Info.bmiHeader.biCompression := BI_RGB;
      Bmp := CreateDIBSection(MemDC, Info, DIB_RGB_COLORS, Bits, 0, 0);
      if (Bmp = 0) or (Bits = nil) then
        Exit;
      try
        OldBmp := SelectObject(MemDC, Bmp);
        try
          SetBkMode(MemDC, OPAQUE);
          SetBkColor(MemDC, RGB(0, 0, 0));
          SetTextColor(MemDC, RGB(255, 255, 255));
          Winapi.Windows.TextOut(MemDC, 0, 0, PChar(S), Length(S));
          GdiFlush;

          SetLength(Buf, W * H * 2);
          Src := Bits;
          for I := 0 to W * H - 1 do
          begin
            Pixel := Src^;
            Buf[I * 2] := 255;                      // luminance
            Buf[I * 2 + 1] := Byte(Pixel and $FF);  // alpha from coverage
            Inc(Src);
          end;
        finally
          SelectObject(MemDC, OldBmp);
        end;
      finally
        DeleteObject(Bmp);
      end;
    finally
      SelectObject(MemDC, OldFont);
    end;
  finally
    DeleteDC(MemDC);
  end;

  Data := TChartGLTextTexture.Create;
  Data.Width := W;
  Data.Height := H;
  glGenTextures(1, @Data.TexId);
  if Data.TexId = 0 then
  begin
    Data.Free;
    Exit;
  end;
  glBindTexture(GL_TEXTURE_2D, Data.TexId);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE_EXT);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE_EXT);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE_ALPHA, W, H, 0,
    GL_LUMINANCE_ALPHA, GL_UNSIGNED_BYTE, @Buf[0]);
  glBindTexture(GL_TEXTURE_2D, 0);

  FTextTextures.Add(Key, Data);
  Result := Data;
end;

//------------------------------------------------------------------------------
procedure TChartGLContext.TextOut(const X, Y: Single; const S: string; AFont: TFont);
var
  Data: TChartGLFontData;
  Bytes: AnsiString;
begin
  if S = '' then
    Exit;
  Data := AcquireFont(AFont);
  if Data = nil then
    Exit;
  Bytes := AnsiString(S);
  glRasterPos2f(X, Y);
  glPushAttrib(GL_LIST_BIT);
  glListBase(Data.Base);
  glCallLists(Length(Bytes), GL_UNSIGNED_BYTE, PAnsiChar(Bytes));
  glPopAttrib;
end;

//------------------------------------------------------------------------------
procedure TChartGLContext.TextOutVertical(const X, Y: Single; const S: string;
  AFont: TFont);
var
  Tex: TChartGLTextTexture;
  W, H: Single;
begin
  Tex := AcquireTextTexture(AFont, S);
  if Tex = nil then
    Exit;
  W := Tex.Width;
  H := Tex.Height;
  // The glyphs were rasterised horizontally; rotating the quad 90 degrees
  // counter-clockwise makes the text read bottom-to-top from (X, Y).
  glEnable(GL_TEXTURE_2D);
  glBindTexture(GL_TEXTURE_2D, Tex.TexId);
  glBegin(GL_QUADS);
  glTexCoord2f(0, 0); glVertex2f(X, Y);
  glTexCoord2f(1, 0); glVertex2f(X, Y - W);
  glTexCoord2f(1, 1); glVertex2f(X + H, Y - W);
  glTexCoord2f(0, 1); glVertex2f(X + H, Y);
  glEnd;
  glBindTexture(GL_TEXTURE_2D, 0);
  glDisable(GL_TEXTURE_2D);
end;

//------------------------------------------------------------------------------
function TChartGLContext.TextWidth(AFont: TFont; const S: string): Integer;
var
  Data: TChartGLFontData;
begin
  Data := AcquireFont(AFont);
  if Data = nil then
    Result := 0
  else
    Result := Data.TextWidth(S);
end;

//------------------------------------------------------------------------------
function TChartGLContext.TextHeight(AFont: TFont): Integer;
var
  Data: TChartGLFontData;
begin
  Data := AcquireFont(AFont);
  if Data = nil then
    Result := 0
  else
    Result := Data.Height;
end;

//------------------------------------------------------------------------------
procedure TChartGLContext.SetColor(AColor: TColor; const AAlpha: Single);
var
  C: TChartGLColor;
begin
  C := ChartColorToGL(AColor, AAlpha);
  glColor4f(C.R, C.G, C.B, C.A);
end;

{ TChartGLRenderContext }

//------------------------------------------------------------------------------
function TChartGLRenderContext.MapX(const AValue: Double): Single;
begin
  if XMax = XMin then
    Result := ChartRect.Left + ChartRect.Width * 0.5
  else
    Result := ChartRect.Left +
      (AValue - XMin) / (XMax - XMin) * ChartRect.Width;
end;

//------------------------------------------------------------------------------
function TChartGLRenderContext.MapY(const AValue: Double): Single;
begin
  if YMax = YMin then
    Result := ChartRect.Top + ChartRect.Height * 0.5
  else
    Result := ChartRect.Bottom -
      (AValue - YMin) / (YMax - YMin) * ChartRect.Height;
end;

end.
