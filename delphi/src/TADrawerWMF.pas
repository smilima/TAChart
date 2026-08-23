{
 *****************************************************************************
  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  Authors: Luis Rodrigues, Alexander Klenin

  Delphi/VCL port note
  --------------------
  The Lazarus original spends ~350 lines reimplementing TMetafile and
  TMetafileCanvas because the LCL does not have them.  The VCL does, so this
  unit shrinks to the drawer itself plus the TChart helper.  Despite the
  traditional unit name, the output is an ENHANCED metafile (.emf), the same
  as upstream.
}

unit TADrawerWMF;

{$I TAChartDefines.inc}

interface

uses
  System.Classes, System.Types, Vcl.Graphics,
  TADrawerCanvas, TAGraph;

type

  { TWindowsMetafileDrawer }

  TWindowsMetafileDrawer = class(TCanvasDrawer)
  strict private
    FFileName: String;
    FMetafile: TMetafile;
  public
    constructor Create(const AFileName: String); reintroduce;
    destructor Destroy; override;
  public
    procedure DrawingBegin(const ABoundingBox: TRect); override;
    procedure DrawingEnd; override;
    function GetCanvas: TCanvas; override;
  end;

  { TWMFChartHelper }

  TWMFChartHelper = class helper for TTAChart
    // With an empty file name the metafile goes to the clipboard.
    procedure CopyToClipboardMetafile;
    procedure SaveToWMF(const AFileName: String);
  end;

implementation

uses
  System.SysUtils, Vcl.Clipbrd, TAChartUtils;

{ TWindowsMetafileDrawer }

constructor TWindowsMetafileDrawer.Create(const AFileName: String);
begin
  FFileName := AFileName;
  FMetafile := TMetafile.Create;
  inherited Create(nil);
end;

destructor TWindowsMetafileDrawer.Destroy;
begin
  FreeAndNil(FCanvas);
  FreeAndNil(FMetafile);
  inherited Destroy;
end;

procedure TWindowsMetafileDrawer.DrawingBegin(const ABoundingBox: TRect);
begin
  inherited DrawingBegin(ABoundingBox);
  FreeAndNil(FCanvas);
  FMetafile.SetSize(
    ABoundingBox.Right - ABoundingBox.Left,
    ABoundingBox.Bottom - ABoundingBox.Top);
  FCanvas := TMetafileCanvas.Create(FMetafile, 0);
end;

procedure TWindowsMetafileDrawer.DrawingEnd;
begin
  // The metafile records the drawing only when its canvas is closed.
  FreeAndNil(FCanvas);
  if FFileName = '' then
    Clipboard.Assign(FMetafile)
  else
    FMetafile.SaveToFile(FFileName);
end;

function TWindowsMetafileDrawer.GetCanvas: TCanvas;
begin
  if FCanvas = nil then
    FCanvas := TMetafileCanvas.Create(FMetafile, 0);
  Result := FCanvas;
end;

{ TWMFChartHelper }

procedure TWMFChartHelper.CopyToClipboardMetafile;
begin
  Draw(TWindowsMetafileDrawer.Create(''), Rect(0, 0, Width, Height));
end;

procedure TWMFChartHelper.SaveToWMF(const AFileName: String);
begin
  Draw(TWindowsMetafileDrawer.Create(AFileName), Rect(0, 0, Width, Height));
end;

end.
