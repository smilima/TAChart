{
 *****************************************************************************
  This file is part of the Delphi/VCL port of TAChart.

  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  OpenGL rendering for the chart control (GPU rendering, layer 2).

  TAChart already draws through an IChartDrawer, and TAGUIConnector is the seam
  it provides for changing how a chart reaches the screen: the connector hands
  the chart a drawer, is told the bounds before each paint, and presents the
  result afterwards.  TChartGLConnector is that seam filled in for OpenGL - it
  makes the context current, sets a pixel-space projection, and swaps buffers
  when the chart has finished drawing.

  A connector alone is not enough, because an OpenGL window needs CS_OWNDC and
  a context tied to its handle, and only the control can arrange that.  Hence
  TTAChartGL: a TTAChart that owns a TChartGLContext and points itself at the
  GL connector.  If a context cannot be created - a machine without OpenGL, or
  a remote desktop session - it leaves GUIConnector nil and TAChart falls back
  to its ordinary canvas connector, so the chart still draws.

  What this layer does and does not buy
  -------------------------------------
  Every element goes through the same IChartDrawer calls as before, so the
  whole chart renders on the GPU, but each series still walks its points on the
  CPU first.  That is fine at ordinary data sizes and is not what makes
  millions of points fast; the fast path is a series that keeps its samples in
  a vertex buffer and never walks them per frame.  Such a series finds the
  context by asking its drawer for IChartGLDrawer, and falls back to the normal
  point path when the drawer does not provide one - so it keeps working under
  the canvas, SVG and WMF drawers.
}

unit TAChartGL;

{$I TAChartDefines.inc}

interface

uses
  Winapi.Windows,
  System.Classes, System.Types,
  Vcl.Controls,
  TADrawerOpenGL, TAGLContext, TAGraph, TAGUIConnector;

type

  { IChartGLDrawer -- implemented by a drawer that renders into an OpenGL
    context, so a series can reach the context and draw itself directly.
    Mirrors IChartTCanvasDrawer, which does the same for a TCanvas. }

  IChartGLDrawer = interface
    ['{4F2A9C31-7B08-4E5D-9A6C-2D1B8E7F3A04}']
    function GetGLContext: TChartGLContext;
    property GLContext: TChartGLContext read GetGLContext;
  end;

  TChartGLConnector = class;

  { TChartGLDrawer -- the stock OpenGL drawer, plus a way back to the context. }

  TChartGLDrawer = class(TOpenGLDrawer, IChartGLDrawer)
  strict private
    FConnector: TChartGLConnector;
  public
    constructor Create(AConnector: TChartGLConnector); reintroduce;
    function GetGLContext: TChartGLContext;
  end;

  { TChartGLConnector }

  TChartGLConnector = class(TChartGUIConnector)
  strict private
    FContext: TChartGLContext;
  public
    procedure CreateDrawer(var AData: TChartGUIConnectorData); override;
    procedure SetBounds(var AData: TChartGUIConnectorData); override;
    procedure Display(var AData: TChartGUIConnectorData); override;
    // The control keeps this current; nil means there is no context to draw
    // into and the chart should not be using this connector at all.
    property Context: TChartGLContext read FContext write FContext;
  end;

  { TTAChartGL }

  TTAChartGL = class(TTAChart)
  strict private
    FGLConnector: TChartGLConnector;
    FGLContext: TChartGLContext;
    FUseOpenGL: Boolean;
    procedure SetUseOpenGL(AValue: Boolean);
    procedure RebuildContext;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    // The live context, or nil when the chart is falling back to GDI.  Only
    // valid between CreateWnd and DestroyWnd.
    property GLContext: TChartGLContext read FGLContext;
    // True when this chart really is rendering through OpenGL.  UseOpenGL is
    // what was asked for; this is what was achieved.
    function OpenGLActive: Boolean;
  published
    // Set before the handle is created - changing it recreates the handle.
    property UseOpenGL: Boolean read FUseOpenGL write SetUseOpenGL default true;
  end;

implementation

uses
  System.SysUtils,
  TAChartUtils;

{ TChartGLDrawer }

constructor TChartGLDrawer.Create(AConnector: TChartGLConnector);
begin
  inherited Create;
  FConnector := AConnector;
end;

function TChartGLDrawer.GetGLContext: TChartGLContext;
begin
  if FConnector = nil then
    Result := nil
  else
    Result := FConnector.Context;
end;

{ TChartGLConnector }

procedure TChartGLConnector.CreateDrawer(var AData: TChartGUIConnectorData);
begin
  // Called once, when the connector is attached - possibly before the chart
  // has a window and therefore before there is a context.  The drawer reads
  // the context back through the connector at draw time instead of capturing
  // it here.
  AData.FDrawer := TChartGLDrawer.Create(Self);
end;

procedure TChartGLConnector.SetBounds(var AData: TChartGUIConnectorData);
begin
  AData.FDrawerBounds := AData.FBounds;
  if FContext = nil then exit;
  if not FContext.MakeCurrent then exit;
  // Origin at the top-left, one unit per pixel - the coordinate system the
  // chart and every drawer already work in.
  FContext.Setup2D(AData.FBounds.Width, AData.FBounds.Height);
end;

procedure TChartGLConnector.Display(var AData: TChartGUIConnectorData);
begin
  Unused(AData);
  if FContext <> nil then
    FContext.Swap;
end;

{ TTAChartGL }

constructor TTAChartGL.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FUseOpenGL := true;
  FGLConnector := TChartGLConnector.Create(Self);
end;

procedure TTAChartGL.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  // An OpenGL window keeps one device context for its lifetime; the pixel
  // format is set on it once and has to stay set.
  Params.WindowClass.style := Params.WindowClass.style or CS_OWNDC;
end;

procedure TTAChartGL.CreateWnd;
begin
  inherited CreateWnd;
  RebuildContext;
end;

procedure TTAChartGL.DestroyWnd;
begin
  // Fall back before the context goes, so a paint arriving during teardown
  // does not find a connector pointing at freed memory.
  GUIConnector := nil;
  FGLConnector.Context := nil;
  FreeAndNil(FGLContext);
  inherited DestroyWnd;
end;

procedure TTAChartGL.RebuildContext;
begin
  FGLConnector.Context := nil;
  FreeAndNil(FGLContext);

  // The drawer's text textures belong to the context that is going away.
  ChartGLFreeTextures;

  if FUseOpenGL and not (csDesigning in ComponentState) then
    try
      FGLContext := TChartGLContext.Create(Handle);
    except
      // No OpenGL here - a bare remote desktop session, say.  Not an error:
      // the chart draws through GDI instead.
      on EChartGLError do
        FGLContext := nil;
    end;

  FGLConnector.Context := FGLContext;
  if FGLContext <> nil then
    GUIConnector := FGLConnector
  else
    // nil makes TAChart use its own canvas connector.
    GUIConnector := nil;
end;

function TTAChartGL.OpenGLActive: Boolean;
begin
  Result := FGLContext <> nil;
end;

procedure TTAChartGL.SetUseOpenGL(AValue: Boolean);
begin
  if FUseOpenGL = AValue then exit;
  FUseOpenGL := AValue;
  // CS_OWNDC is fixed when the window class is registered, and the context is
  // built in CreateWnd, so the switch takes a new handle.
  if HandleAllocated then
    RecreateWnd;
end;

end.
