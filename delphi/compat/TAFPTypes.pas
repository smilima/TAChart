{
 *****************************************************************************
  This file is part of the Delphi/VCL port of TAChart.

  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  Compatibility layer replacing the Free Pascal FPCanvas / FPImage units that
  the original Lazarus code depends on.

  Rationale
  ---------
  In the LCL, TPen/TBrush/TFont descend from TFPCanvasHelper (unit FPCanvas)
  and colours are exchanged as TFPColor (unit FPImage, 16 bit per channel).
  Delphi's VCL has an equivalent hierarchy rooted at TGraphicsObject, so most
  of the port is a set of type aliases.  Only the 16-bit colour record and the
  raw image classes have no VCL counterpart and are implemented here.

  The image classes deliberately keep the names used upstream (TLazIntfImage,
  TRawImage, CreateLazIntfImage) so that the ported series units stay close to
  their Lazarus originals and remain easy to diff against upstream.
}

unit TAFPTypes;

{$I TAChartDefines.inc}

interface

uses
  Winapi.Windows, System.Classes, System.SysUtils, Vcl.Graphics;

type
  // The VCL equivalents of the FPCanvas base classes.  TAChart only ever uses
  // these as the static types of properties and parameters; every instance it
  // creates is a real VCL TPen/TBrush/TFont.
  TFPCanvasHelper = Vcl.Graphics.TGraphicsObject;
  TFPCustomPen    = Vcl.Graphics.TPen;
  TFPCustomBrush  = Vcl.Graphics.TBrush;
  TFPCustomFont   = Vcl.Graphics.TFont;
  TFPPenStyle     = Vcl.Graphics.TPenStyle;
  TFPBrushStyle   = Vcl.Graphics.TBrushStyle;

const
  alphaTransparent = $0000;
  alphaOpaque      = $FFFF;

type
  { TFPColor -- 16 bit per channel colour, the interchange format used by the
    IChartDrawer interface so that drawing back-ends with more than 8 bits of
    colour resolution (SVG, OpenGL, ...) do not lose precision. }
  TFPColor = record
    Red, Green, Blue, Alpha: Word;
  end;
  PFPColor = ^TFPColor;

  { TFPCustomImage -- minimal stand-in for the FCL image base class.  Only the
    members TAChart actually touches are provided: the dimensions and indexed
    access to pixels. }
  TFPCustomImage = class(TPersistent)
  strict private
    FWidth: Integer;
    FHeight: Integer;
  strict protected
    function GetColor(X, Y: Integer): TFPColor; virtual; abstract;
    procedure SetColor(X, Y: Integer; const AValue: TFPColor); virtual; abstract;
    procedure SetSize(AWidth, AHeight: Integer); virtual;
  public
    constructor Create(AWidth, AHeight: Integer); virtual;
    property Colors[X, Y: Integer]: TFPColor read GetColor write SetColor; default;
    property Height: Integer read FHeight;
    property Width: Integer read FWidth;
  end;

  { TRawImageDescription -- the handful of fields the chart code reads back
    from a raw image.  The port always uses 32 bit BGRA, top-down. }
  TRawImageDescription = record
    Width: Cardinal;
    Height: Cardinal;
    BitsPerPixel: Word;
    LineOrder: Byte;            // 0 = top-to-bottom
    BytesPerLine: Cardinal;
    procedure Init_BPP32_B8G8R8A8_BIO_TTB(AWidth, AHeight: Integer);
  end;

  { TRawImage -- a flat, top-down, 32 bit BGRA pixel buffer.

    Upstream this is an LCL record whose storage is owned by the caller; here
    the buffer is owned by the TChartIntfImage that produced it, which keeps
    the "out ARawImage" calling convention of CreateLazIntfImage intact. }
  TRawImage = record
    Description: TRawImageDescription;
    Data: PByte;
    DataSize: Cardinal;
    procedure Init;
  end;
  PRawImage = ^TRawImage;

  { TChartIntfImage -- a device independent 32 bit BGRA image.

    The pixel buffer is stored top-down so that the "PCardinal(Data)[Y*W + X]"
    addressing used by TManhattanSeries and TColorMapSeries works unchanged.
    The buffer is premultiplied-alpha safe because the chart code only ever
    writes fully opaque ($FF) or fully transparent ($00) pixels. }
  TChartIntfImage = class(TFPCustomImage)
  strict private
    FData: PCardinal;
    FDataSize: Cardinal;
    function GetPixels(X, Y: Integer): Cardinal; inline;
    procedure SetPixels(X, Y: Integer; AValue: Cardinal); inline;
    function GetTColor(X, Y: Integer): TColor;
    procedure SetTColor(X, Y: Integer; AValue: TColor);
  strict protected
    function GetColor(X, Y: Integer): TFPColor; override;
    procedure SetColor(X, Y: Integer; const AValue: TFPColor); override;
    procedure SetSize(AWidth, AHeight: Integer); override;
  public
    constructor Create(AWidth, AHeight: Integer); override;
    destructor Destroy; override;
    procedure Clear;
    procedure GetRawImage(out ARawImage: TRawImage);
    // Blits the image onto ADC honouring the per-pixel alpha channel.
    procedure DrawTo(ADC: HDC; AX, AY: Integer);
    property Data: PCardinal read FData;
    property DataSize: Cardinal read FDataSize;
    // Raw BGRA access; A is the most significant byte.
    property Pixels[X, Y: Integer]: Cardinal read GetPixels write SetPixels;
    // Access as a VCL TColor, which stores its channels the other way round.
    property TColors[X, Y: Integer]: TColor read GetTColor write SetTColor;
  end;

  // Upstream name, kept so the ported series units need no edit.
  TLazIntfImage = TChartIntfImage;

function FPColor(Ared, Agreen, Ablue: Word; Aalpha: Word = alphaOpaque): TFPColor; inline;
function FPColorsEqual(const A, B: TFPColor): Boolean; inline;

// Converts a VCL TColor ($00BBGGRR) into an opaque TChartIntfImage pixel
// ($AARRGGBB), for the series that write into the raw buffer directly.
function TColorToPixel32(AColor: TColor): Cardinal; inline;

const
  colTransparent: TFPColor = (Red: 0; Green: 0; Blue: 0; Alpha: alphaTransparent);
  colBlack: TFPColor = (Red: 0; Green: 0; Blue: 0; Alpha: alphaOpaque);
  colWhite: TFPColor = (Red: $FFFF; Green: $FFFF; Blue: $FFFF; Alpha: alphaOpaque);

implementation

function FPColor(Ared, Agreen, Ablue: Word; Aalpha: Word): TFPColor;
begin
  Result.Red := Ared;
  Result.Green := Agreen;
  Result.Blue := Ablue;
  Result.Alpha := Aalpha;
end;

function FPColorsEqual(const A, B: TFPColor): Boolean;
begin
  Result := (A.Red = B.Red) and (A.Green = B.Green) and (A.Blue = B.Blue) and
    (A.Alpha = B.Alpha);
end;

function TColorToPixel32(AColor: TColor): Cardinal;
var
  c: Cardinal;
begin
  c := Cardinal(ColorToRGB(AColor));
  Result := $FF000000 or ((c and $FF) shl 16) or (c and $FF00) or
    ((c shr 16) and $FF);
end;

{ TFPCustomImage }

constructor TFPCustomImage.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  SetSize(AWidth, AHeight);
end;

procedure TFPCustomImage.SetSize(AWidth, AHeight: Integer);
begin
  FWidth := AWidth;
  FHeight := AHeight;
end;

{ TRawImageDescription }

procedure TRawImageDescription.Init_BPP32_B8G8R8A8_BIO_TTB(
  AWidth, AHeight: Integer);
begin
  Width := AWidth;
  Height := AHeight;
  BitsPerPixel := 32;
  LineOrder := 0;
  BytesPerLine := Cardinal(AWidth) * 4;
end;

{ TRawImage }

procedure TRawImage.Init;
begin
  Self := Default(TRawImage);
end;

{ TChartIntfImage }

constructor TChartIntfImage.Create(AWidth, AHeight: Integer);
begin
  inherited Create(AWidth, AHeight);
end;

destructor TChartIntfImage.Destroy;
begin
  FreeMem(FData);
  FData := nil;
  inherited;
end;

procedure TChartIntfImage.SetSize(AWidth, AHeight: Integer);
var
  newSize: Cardinal;
begin
  if AWidth < 0 then AWidth := 0;
  if AHeight < 0 then AHeight := 0;
  newSize := Cardinal(AWidth) * Cardinal(AHeight) * 4;
  if newSize <> FDataSize then begin
    ReallocMem(FData, newSize);
    FDataSize := newSize;
  end;
  inherited SetSize(AWidth, AHeight);
  Clear;
end;

procedure TChartIntfImage.Clear;
begin
  if (FData <> nil) and (FDataSize > 0) then
    FillChar(FData^, FDataSize, 0);
end;

function TChartIntfImage.GetPixels(X, Y: Integer): Cardinal;
begin
  Result := PCardinal(PByte(FData) + (Cardinal(Y) * Cardinal(Width) + Cardinal(X)) * 4)^;
end;

procedure TChartIntfImage.SetPixels(X, Y: Integer; AValue: Cardinal);
begin
  PCardinal(PByte(FData) + (Cardinal(Y) * Cardinal(Width) + Cardinal(X)) * 4)^ := AValue;
end;

function TChartIntfImage.GetColor(X, Y: Integer): TFPColor;
var
  c: Cardinal;
begin
  c := GetPixels(X, Y);
  // Stored as BGRA with A in the high byte.
  Result.Blue := (c and $FF) * $101;
  Result.Green := ((c shr 8) and $FF) * $101;
  Result.Red := ((c shr 16) and $FF) * $101;
  Result.Alpha := ((c shr 24) and $FF) * $101;
end;

procedure TChartIntfImage.SetColor(X, Y: Integer; const AValue: TFPColor);
begin
  SetPixels(X, Y,
    Cardinal(AValue.Blue shr 8) or
    (Cardinal(AValue.Green shr 8) shl 8) or
    (Cardinal(AValue.Red shr 8) shl 16) or
    (Cardinal(AValue.Alpha shr 8) shl 24));
end;

function TChartIntfImage.GetTColor(X, Y: Integer): TColor;
var
  c: Cardinal;
begin
  // Stored $AARRGGBB, TColor is $00BBGGRR.
  c := GetPixels(X, Y);
  Result := TColor(((c shr 16) and $FF) or (c and $FF00) or ((c and $FF) shl 16));
end;

procedure TChartIntfImage.SetTColor(X, Y: Integer; AValue: TColor);
var
  c: Cardinal;
begin
  c := Cardinal(ColorToRGB(AValue));
  SetPixels(X, Y,
    $FF000000 or ((c and $FF) shl 16) or (c and $FF00) or ((c shr 16) and $FF));
end;

procedure TChartIntfImage.GetRawImage(out ARawImage: TRawImage);
begin
  ARawImage.Init;
  ARawImage.Description.Init_BPP32_B8G8R8A8_BIO_TTB(Width, Height);
  ARawImage.Data := PByte(FData);
  ARawImage.DataSize := FDataSize;
end;

procedure TChartIntfImage.DrawTo(ADC: HDC; AX, AY: Integer);
var
  bmi: TBitmapInfo;
  memDC: HDC;
  dib, oldBmp: HBITMAP;
  bits: Pointer;
  bf: TBlendFunction;
begin
  if (Width <= 0) or (Height <= 0) or (FData = nil) then exit;

  FillChar(bmi, SizeOf(bmi), 0);
  with bmi.bmiHeader do begin
    biSize := SizeOf(TBitmapInfoHeader);
    biWidth := Width;
    biHeight := -Height;            // negative => top-down, matching FData
    biPlanes := 1;
    biBitCount := 32;
    biCompression := BI_RGB;
  end;

  memDC := CreateCompatibleDC(ADC);
  if memDC = 0 then exit;
  try
    dib := CreateDIBSection(memDC, bmi, DIB_RGB_COLORS, bits, 0, 0);
    if dib = 0 then exit;
    try
      Move(FData^, bits^, FDataSize);
      oldBmp := SelectObject(memDC, dib);
      try
        bf.BlendOp := AC_SRC_OVER;
        bf.BlendFlags := 0;
        bf.SourceConstantAlpha := 255;
        bf.AlphaFormat := AC_SRC_ALPHA;
        // The chart writes only $00 or $FF alpha, so the buffer already
        // satisfies AlphaBlend's premultiplied-source requirement.
        Winapi.Windows.AlphaBlend(
          ADC, AX, AY, Width, Height, memDC, 0, 0, Width, Height, bf);
      finally
        SelectObject(memDC, oldBmp);
      end;
    finally
      DeleteObject(dib);
    end;
  finally
    DeleteDC(memDC);
  end;
end;

end.
