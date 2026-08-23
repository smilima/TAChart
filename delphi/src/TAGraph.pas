{
 /***************************************************************************
                               TAGraph.pas
                               -----------
                    Component Library Standard Graph

 ***************************************************************************/

 *****************************************************************************
  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  Authors: Luís Rodrigues, Philippe Martinole, Alexander Klenin

}
unit TAGraph;

{$I TAChartDefines.inc}

interface

uses
  Winapi.Windows, Winapi.Messages, Graphics, Classes, Controls, TALCLCompat,
  SysUtils, TAChartAxis, TAChartAxisUtils, TAChartUtils, TADrawUtils,
  TAGUIConnector, TALegend, TATextElements, TATypes, Types;

{$HPPEMIT END '#pragma comment(lib, "TAChartRT")'}
{$HPPEMIT '#pragma link "TATools"'}

type
  TTAChart = class;

  TReticuleMode = (rmNone, rmVertical, rmHorizontal, rmCross);

  TDrawReticuleEvent = procedure(
    ASender: TTAChart; ASeriesIndex, AIndex: Integer;
    const AData: TDoublePoint) of object;

  TChartDrawLegendEvent = procedure(
    ASender: TTAChart; ADrawer: IChartDrawer; ALegendItems: TChartLegendItems;
    ALegendItemSize: TPoint; const ALegendRect: TRect;
    AColCount, ARowCount: Integer) of object;

  { TBasicChartSeries }

  TBasicChartSeries = class(TIndexedComponent)
  protected
    FActive: Boolean;
    FChart: TTAChart;
    FDepth: TChartDistance;
    FDragOrigin: TPoint;
    FShadow: TChartShadow;
    FTransparency: TChartTransparency;
    FZPosition: TChartDistance;

    procedure AfterAdd; virtual; abstract;
    procedure AfterDraw; virtual;
    procedure BeforeDraw; virtual;
    procedure GetLegendItemsBasic(AItems: TChartLegendItems); virtual; abstract;
    function GetShowInLegend: Boolean; virtual; abstract;
    procedure SetActive(AValue: Boolean); virtual; abstract;
    procedure SetDepth(AValue: TChartDistance); virtual; abstract;
    procedure SetShadow(AValue: TChartShadow); virtual; abstract;
    procedure SetShowInLegend(AValue: Boolean); virtual; abstract;
    procedure SetTransparency(AValue: TChartTransparency); virtual; abstract;
    procedure SetZPosition(AValue: TChartDistance); virtual; abstract;
    procedure UpdateMargins(ADrawer: IChartDrawer; var AMargins: TRect); virtual;
    procedure VisitSources(
      AVisitor: TChartOnSourceVisitor; AAxis: TChartAxis; var AData); virtual;

  public
    function AxisToGraphX(AX: Double): Double; virtual;
    function AxisToGraphY(AY: Double): Double; virtual;
    function GraphToAxisX(AX: Double): Double; virtual;
    function GraphToAxisY(AY: Double): Double; virtual;

  public
    procedure Assign(Source: TPersistent); override;
    destructor Destroy; override;

  public
    procedure Draw(ADrawer: IChartDrawer); virtual; abstract;
    function GetAxisBounds(AAxis: TChartAxis; out AMin, AMax: Double): boolean; virtual; abstract;
    function GetGraphBounds: TDoubleRect; virtual; abstract;
    function IsEmpty: Boolean; virtual; abstract;
    procedure MovePoint(var AIndex: Integer; const ANewPos: TPoint); overload; inline;
    procedure MovePoint(var AIndex: Integer; const ANewPos: TDoublePoint); overload; virtual;
    procedure MovePointEx(var AIndex: Integer; AXIndex, AYIndex: Integer;
      const ANewPos: TDoublePoint); virtual;
    procedure UpdateBiDiMode; virtual;
    function UsesPolarCoordinates: Boolean; virtual;

    property Active: Boolean read FActive write SetActive default true;
    property Depth: TChartDistance read FDepth write SetDepth default 0;
    property DragOrigin: TPoint read FDragOrigin write FDragOrigin;
    property ParentChart: TTAChart read FChart;
    property Shadow: TChartShadow read FShadow write SetShadow;
    property Transparency: TChartTransparency
      read FTransparency write SetTransparency default 0;
    property ZPosition: TChartDistance read FZPosition write SetZPosition default 0;
  end;

  TSeriesClass = class of TBasicChartSeries;

  { TBasicСhartTool }

  TBasicChartTool = class(TIndexedComponent)
  strict protected
    FChart: TTAChart;
    FStartMousePos: TPoint;

    procedure Activate; virtual;
    procedure Deactivate; virtual;
    function PopupMenuConflict: Boolean; virtual;
  public
    property Chart: TTAChart read FChart;
  end;

  TChartToolEventId = (
    evidKeyDown, evidKeyUp, evidMouseDown, evidMouseMove, evidMouseUp,
    evidMouseWheelDown, evidMouseWheelUp);

  { TBasicChartToolset }

  TBasicChartToolset = class(TComponent)
  public
    function Dispatch(
      AChart: TTAChart; AEventId: TChartToolEventId;
      AShift: TShiftState; APoint: TPoint): Boolean; reintroduce; overload; virtual; abstract;
      procedure Draw(AChart: TTAChart; ADrawer: IChartDrawer); virtual; abstract;
  end;

  TBasicChartSeriesEnumerator = class(TChartListEnumerator)
  public
    function GetCurrent: TBasicChartSeries;
    property Current: TBasicChartSeries read GetCurrent;
  end;

  { TChartSeriesList }

  TChartSeriesList = class(TPersistent)
  private
    FList: TIndexedComponentList;
    function GetItem(AIndex: Integer): TBasicChartSeries;
  public
    constructor Create;
    destructor Destroy; override;
  public
    procedure Clear;
    function Count: Integer;
    function GetEnumerator: TBasicChartSeriesEnumerator;
    procedure UpdateBiDiMode;
  public
    property Items[AIndex: Integer]: TBasicChartSeries read GetItem; default;
    property List: TIndexedComponentList read FList;
  end;

  TChartAfterDrawEvent = procedure (
    ASender: TTAChart; ACanvas: TCanvas; const ARect: TRect) of object;
  TChartBeforeDrawEvent = procedure (
    ASender: TTAChart; ACanvas: TCanvas; const ARect: TRect;
    var ADoDefaultDrawing: Boolean) of object;
  TChartEvent = procedure (ASender: TTAChart) of object;
  TChartPaintEvent = procedure (
    ASender: TTAChart; const ARect: TRect;
    var ADoDefaultDrawing: Boolean) of object;
  TChartDrawEvent = procedure (
    ASender: TTAChart; ADrawer: IChartDrawer) of object;

  TChartRenderingParams = record
    FClipRect: TRect;
    FIsZoomed: Boolean;
    FLogicalExtent, FPrevLogicalExtent: TDoubleRect;
    FScale, FOffset: TDoublePoint;
  end;

  { TTAChart }

  [ComponentPlatformsAttribute(pfidWindows)]
  TTAChart = class(TCustomChart, ICoordTransformer)
  strict private // Property fields
    FAllowZoom: Boolean;
    FAntialiasingMode: TChartAntialiasingMode;
    FAxisList: TChartAxisList;
    FAxisVisible: Boolean;
    FBackColor: TColor;
    FConnectorData: TChartGUIConnectorData;
    FDepth: TChartDistance;
    FDefaultGUIConnector: TChartGUIConnector;
    FExpandPercentage: Integer;
    FExtent: TChartExtent;
    FExtentSizeLimit: TChartExtent;
    FFoot: TChartTitle;
    FFrame: TChartPen;
    FGUIConnector: TChartGUIConnector;
    FGUIConnectorListener: TListener;
    FLegend: TChartLegend;
    FLogicalExtent: TDoubleRect;
    FMargins: TChartMargins;
    FMarginsExternal: TChartMargins;
    FOnAfterDraw: TChartDrawEvent;
    FOnAfterDrawBackground: TChartAfterDrawEvent;
    FOnAfterDrawBackWall: TChartAfterDrawEvent;
    FOnBeforeDrawBackground: TChartBeforeDrawEvent;
    FOnBeforeDrawBackWall: TChartBeforeDrawEvent;
    FOnChartPaint: TChartPaintEvent;
    FOnDrawReticule: TDrawReticuleEvent;
    FOnDrawLegend: TChartDrawLegendEvent;
    FProportional: Boolean;
    FSeries: TChartSeriesList;
    FTitle: TChartTitle;
    FToolset: TBasicChartToolset;

    function ClipRectWithoutFrame(AZPosition: TChartDistance): TRect;
    function EffectiveGUIConnector: TChartGUIConnector; inline;
  private
    FActiveToolIndex: Integer;
    FAutoFocus: Boolean;
    FBroadcaster: TBroadcaster;
    FBuiltinToolset: TBasicChartToolset;
    FClipRect: TRect;
    FCurrentExtent: TDoubleRect;
    FDisableRedrawingCounter: Integer;
    FExtentBroadcaster: TBroadcaster;
    FIsZoomed: Boolean;
    FOffset: TDoublePoint;   // Coordinates transformation
    FOnAfterPaint: TChartEvent;
    FOnExtentChanged: TChartEvent;
    FOnExtentChanging: TChartEvent;
    FPrevLogicalExtent: TDoubleRect;
    FReticuleMode: TReticuleMode;
    FReticulePos: TPoint;
    FScale: TDoublePoint;    // Coordinates transformation

    procedure CalculateTransformationCoeffs(const AMargin: TRect);
    procedure DrawReticule(ADrawer: IChartDrawer);
    procedure FindComponentClass(
      AReader: TReader; const AClassName: String; var AClass: TComponentClass);
    function GetChartHeight: Integer;
    function GetChartWidth: Integer;
    function GetMargins(ADrawer: IChartDrawer): TRect;
    function GetRenderingParams: TChartRenderingParams;
    function GetSeriesCount: Integer;
    function GetToolset: TBasicChartToolset;
    procedure HideReticule;

    function HasPolarCoordinates: Boolean;
    function PolarSquareExtent(const AExtent: TDoubleRect): TDoubleRect;
    procedure DrawPolarGrid(ADrawer: IChartDrawer);
    procedure PreparePolarLabelFont(ADrawer: IChartDrawer);
    procedure DrawDesignFrame(ADrawer: IChartDrawer; const ARect: TRect);

    procedure SetAntialiasingMode(AValue: TChartAntialiasingMode);
    procedure SetAxisList(AValue: TChartAxisList);
    procedure SetAxisVisible(Value: Boolean);
    procedure SetBackColor(AValue: TColor);
    procedure SetDepth(AValue: TChartDistance);
    procedure SetExpandPercentage(AValue: Integer);
    procedure SetExtent(AValue: TChartExtent);
    procedure SetExtentSizeLimit(AValue: TChartExtent);
    procedure SetFoot(Value: TChartTitle);
    procedure SetFrame(Value: TChartPen);
    procedure SetGUIConnector(AValue: TChartGUIConnector);
    procedure SetLegend(Value: TChartLegend);
    procedure SetLogicalExtent(const AValue: TDoubleRect);
    procedure SetMargins(AValue: TChartMargins);
    procedure SetMarginsExternal(AValue: TChartMargins);
    procedure SetOnAfterDraw(AValue: TChartDrawEvent);
    procedure SetOnAfterDrawBackground(AValue: TChartAfterDrawEvent);
    procedure SetOnAfterDrawBackWall(AValue: TChartAfterDrawEvent);
    procedure SetOnBeforeDrawBackground(AValue: TChartBeforeDrawEvent);
    procedure SetOnBeforeDrawBackWall(AValue: TChartBeforeDrawEvent);
    procedure SetOnChartPaint(AValue: TChartPaintEvent);
    procedure SetOnDrawLegend(AValue: TChartDrawLegendEvent);
    procedure SetOnDrawReticule(AValue: TDrawReticuleEvent);
    procedure SetProportional(AValue: Boolean);
    procedure SetRenderingParams(AValue: TChartRenderingParams);
    procedure SetReticuleMode(AValue: TReticuleMode);
    procedure SetReticulePos(const AValue: TPoint);
    procedure SetTitle(Value: TChartTitle);
    procedure SetToolset(AValue: TBasicChartToolset);
    procedure VisitSources(
      AVisitor: TChartOnSourceVisitor; AAxis: TChartAxis; var AData);
  protected
    FDisablePopupMenu: Boolean;
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
    function DoMouseWheel(
      AShift: TShiftState; AWheelDelta: Integer;
      AMousePos: TPoint): Boolean; override;
    procedure MouseDown(
      Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(
      AButton: TMouseButton; AShift: TShiftState; AX, AY: Integer); override;
  protected
    function GetAxisBounds(AAxis: TChartAxis): TDoubleInterval;
    function GetAxisByAlign(AAlign: TChartAxisAlignment): TChartAxis;
    procedure SetAxisByAlign(AAlign: TChartAxisAlignment; AValue: TChartAxis); inline;
  protected
    procedure Clear(ADrawer: IChartDrawer; const ARect: TRect);
    procedure DisplaySeries(ADrawer: IChartDrawer);
    procedure DrawBackWall(ADrawer: IChartDrawer);
    // The LCL calls KeyDownAfterInterface/KeyUpAfterInterface once the widget
    // has had its turn; KeyDown/KeyUp are the VCL equivalents.
    procedure KeyDown(var AKey: Word; AShift: TShiftState); override;
    procedure KeyUp(var AKey: Word; AShift: TShiftState); override;
    {$IFDEF LCLGtk2}
    procedure DoOnResize; override;
    {$ENDIF}
    procedure Notification(
      AComponent: TComponent; AOperation: TOperation); override;
    procedure PrepareAxis(ADrawer: IChartDrawer);
    function PrepareLegend(
      ADrawer: IChartDrawer; var AClipRect: TRect): TChartLegendDrawingData;
    procedure SetBiDiMode(AValue: TBiDiMode); override;
    procedure SetName(const AValue: TComponentName); override;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // The VCL equivalent of overriding LCL's EraseBackground.
    procedure WMEraseBkgnd(var AMessage: TWMEraseBkgnd);
      message WM_ERASEBKGND;
    procedure GetChildren(AProc: TGetChildProc; ARoot: TComponent); override;
    procedure Paint; override;
    procedure SetChildOrder(Child: TComponent; Order: Integer); override;

  public // Helpers for series drawing
    procedure DrawLineHoriz(ADrawer: IChartDrawer; AY: Integer);
    procedure DrawLineVert(ADrawer: IChartDrawer; AX: Integer);
    procedure DrawOnCanvas(Rect: TRect; ACanvas: TCanvas); deprecated;
    function IsPointInViewPort(const AP: TDoublePoint): Boolean;

  public
    procedure AddSeries(ASeries: TBasicChartSeries);
    procedure ClearSeries;
    function Clone: TTAChart;
    procedure CopyToClipboardBitmap;
    procedure DeleteSeries(ASeries: TBasicChartSeries);
    procedure DisableRedrawing;
    procedure Draw(ADrawer: IChartDrawer; const ARect: TRect);
    procedure DrawLegendOn(ACanvas: TCanvas; var ARect: TRect);
    procedure EnableRedrawing;
    function GetFullExtent: TDoubleRect;
    function GetLegendItems(AIncludeHidden: Boolean = false): TChartLegendItems;
    procedure Notify(ACommand: Integer; AParam1, AParam2: Pointer; var AData); override;
    procedure PaintOnAuxCanvas(ACanvas: TCanvas; ARect: TRect);
    procedure PaintOnCanvas(ACanvas: TCanvas; ARect: TRect);
    procedure Prepare;
    procedure RemoveSeries(ASeries: TBasicChartSeries); inline;
    procedure SaveToBitmapFile(const AFileName: String); inline;
    procedure SaveToFile(AClass: TGraphicClass; AFileName: String);
    function SaveToImage(AClass: TGraphicClass): TGraphic;
    procedure StyleChanged(Sender: TObject); override;
    procedure ZoomFull(AImmediateRecalc: Boolean = false); override;
    property Drawer: IChartDrawer read FConnectorData.FDrawer;

  public // Coordinate conversion
    function GraphToImage(const AGraphPoint: TDoublePoint): TPoint;
    function ImageToGraph(const APoint: TPoint): TDoublePoint;
    // Do not inline: these implement ICoordTransformer, and axis interval
    // calculation takes them as method pointers. Delphi/C++Builder cannot
    // form a reliable of-object pointer to an inlined or interface method.
    function XGraphToImage(AX: Double): Integer;
    function XImageToGraph(AX: Integer): Double;
    function YGraphToImage(AY: Double): Integer;
    function YImageToGraph(AY: Integer): Double;

  public
    property ActiveToolIndex: Integer read FActiveToolIndex;
    property Broadcaster: TBroadcaster read FBroadcaster;
    property ChartHeight: Integer read GetChartHeight;
    property ChartWidth: Integer read GetChartWidth;
    property ClipRect: TRect read FClipRect;
    property CurrentExtent: TDoubleRect read FCurrentExtent;
    property ExtentBroadcaster: TBroadcaster read FExtentBroadcaster;
    property IsZoomed: Boolean read FIsZoomed;
    property LogicalExtent: TDoubleRect read FLogicalExtent write SetLogicalExtent;
    property OnChartPaint: TChartPaintEvent
      read FOnChartPaint write SetOnChartPaint;  // experimental
    property PrevLogicalExtent: TDoubleRect read FPrevLogicalExtent;
    property RenderingParams: TChartRenderingParams
      read GetRenderingParams write SetRenderingParams;
    property ReticulePos: TPoint read FReticulePos write SetReticulePos;
    property SeriesCount: Integer read GetSeriesCount;
    property XGraphMax: Double read FCurrentExtent.b.X;
    property XGraphMin: Double read FCurrentExtent.a.X;
    property YGraphMax: Double read FCurrentExtent.b.Y;
    property YGraphMin: Double read FCurrentExtent.a.Y;

  published
    property AutoFocus: Boolean read FAutoFocus write FAutoFocus default false;
    property AllowZoom: Boolean read FAllowZoom write FAllowZoom default true;
    property AntialiasingMode: TChartAntialiasingMode
      read FAntialiasingMode write SetAntialiasingMode default amDontCare;
    property AxisList: TChartAxisList read FAxisList write SetAxisList;
    property AxisVisible: Boolean read FAxisVisible write SetAxisVisible default true;
    property BackColor: TColor read FBackColor write SetBackColor default clBtnFace;
    property BottomAxis: TChartAxis index calBottom read GetAxisByAlign write SetAxisByAlign stored false;
    property Depth: TChartDistance read FDepth write SetDepth default 0;
    property ExpandPercentage: Integer
      read FExpandPercentage write SetExpandPercentage default 0;
    property Extent: TChartExtent read FExtent write SetExtent;
    property ExtentSizeLimit: TChartExtent read FExtentSizeLimit write SetExtentSizeLimit;
    property Foot: TChartTitle read FFoot write SetFoot;
    property Frame: TChartPen read FFrame write SetFrame;
    property GUIConnector: TChartGUIConnector
      read FGUIConnector write SetGUIConnector;
    property LeftAxis: TChartAxis index calLeft read GetAxisByAlign write SetAxisByAlign stored false;
    property Legend: TChartLegend read FLegend write SetLegend;
    property Margins: TChartMargins read FMargins write SetMargins;
    property MarginsExternal: TChartMargins
      read FMarginsExternal write SetMarginsExternal;
    property Proportional: Boolean
      read FProportional write SetProportional default false;
    property ReticuleMode: TReticuleMode
      read FReticuleMode write SetReticuleMode default rmNone;
    property Series: TChartSeriesList read FSeries;
    property Title: TChartTitle read FTitle write SetTitle;
    property Toolset: TBasicChartToolset read FToolset write SetToolset;

  published
    property OnAfterDraw: TChartDrawEvent read FOnAfterDraw write SetOnAfterDraw;
    property OnAfterDrawBackground: TChartAfterDrawEvent
      read FOnAfterDrawBackground write SetOnAfterDrawBackground;
    property OnAfterDrawBackWall: TChartAfterDrawEvent
      read FOnAfterDrawBackWall write SetOnAfterDrawBackWall;
    property OnAfterPaint: TChartEvent read FOnAfterPaint write FOnAfterPaint;
    property OnBeforeDrawBackground: TChartBeforeDrawEvent
      read FOnBeforeDrawBackground write SetOnBeforeDrawBackground;
    property OnBeforeDrawBackWall: TChartBeforeDrawEvent
      read FOnBeforeDrawBackWall write SetOnBeforeDrawBackWall;
    property OnDrawLegend: TChartDrawLegendEvent
      read FOnDrawLegend write SetOnDrawLegend;
    property OnDrawReticule: TDrawReticuleEvent
      read FOnDrawReticule write SetOnDrawReticule;
    property OnExtentChanged: TChartEvent
      read FOnExtentChanged write FOnExtentChanged;
    property OnExtentChanging: TChartEvent
      read FOnExtentChanging write FOnExtentChanging;

  published
    property Align;
    property Anchors;
    property BiDiMode;
    property Color default clBtnFace;
    property DoubleBuffered;
    property DragCursor;
    property DragMode;
    property Enabled;
    property ParentBiDiMode;
    property ParentColor default false;
    property ParentShowHint;
    property PopupMenu;
    property ShowHint;
    property Visible;

  published
    property OnClick;
    property OnContextPopup;
    property OnDblClick;
    property OnDragDrop;
    property OnDragOver;
    property OnEndDrag;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnResize;
    property OnStartDrag;
  end;

  // Type alias for source compatibility. ClassName is TTAChart so it
  // does not collide with TeeChart when RegisterClass walks ancestors.
  {$NODEFINE TChart} // C++ must use TTAChart; TChart collides with TeeChart
  TChart = TTAChart;

procedure RegisterSeriesClass(ASeriesClass: TSeriesClass; const ACaption: String); overload;
procedure RegisterSeriesClass(ASeriesClass: TSeriesClass; ACaptionPtr: PStr); overload;

var
  SeriesClassRegistry: TClassRegistry = nil;
  OnInitBuiltinTools: function(AChart: TTAChart): TBasicChartToolset;

implementation

uses
  Vcl.Clipbrd, Dialogs, Math, TADrawerCanvas, TAGeometry, TAMath, TAStyles,
  TATools;

//  TATools;  // needed to initialize OnInitBuiltinTools; added to avoid crash of converted Delphi projects
// wp: removed again, causes compilation error with fpc 2.6.4
// Delphi/C++Builder: TATools is required so builtin zoom/pan tools exist.
// C++ projects that only #pragma link "TAGraph" otherwise leave OnInitBuiltinTools nil.

function CompareZPosition(AItem1, AItem2: Pointer): Integer;
begin
  Result :=
    TBasicChartSeries(AItem1).ZPosition - TBasicChartSeries(AItem2).ZPosition;
end;


procedure EnsureSeriesClassRegistry;
begin
  if SeriesClassRegistry = nil then
    SeriesClassRegistry := TClassRegistry.Create;
end;

procedure RegisterSeriesClass(ASeriesClass: TSeriesClass; const ACaption: String);
begin
  EnsureSeriesClassRegistry;
  System.Classes.RegisterClass(ASeriesClass);
  if SeriesClassRegistry.IndexOfClass(ASeriesClass) < 0 then
    SeriesClassRegistry.Add(TClassRegistryItem.Create(ASeriesClass, ACaption));
end;

procedure RegisterSeriesClass(ASeriesClass: TSeriesClass; ACaptionPtr: PStr);
begin
  EnsureSeriesClassRegistry;
  System.Classes.RegisterClass(ASeriesClass);
  if SeriesClassRegistry.IndexOfClass(ASeriesClass) < 0 then
    SeriesClassRegistry.Add(TClassRegistryItem.CreateRes(ASeriesClass, ACaptionPtr));
end;

// The Lazarus original goes through CreateLRSWriter / ReadComponentFromBinaryStream;
// the plain RTL streaming classes do the same job in Delphi.
procedure WriteComponentToStream(AStream: TStream; AComponent: TComponent);
var
  writer: TWriter;
begin
  writer := TWriter.Create(AStream, 4096);
  try
    writer.Root := AComponent.Owner;
    writer.WriteRootComponent(AComponent);
  finally
    writer.Free;
  end;
end;

function ReadComponentFromStream(AStream: TStream;
  AOnFindComponentClass: TFindComponentClassEvent;
  AOwner, AParent, ARoot: TComponent): TComponent;
var
  reader: TReader;
begin
  reader := TReader.Create(AStream, 4096);
  try
    reader.OnFindComponentClass := AOnFindComponentClass;
    reader.Root := ARoot;
    reader.Owner := AOwner;
    reader.Parent := AParent;
    Result := reader.ReadRootComponent(nil);
  finally
    reader.Free;
  end;
end;

{ TBasicChartSeriesEnumerator }

function TBasicChartSeriesEnumerator.GetCurrent: TBasicChartSeries;
begin
  Result := TBasicChartSeries(inherited GetCurrent);
end;

{ TTAChart }

procedure TTAChart.AddSeries(ASeries: TBasicChartSeries);
begin
  if ASeries.FChart = Self then exit;
  if ASeries.FChart <> nil then
    ASeries.FChart.DeleteSeries(ASeries);
  HideReticule;
  Series.FList.Add(ASeries);
  ASeries.FChart := Self;
  ASeries.AfterAdd;
  StyleChanged(ASeries);
end;

procedure TTAChart.CalculateTransformationCoeffs(const AMargin: TRect);
var
  rX, rY: TAxisCoeffHelper;
begin
  rX.Init(
    BottomAxis, FClipRect.Left, FClipRect.Right, AMargin.Left, -AMargin.Right,
    @FCurrentExtent.a.X, @FCurrentExtent.b.X);
  rY.Init(
    LeftAxis, FClipRect.Bottom, FClipRect.Top, -AMargin.Bottom, AMargin.Top,
    @FCurrentExtent.a.Y, @FCurrentExtent.b.Y);
  FScale.X := rX.CalcScale(1);
  FScale.Y := rY.CalcScale(-1);
  if Proportional or HasPolarCoordinates then begin
    if Abs(FScale.X) > Abs(FScale.Y) then
      FScale.X := Abs(FScale.Y) * Sign(FScale.X)
    else
      FScale.Y := Abs(FScale.X) * Sign(FScale.Y);
  end;
  FOffset.X := rX.CalcOffset(FScale.X);
  FOffset.Y := rY.CalcOffset(FScale.Y);
  rX.UpdateMinMax(XImageToGraph);
  rY.UpdateMinMax(YImageToGraph);
end;

procedure TTAChart.Clear(ADrawer: IChartDrawer; const ARect: TRect);
var
  defaultDrawing: Boolean;
  ic: IChartTCanvasDrawer;
begin
  defaultDrawing := true;
  ADrawer.PrepareSimplePen(Color);
  ADrawer.SetBrushParams(bsSolid, Color);
  if Supports(ADrawer, IChartTCanvasDrawer, ic) and Assigned(OnBeforeDrawBackground) then
    OnBeforeDrawBackground(Self, ic.Canvas, ARect, defaultDrawing);
  if defaultDrawing then
    ADrawer.FillRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);
//    ADrawer.Rectangle(ARect);
  if Supports(ADrawer, IChartTCanvasDrawer, ic) and Assigned(OnAfterDrawBackground) then
    OnAfterDrawBackground(Self, ic.Canvas, ARect);
end;

procedure TTAChart.ClearSeries;
begin
  FSeries.Clear;
  StyleChanged(Self);
end;

function TTAChart.ClipRectWithoutFrame(AZPosition: TChartDistance): TRect;
begin
  Result := FClipRect;
  if (AZPosition > 0) or not Frame.EffVisible then exit;
  Result.Left := Result.Left + ((Frame.Width + 1) div 2);
  Result.Top := Result.Top + ((Frame.Width + 1) div 2);
  Result.Bottom := Result.Bottom - (Frame.Width div 2);
  Result.Right := Result.Right - (Frame.Width div 2);
end;

function TTAChart.Clone: TTAChart;
var
  ms: TMemoryStream;
  cloned: TComponent;
begin
  cloned := nil;
  ms := TMemoryStream.Create;
  try
    WriteComponentToStream(ms, Self);
    ms.Seek(0, soBeginning);
    cloned := ReadComponentFromStream(
      ms, FindComponentClass, Owner, Parent, Owner);
    Result := cloned as TTAChart;
  finally
    ms.Free;
  end;
end;

procedure TTAChart.CopyToClipboardBitmap;
var
  g: TGraphic;
begin
  g := SaveToImage(TBitmap);
  try
    Clipboard.Assign(g);
  finally
    g.Free;
  end;
end;

constructor TTAChart.Create(AOwner: TComponent);
const
  DEFAULT_CHART_WIDTH = 300;
  DEFAULT_CHART_HEIGHT = 200;
  DEFAULT_CHART_TITLE = 'TAChart';
  FONT_VERTICAL = 900;
begin
  inherited Create(AOwner);

  FBroadcaster := TBroadcaster.Create;
  FExtentBroadcaster := TBroadcaster.Create;
  FAllowZoom := true;
  FAntialiasingMode := amDontCare;
  FAxisVisible := true;
  FConnectorData.FCanvas := Canvas;
  FDefaultGUIConnector := TChartGUIConnectorCanvas.Create(Self);
  FDefaultGUIConnector.CreateDrawer(FConnectorData);
  FGUIConnectorListener := TListener.Create(@FGUIConnector, StyleChanged);

  FScale := DoublePoint(1, 1);

  Width := DEFAULT_CHART_WIDTH;
  Height := DEFAULT_CHART_HEIGHT;

  FReticulePos := Point(-1, -1);
  FReticuleMode := rmNone;

  FSeries := TChartSeriesList.Create;

  Color := clBtnFace;
  FBackColor := clBtnFace;

  FIsZoomed := false;

  FLegend := TChartLegend.Create(Self);
  FTitle := TChartTitle.Create(Self);
  FTitle.Alignment := taCenter;
  FTitle.Text.Add(DEFAULT_CHART_TITLE);
  FFoot := TChartTitle.Create(Self);

  FAxisList := TChartAxisList.Create(Self);
  FAxisList.OnVisitSources := VisitSources;
  with TChartAxis.Create(FAxisList) do begin
    Alignment := calLeft;
    Title.LabelFont.Orientation := FONT_VERTICAL;
  end;
  with TChartAxis.Create(FAxisList) do
    Alignment := calBottom;

  FFrame :=  TChartPen.Create;
  FFrame.OnChange := StyleChanged;

  FExtent := TChartExtent.Create(Self);
  FExtentSizeLimit := TChartExtent.Create(Self);
  FMargins := TChartMargins.Create(Self);
  FMarginsExternal := TChartMargins.Create(Self);

  // TATools assigns OnInitBuiltinTools in its initialization section. C++Builder
  // can load TAGraph without running that section, so fall back to a direct call.
  if Assigned(OnInitBuiltinTools) then
    FBuiltinToolset := OnInitBuiltinTools(Self);
  if FBuiltinToolset = nil then
    FBuiltinToolset := InitBuiltinTools(Self);
  FActiveToolIndex := -1;

  FLogicalExtent := EmptyExtent;
  FPrevLogicalExtent := EmptyExtent;
end;

procedure TTAChart.DeleteSeries(ASeries: TBasicChartSeries);
var
  i: Integer;
begin
  i := FSeries.FList.IndexOf(ASeries);
  if i < 0 then exit;
  FSeries.FList.Delete(i);
  ASeries.FChart := nil;
  StyleChanged(Self);
end;

destructor TTAChart.Destroy;
begin
  FreeAndNil(FSeries);

  FreeAndNil(FLegend);
  FreeAndNil(FTitle);
  FreeAndNil(FFoot);
  FreeAndNil(FAxisList);
  FreeAndNil(FFrame);
  FreeAndNil(FGUIConnectorListener);
  FreeAndNil(FExtent);
  FreeAndNil(FExtentSizeLimit);
  FreeAndNil(FMargins);
  FreeAndNil(FMarginsExternal);
  FreeAndNil(FBuiltinToolset);
  FreeAndNil(FBroadcaster);
  FreeAndNil(FExtentBroadcaster);
  FreeAndNil(FDefaultGUIConnector);

  DrawData.DeleteByChart(Self);
  inherited;
end;

procedure TTAChart.DisableRedrawing;
begin
  FDisableRedrawingCounter := FDisableRedrawingCounter + 1;
end;

procedure TTAChart.DisplaySeries(ADrawer: IChartDrawer);

  procedure OffsetDrawArea(ADX, ADY: Integer);
  begin
    FOffset.X := FOffset.X + ADX;
    FOffset.Y := FOffset.Y + ADY;
    OffsetRect(FClipRect, ADX, ADY);
  end;

  procedure OffsetWithDepth(AZPos, ADepth: Integer);
  begin
    AZPos := ADrawer.Scale(AZPos);
    ADepth := ADrawer.Scale(ADepth);
    OffsetDrawArea(-AZPos, AZPos);
    FClipRect.Right := FClipRect.Right + ADepth;
    FClipRect.Top := FClipRect.Top - ADepth;
  end;

  procedure DrawOrDeactivate(
    ASeries: TBasicChartSeries; ATransparency: TChartTransparency);
  begin
    try
      ADrawer.SetTransparency(ATransparency);
      ASeries.Draw(ADrawer);
    except
      ASeries.Active := false;
      raise;
    end;
  end;

var
  axisIndex: Integer;
  seriesInZOrder: TChartSeriesList;
  s: TBasicChartSeries;
begin
  axisIndex := 0;
  if SeriesCount > 0 then begin
    seriesInZOrder := TChartSeriesList.Create;
    try
      seriesInZOrder.List.Assign(FSeries.List);
      seriesInZOrder.List.Sort(CompareZPosition);

      for s in seriesInZOrder do begin
        if not s.Active then continue;
        // Interleave axises with series according to ZPosition.
        if AxisVisible and not HasPolarCoordinates then
          AxisList.Draw(s.ZPosition, axisIndex);
        OffsetWithDepth(Min(s.ZPosition, Depth), Min(s.Depth, Depth));
        ADrawer.ClippingStart(ClipRectWithoutFrame(s.ZPosition));

        try
          with s.Shadow do
            if Visible then begin
              OffsetDrawArea(OffsetX, OffsetY);
              ADrawer.SetMonochromeColor(Color);
              try
                DrawOrDeactivate(s, Transparency);
              finally
                ADrawer.SetMonochromeColor(clTAColor);
                OffsetDrawArea(-OffsetX, -OffsetY);
              end;
            end;
          DrawOrDeactivate(s, s.Transparency);
        finally
          OffsetWithDepth(-Min(s.ZPosition, Depth), -Min(s.Depth, Depth));
          ADrawer.ClippingStop;
        end;
      end;
    finally
      seriesInZOrder.List.Clear; // Avoid freeing series.
      seriesInZOrder.Free;
      ADrawer.SetTransparency(0);
    end;
  end;
  if AxisVisible and not HasPolarCoordinates then
    AxisList.Draw(MaxInt, axisIndex);
end;

procedure TTAChart.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
begin
  if FDisablePopupMenu then Handled := true;
  inherited;
end;

function TTAChart.DoMouseWheel(
  AShift: TShiftState; AWheelDelta: Integer; AMousePos: TPoint): Boolean;
const
  EV: array [Boolean] of TChartToolEventId = (
    evidMouseWheelDown, evidMouseWheelUp);
var
  ts: TBasicChartToolset;
begin
  ts := GetToolset;
  Result :=
    Assigned(ts) and ts.Dispatch(Self, EV[AWheelDelta > 0], AShift, AMousePos) or
    inherited DoMouseWheel(AShift, AWheelDelta, AMousePos);
end;

{$IFDEF LCLGtk2}
procedure TTAChart.DoOnResize;
begin
  inherited;
  // FIXME: GTK does not invalidate the control on resizing, do it manually
  Invalidate;
end;
{$ENDIF}

procedure TTAChart.Draw(ADrawer: IChartDrawer; const ARect: TRect);
var
  ldd: TChartLegendDrawingData;
  s: TBasicChartSeries;
  ts: TBasicChartToolset;
  phTitle: String;
  phTitleTop, phTitleHeight: Integer;
begin
  Prepare;

  ADrawer.SetRightToLeft(BiDiMode <> bdLeftToRight);

  FClipRect := ARect;
  with MarginsExternal do begin
    FClipRect.Left := FClipRect.Left + Left;
    FClipRect.Top := FClipRect.Top + Top;
    FClipRect.Right := FClipRect.Right - Right;
    FClipRect.Bottom := FClipRect.Bottom - Bottom;
  end;

  // At design time an untitled chart shows its name where the title will go,
  // the way TeeChart does, so the reserved area is visible on the form.
  phTitleHeight := 0;
  phTitleTop := 0;
  phTitle := '';
  if (csDesigning in ComponentState) and not FTitle.Visible then begin
    phTitle := Trim(FTitle.Text.Text);
    if phTitle = '' then
      phTitle := Name;
    if phTitle = '' then
      phTitle := 'TTAChart';
    ADrawer.Font := FTitle.Font;
    phTitleHeight := ADrawer.TextExtent(phTitle).Y + ADrawer.Scale(DEF_MARGIN);
    phTitleTop := FClipRect.Top + ADrawer.Scale(DEF_MARGIN) div 2;
    FClipRect.Top := FClipRect.Top + phTitleHeight;
  end;

  with FClipRect do begin
    FTitle.Measure(ADrawer, 1, Left, Right, Top);
    FFoot.Measure(ADrawer, -1, Left, Right, Bottom);
  end;

  ldd.FItems := nil;
  if Legend.Visible then
    ldd := PrepareLegend(ADrawer, FClipRect);

  try
    PrepareAxis(ADrawer);
    if Legend.Visible and not Legend.UseSidebar then
      Legend.Prepare(ldd, FClipRect);
    if (FPrevLogicalExtent <> FLogicalExtent) and Assigned(OnExtentChanging) then
      OnExtentChanging(Self);
    ADrawer.DrawingBegin(ARect);
    ADrawer.SetAntialiasingMode(AntialiasingMode);
    Clear(ADrawer, ARect);
    if csDesigning in ComponentState then
      DrawDesignFrame(ADrawer, ARect);
    if phTitleHeight > 0 then begin
      ADrawer.Font := FTitle.Font;
      ADrawer.TextOut.Pos(
        (FClipRect.Left + FClipRect.Right - ADrawer.TextExtent(phTitle).X) div 2,
        phTitleTop).Text(phTitle).Done;
    end;
    FTitle.Draw(ADrawer);
    FFoot.Draw(ADrawer);
    DrawBackWall(ADrawer);
    DisplaySeries(ADrawer);
    if Legend.Visible then begin
      if Assigned(FOnDrawLegend) then
        FOnDrawlegend(Self, ldd.FDrawer, ldd.FItems, ldd.FItemSize, ldd.FBounds,
          ldd.FColCount, ldd.FRowCount)
      else
        Legend.Draw(ldd);
    end;
  finally
    ldd.FItems.Free;
  end;
  DrawReticule(ADrawer);
  ts := GetToolset;
  if Assigned(ts) then
    ts.Draw(Self, ADrawer);

  for s in Series do
    s.AfterDraw;

  if Assigned(OnAfterDraw) then
    OnAfterDraw(Self, ADrawer);
  ADrawer.DrawingEnd;

  if FPrevLogicalExtent <> FLogicalExtent then begin
    FExtentBroadcaster.Broadcast(Self);
    if Assigned(OnExtentChanged) then
      OnExtentChanged(Self);
    FPrevLogicalExtent := FLogicalExtent;
  end;

  // Undo changes made by the drawer (mainly for printing). The user may print
  // something else after the chart and, for example, would not expect the font
  // to be rotated (Fix for issue #0027163) or the pen to be in xor mode.
  ADrawer.ResetFont;
  ADrawer.SetXor(false);
  ADrawer.PrepareSimplePen(clBlack);     // resets canvas pen mode to pmCopy
  ADrawer.SetPenParams(psSolid, clDefault);
  ADrawer.SetBrushParams(bsSolid, clWhite);
  ADrawer.SetAntialiasingMode(amDontCare);
end;

procedure TTAChart.DrawBackWall(ADrawer: IChartDrawer);
var
  defaultDrawing: Boolean;
  ic: IChartTCanvasDrawer;
  scaled_depth: Integer;
begin
  defaultDrawing := true;
  if Supports(ADrawer, IChartTCanvasDrawer, ic) and Assigned(OnBeforeDrawBackWall) then
    OnBeforeDrawBackWall(Self, ic.Canvas, FClipRect, defaultDrawing);
  if defaultDrawing then
    with ADrawer do begin
      if HasPolarCoordinates or not FFrame.Visible then
        SetPenParams(psClear, clTAColor)
      else
        Pen := FFrame;
      SetBrushParams(bsSolid, BackColor);
      with FClipRect do
        Rectangle(Left, Top, Right + 1, Bottom + 1);
    end;
  if HasPolarCoordinates then
    DrawPolarGrid(ADrawer);
  if Supports(ADrawer, IChartTCanvasDrawer, ic) and Assigned(OnAfterDrawBackWall) then
    OnAfterDrawBackWall(Self, ic.Canvas, FClipRect);

  // Z axis
  if (Depth > 0) and FFrame.Visible then begin
    scaled_depth := ADrawer.Scale(Depth);
    ADrawer.Pen := FFrame;
    with FClipRect do
      ADrawer.Line(Left, Bottom, Left - scaled_depth, Bottom + scaled_depth);
  end;
end;

procedure TTAChart.DrawLegendOn(ACanvas: TCanvas; var ARect: TRect);
var
  ldd: TChartLegendDrawingData;
begin
  ldd := PrepareLegend(TCanvasDrawer.Create(ACanvas), ARect);
  try
    Legend.Draw(ldd);
  finally
    ldd.FItems.Free;
  end;
end;

procedure TTAChart.DrawLineHoriz(ADrawer: IChartDrawer; AY: Integer);
begin
  if (FClipRect.Top < AY) and (AY < FClipRect.Bottom) then
    ADrawer.Line(FClipRect.Left, AY, FClipRect.Right, AY);
end;

procedure TTAChart.DrawLineVert(ADrawer: IChartDrawer; AX: Integer);
begin
  if (FClipRect.Left < AX) and (AX < FClipRect.Right) then
    ADrawer.Line(AX, FClipRect.Top, AX, FClipRect.Bottom);
end;

procedure TTAChart.DrawOnCanvas(Rect: TRect; ACanvas: TCanvas);
begin
  PaintOnCanvas(ACanvas, Rect);
end;

procedure TTAChart.DrawReticule(ADrawer: IChartDrawer);
begin
  ADrawer.SetXor(true);
  ADrawer.PrepareSimplePen(clTAColor);
  if ReticuleMode in [rmVertical, rmCross] then
    DrawLineVert(ADrawer, FReticulePos.X);
  if ReticuleMode in [rmHorizontal, rmCross] then
    DrawLineHoriz(ADrawer, FReticulePos.Y);
  ADrawer.SetXor(false);
end;

function TTAChart.EffectiveGUIConnector: TChartGUIConnector;
begin
  Result := TChartGUIConnector(
    IfThen(FGUIConnector = nil, FDefaultGUIConnector, FGUIConnector));
end;

procedure TTAChart.EnableRedrawing;
begin
  FDisableRedrawingCounter := FDisableRedrawingCounter - 1;
end;

procedure TTAChart.WMEraseBkgnd(var AMessage: TWMEraseBkgnd);
begin
  // Do not erase, since we will paint over it anyway.
  AMessage.Result := 1;
end;

procedure TTAChart.FindComponentClass(
  AReader: TReader; const AClassName: String; var AClass: TComponentClass);
var
  i: Integer;
begin
  Unused(AReader);
  if AClassName = ClassName then begin
    AClass := TTAChart;
    exit;
  end;
  for i := 0 to SeriesClassRegistry.Count - 1 do begin
    AClass := TSeriesClass(SeriesClassRegistry.GetClass(i));
    if AClass.ClassNameIs(AClassName) then exit;
  end;
  AClass := nil;
end;

function TTAChart.GetAxisBounds(AAxis: TChartAxis): TDoubleInterval;
var
  s: TBasicChartSeries;
  mn, mx: Double;
begin
  Result.FStart := SafeInfinity;
  Result.FEnd := NegInfinity;
  for s in Series do
    if s.Active and s.GetAxisBounds(AAxis, mn, mx) then begin
      Result.FStart := Min(Result.FStart, mn);
      Result.FEnd := Max(Result.FEnd, mx);
    end;
end;

function TTAChart.GetAxisByAlign(AAlign: TChartAxisAlignment): TChartAxis;
begin
  if (BidiMode <> bdLeftToRight) then
    case AAlign of
      calLeft: AAlign := calRight;
      calRight: AAlign := calLeft;
    end;
  Result := FAxisList.GetAxisByAlign(AAlign);
end;

function TTAChart.GetChartHeight: Integer;
begin
  Result := FClipRect.Bottom - FClipRect.Top;
end;

function TTAChart.GetChartWidth: Integer;
begin
  Result := FClipRect.Right - FClipRect.Left;
end;

procedure TTAChart.GetChildren(AProc: TGetChildProc; ARoot: TComponent);
var
  s: TBasicChartSeries;
begin
  // FIXME: This is a workaround for issue #16035
  if FSeries = nil then exit;
  for s in Series do
    if s.Owner = ARoot then
      AProc(s);
end;

function TTAChart.GetFullExtent: TDoubleRect;

  procedure SetBounds(
    var ALo, AHi: Double; AMin, AMax: Double; AUseMin, AUseMax: Boolean);
  const
    DEFAULT_WIDTH = 2.0;
  begin
    if AUseMin then ALo := AMin;
    if AUseMax then AHi := AMax;
    case CASE_OF_TWO[IsInfinite(ALo), IsInfinite(AHi)] of
      cotNone: begin // Both high and low boundary defined
        if ALo = AHi then begin
          ALo := ALo - (DEFAULT_WIDTH / 2);
          AHi := AHi + (DEFAULT_WIDTH / 2);
        end
        else begin
          EnsureOrder(ALo, AHi);
          // Expand view slightly to avoid data points on the chart edge.
          ExpandRange(ALo, AHi, ExpandPercentage * PERCENT);
        end;
      end;
      cotFirst: ALo := AHi - DEFAULT_WIDTH;
      cotSecond: AHi := ALo + DEFAULT_WIDTH;
      cotBoth: begin // No boundaries defined, take some arbitrary values
        ALo := -DEFAULT_WIDTH / 2;
        AHi := DEFAULT_WIDTH / 2;
      end;
    end;
  end;

  procedure JoinBounds(const ABounds: TDoubleRect);
  begin
    with Result do begin
      a.X := Min(a.X, ABounds.a.X);
      b.X := Max(b.X, ABounds.b.X);
      a.Y := Min(a.Y, ABounds.a.Y);
      b.Y := Max(b.Y, ABounds.b.Y);
    end;
  end;

var
  axisBounds: TDoubleRect;
  s: TBasicChartSeries;
  a: TChartAxis;
begin
  Extent.CheckBoundsOrder;

  for a in AxisList do
    if a.Transformations <> nil then
      a.Transformations.ClearBounds;

  Result := EmptyExtent;
  for s in Series do begin
    if not s.Active then continue;
    try
      JoinBounds(s.GetGraphBounds);
    except
      s.Active := false;
      raise;
    end;
  end;
  for a in AxisList do begin
    axisBounds := EmptyExtent;
    if a.Range.UseMin then
      TDoublePointBoolArr(axisBounds.a)[a.IsVertical] :=
        a.GetTransform.AxisToGraph(a.Range.Min);
    if a.Range.UseMax then
      TDoublePointBoolArr(axisBounds.b)[a.IsVertical] :=
        a.GetTransform.AxisToGraph(a.Range.Max);
    JoinBounds(axisBounds);
  end;
  with Extent do begin
    SetBounds(Result.a.X, Result.b.X, XMin, XMax, UseXMin, UseXMax);
    SetBounds(Result.a.Y, Result.b.Y, YMin, YMax, UseYMin, UseYMax);
  end;
  if HasPolarCoordinates then
    Result := PolarSquareExtent(Result);
end;

function TTAChart.GetLegendItems(AIncludeHidden: Boolean): TChartLegendItems;
var
  s: TBasicChartSeries;
begin
  Result := TChartLegendItems.Create;
  try
    for s in Series do
      if AIncludeHidden or (s.Active and s.GetShowInLegend) then
        try
          s.GetLegendItemsBasic(Result);
        except
          s.SetShowInLegend(AIncludeHidden);
          raise;
        end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function TTAChart.GetMargins(ADrawer: IChartDrawer): TRect;
var
  i: Integer;
  a: TRectArray absolute Result;
  s: TBasicChartSeries;
begin
  Result := ZeroRect;
  for s in Series do
    if s.Active then
      s.UpdateMargins(ADrawer, Result);
  for i := Low(a) to High(a) do
    a[i] := ADrawer.Scale(a[i] + TRectArray(Margins.Data)[i]);
end;

function TTAChart.GetRenderingParams: TChartRenderingParams;
begin
  Result.FScale := FScale;
  Result.FOffset := FOffset;
  Result.FClipRect := FClipRect;
  Result.FLogicalExtent := FLogicalExtent;
  Result.FPrevLogicalExtent := FPrevLogicalExtent;
  Result.FIsZoomed := FIsZoomed;
end;

function TTAChart.GetSeriesCount: Integer;
begin
  Result := FSeries.FList.Count;
end;

function TTAChart.GetToolset: TBasicChartToolset;
begin
  Result := FToolset;
  if Result = nil then
    Result := FBuiltinToolset;
end;

function TTAChart.GraphToImage(const AGraphPoint: TDoublePoint): TPoint;
begin
  Result := Point(XGraphToImage(AGraphPoint.X), YGraphToImage(AGraphPoint.Y));
end;

procedure TTAChart.HideReticule;
begin
  // Hide reticule - - it will be drawn again in the next MouseMove.
  FReticulePos := Point( - 1, - 1);
end;

function TTAChart.HasPolarCoordinates: Boolean;
var
  s: TBasicChartSeries;
begin
  for s in Series do
    if s.Active and s.UsesPolarCoordinates then
      Exit(True);
  Result := False;
end;

function TTAChart.PolarSquareExtent(const AExtent: TDoubleRect): TDoubleRect;
var
  r: Double;
begin
  r := 0;
  if not IsInfinite(AExtent.a.X) then
    r := Max(r, Abs(AExtent.a.X));
  if not IsInfinite(AExtent.b.X) then
    r := Max(r, Abs(AExtent.b.X));
  if not IsInfinite(AExtent.a.Y) then
    r := Max(r, Abs(AExtent.a.Y));
  if not IsInfinite(AExtent.b.Y) then
    r := Max(r, Abs(AExtent.b.Y));
  if r <= 0 then
    r := 1;
  r := r * 1.08;
  Result := DoubleRect(-r, -r, r, r);
end;

procedure TTAChart.DrawPolarGrid(ADrawer: IChartDrawer);
const
  CircleCount = 4;
  SpokeCount = 12;
const
  GAP = 4;
var
  origin, p1, p2: TPoint;
  maxR, ringR, angle: Double;
  i: Integer;
  labelText: String;
  sz: TPoint;
begin
  origin := GraphToImage(DoublePoint(0, 0));
  // CalculateTransformationCoeffs forces equal axis scales for polar charts,
  // which widens the visible range of the longer window axis beyond the data
  // extent.  The shorter axis still matches the (square) polar extent, so the
  // outer ring must be sized from the SMALLER of the two visible half-ranges;
  // sizing it from X alone made the grid overflow the window whenever the
  // window was wider than tall (or vice versa).
  maxR := Min(
    Max(Abs(FCurrentExtent.a.X), Abs(FCurrentExtent.b.X)),
    Max(Abs(FCurrentExtent.a.Y), Abs(FCurrentExtent.b.Y)));
  if maxR <= 0 then
    exit;

  ADrawer.SetBrushParams(bsClear, BackColor);
  if (AxisList.Count > 0) and AxisList[0].Grid.Visible then
    ADrawer.Pen := AxisList[0].Grid
  else
    ADrawer.SetPenParams(psDot, clSilver);

  for i := 1 to CircleCount do begin
    ringR := maxR * i / CircleCount;
    // Rings are drawn in graph coordinates on both axes, so they stay
    // consistent with the series data under any axis transformation and
    // always land inside the plot area.
    p1 := GraphToImage(DoublePoint(-ringR, ringR));
    p2 := GraphToImage(DoublePoint(ringR, -ringR));
    ADrawer.Ellipse(p1.X, p1.Y, p2.X, p2.Y);
  end;

  for i := 0 to SpokeCount - 1 do begin
    angle := i * 2 * Pi / SpokeCount;
    ADrawer.Line(origin, GraphToImage(DoublePoint(maxR * Cos(angle), maxR * Sin(angle))));
  end;

  // Angle labels just outside the outer ring, anchored radially so they clear
  // the circle in every direction; PrepareAxis reserved the margin for them.
  PreparePolarLabelFont(ADrawer);
  for i := 0 to SpokeCount - 1 do begin
    angle := i * 2 * Pi / SpokeCount;
    labelText := IntToStr(i * 360 div SpokeCount) + #176;
    sz := ADrawer.TextExtent(labelText);
    p1 := GraphToImage(DoublePoint(maxR * Cos(angle), maxR * Sin(angle)));
    // Push the label box outward along the spoke direction; in image space
    // the y axis points down, hence the sign flip on Sin.
    p1.X := p1.X + Round(Cos(angle) * (GAP + sz.X / 2)) - sz.X div 2;
    p1.Y := p1.Y - Round(Sin(angle) * (GAP + sz.Y / 2)) - sz.Y div 2;
    ADrawer.TextOut.Pos(p1.X, p1.Y).Text(labelText).Done;
  end;

  // Radius values along the upward spoke, next to each ring.
  for i := 1 to CircleCount do begin
    ringR := maxR * i / CircleCount;
    labelText := FloatToStrF(ringR, ffGeneral, 3, 0);
    p1 := GraphToImage(DoublePoint(0, ringR));
    ADrawer.TextOut.Pos(p1.X + 3, p1.Y).Text(labelText).Done;
  end;
end;

procedure TTAChart.PreparePolarLabelFont(ADrawer: IChartDrawer);
begin
  if AxisList.Count > 0 then
    ADrawer.Font := AxisList[0].Marks.LabelFont
  else
    ADrawer.Font := FTitle.Font;
end;

procedure TTAChart.DrawDesignFrame(ADrawer: IChartDrawer; const ARect: TRect);

  procedure Edge(AColor: TChartColor; AX1, AY1, AX2, AY2: Integer);
  begin
    ADrawer.SetPenParams(psSolid, ColorToRGB(AColor));
    ADrawer.Line(AX1, AY1, AX2, AY2);
  end;

begin
  // Raised-panel bevel, drawn only at design time to mirror the classic
  // TeeChart appearance in the form designer.
  with ARect do begin
    Edge(clBtnHighlight, Left, Bottom - 2, Left, Top);              // outer left
    Edge(clBtnHighlight, Left, Top, Right - 1, Top);                // outer top
    Edge(cl3DDkShadow, Right - 1, Top, Right - 1, Bottom - 1);      // outer right
    Edge(cl3DDkShadow, Right - 1, Bottom - 1, Left, Bottom - 1);    // outer bottom
    Edge(cl3DLight, Left + 1, Bottom - 3, Left + 1, Top + 1);       // inner left
    Edge(cl3DLight, Left + 1, Top + 1, Right - 2, Top + 1);         // inner top
    Edge(clBtnShadow, Right - 2, Top + 1, Right - 2, Bottom - 2);   // inner right
    Edge(clBtnShadow, Right - 2, Bottom - 2, Left + 1, Bottom - 2); // inner bottom
  end;
end;

function TTAChart.ImageToGraph(const APoint: TPoint): TDoublePoint;
begin
  Result.X := XImageToGraph(APoint.X);
  Result.Y := YImageToGraph(APoint.Y);
end;

function TTAChart.IsPointInViewPort(const AP: TDoublePoint): Boolean;
begin
  Result :=
    not IsNan(AP) and
    InRange(AP.X, XGraphMin, XGraphMax) and InRange(AP.Y, YGraphMin, YGraphMax);
end;

procedure TTAChart.KeyDown(var AKey: Word; AShift: TShiftState);
var
  p: TPoint;
  ts: TBasicChartToolset;
begin
  p := ScreenToClient(Mouse.CursorPos);
  ts := GetToolset;
  if Assigned(ts) and ts.Dispatch(Self, evidKeyDown, AShift, p) then exit;
  inherited;
end;

procedure TTAChart.KeyUp(var AKey: Word; AShift: TShiftState);
var
  p: TPoint;
  ts: TBasicChartToolset;
begin
  p := ScreenToClient(Mouse.CursorPos);
  // To find a tool, toolset must see the shift state with the key still down.
  case AKey of
    VK_CONTROL: AShift := AShift + [ssCtrl];
    VK_MENU: AShift := AShift + [ssAlt];
    VK_SHIFT: AShift := AShift + [ssShift];
  end;
  ts := GetToolset;
  if Assigned(ts) and ts.Dispatch(Self, evidKeyUp, AShift, p) then exit;
  inherited;
end;

procedure TTAChart.MouseDown(
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  ts: TBasicChartToolset;
begin
  ts := GetToolset;
  if
    PtInRect(FClipRect, Point(X, Y)) and
    Assigned(ts) and ts.Dispatch(Self, evidMouseDown, Shift, Point(X, Y))
  then
    exit;
  inherited;
end;

procedure TTAChart.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  ts: TBasicChartToolset;
begin
  if AutoFocus then
    SetFocus;
  ts := GetToolset;
  if Assigned(ts) and ts.Dispatch(Self, evidMouseMove, Shift, Point(X, Y)) then exit;
  inherited;
end;

procedure TTAChart.MouseUp(
  AButton: TMouseButton; AShift: TShiftState; AX, AY: Integer);
const
  // Delphi's TShiftState has no named element type, so the table holds sets.
  MOUSE_BUTTON_TO_SHIFT: array [TMouseButton] of TShiftState = (
    [ssLeft], [ssRight], [ssMiddle]);
var
  ts: TBasicChartToolset;
begin
  // To find a tool, toolset must see the shift state with the button still down.
  AShift := AShift + MOUSE_BUTTON_TO_SHIFT[AButton];
  ts := GetToolset;
  if Assigned(ts) and ts.Dispatch(Self, evidMouseUp, AShift, Point(AX, AY)) then exit;
  inherited;
end;

procedure TTAChart.Notification(AComponent: TComponent; AOperation: TOperation);
var
  ax: TChartAxis;
begin
  if (AOperation = opRemove) and (AComponent = Toolset) then
    FToolset := nil
  else if (AOperation = opRemove) and (AComponent = GUIConnector) then
    GUIConnector := nil
  else if (AOperation = opRemove) and (AComponent is TChartStyles) then begin
    for ax in FAxisList do
      if ax.Marks.Stripes = AComponent then
        ax.Marks.Stripes := nil;
  end;

  inherited Notification(AComponent, AOperation);
end;

{ Notifies the chart of something which is specified by ACommand and both
  parameters. Needed for example by the axis to query the extent covered by
  all series using this axis (cannot be called directly because TAChartAxis
  does not "use" TACustomSeries. }
procedure TTAChart.Notify(ACommand: Integer; AParam1, AParam2: Pointer; var AData);
begin
  UnUsed(AParam2);
  case ACommand of
    CMD_QUERY_SERIESEXTENT:
      TDoubleInterval(AData) := GetAxisBounds(TChartAxis(AParam1));
  end;
end;

procedure TTAChart.Paint;
var
  defaultDrawing: Boolean;
begin
  defaultDrawing := true;
  FConnectorData.FBounds := GetClientRect;
  {$WARNINGS OFF}
  if Assigned(OnChartPaint) then
    OnChartPaint(Self, FConnectorData.FBounds, defaultDrawing);
  {$WARNINGS ON}
  if defaultDrawing then
    with EffectiveGUIConnector do begin
      SetBounds(FConnectorData);
      Draw(Drawer, FConnectorData.FDrawerBounds);
      EffectiveGUIConnector.Display(FConnectorData);
  end;
  if Assigned(OnAfterPaint) then
    OnAfterPaint(Self);
end;

procedure TTAChart.PaintOnAuxCanvas(ACanvas: TCanvas; ARect: TRect);
var
  rp: TChartRenderingParams;
begin
  rp := RenderingParams;
  ExtentBroadcaster.Locked := true;
  try
    FIsZoomed := false;
    PaintOnCanvas(ACanvas, ARect);
  finally
    RenderingParams := rp;
    ExtentBroadcaster.Locked := false;
  end;
end;

procedure TTAChart.PaintOnCanvas(ACanvas: TCanvas; ARect: TRect);
begin
  Draw(TCanvasDrawer.Create(ACanvas), ARect);
end;

procedure TTAChart.PrepareAxis(ADrawer: IChartDrawer);
var
  axisMargin: TChartAxisMargins;
  aa: TChartAxisAlignment;
  cr: TRect;
  tries: Integer;
  prevExt: TDoubleRect;
  axis: TChartAxis;
  scaled_depth: Integer;
begin
  scaled_depth := ADrawer.Scale(Depth);
  if not AxisVisible or HasPolarCoordinates then begin
    FClipRect.Left := FClipRect.Left + scaled_depth;
    FClipRect.Bottom := FClipRect.Bottom - scaled_depth;
    if HasPolarCoordinates then begin
      // Reserve room around the plot area for the angle labels that
      // DrawPolarGrid places outside the outer ring.
      PreparePolarLabelFont(ADrawer);
      with ADrawer.TextExtent('330' + #176) do begin
        FClipRect.Left := FClipRect.Left + X + ADrawer.Scale(4);
        FClipRect.Right := FClipRect.Right - X - ADrawer.Scale(4);
        FClipRect.Top := FClipRect.Top + Y + ADrawer.Scale(4);
        FClipRect.Bottom := FClipRect.Bottom - Y - ADrawer.Scale(4);
      end;
    end;
    CalculateTransformationCoeffs(GetMargins(ADrawer));
    exit;
  end;

  AxisList.PrepareGroups;
  for axis in AxisList do
    axis.PrepareHelper(ADrawer, XGraphToImage, YGraphToImage, @FClipRect, scaled_depth);

  // There is a cyclic dependency: extent -> visible marks -> margins.
  // We recalculate them iteratively hoping that the process converges.
  CalculateTransformationCoeffs(ZeroRect);
  cr := FClipRect;
  for tries := 1 to 10 do begin
    axisMargin := AxisList.Measure(CurrentExtent, scaled_depth);
    axisMargin[calLeft] := Max(axisMargin[calLeft], scaled_depth);
    axisMargin[calBottom] := Max(axisMargin[calBottom], scaled_depth);
    FClipRect := cr;
    for aa := Low(aa) to High(aa) do
      SideByAlignment(FClipRect, aa, -axisMargin[aa]);
    prevExt := FCurrentExtent;
    FCurrentExtent := FLogicalExtent;
    CalculateTransformationCoeffs(GetMargins(ADrawer));
    if prevExt = FCurrentExtent then break;
    prevExt := FCurrentExtent;
  end;

  AxisList.Prepare(FClipRect);
end;

procedure TTAChart.Prepare;
var
  a: TChartAxis;
  s: TBasicChartSeries;
begin
  for a in AxisList do
    if a.Transformations <> nil then
      a.Transformations.SetChart(Self);
  for s in Series do
    s.BeforeDraw;

  if not FIsZoomed then
    FLogicalExtent := GetFullExtent;
  FCurrentExtent := FLogicalExtent;
end;

function TTAChart.PrepareLegend(
  ADrawer: IChartDrawer; var AClipRect: TRect): TChartLegendDrawingData;
begin
  Result.FDrawer := ADrawer;
  Result.FItems := GetLegendItems;
  try
    Legend.SortItemsByOrder(Result.FItems);
    Legend.AddGroups(Result.FItems);
    Legend.Prepare(Result, AClipRect);
  except
    FreeAndNil(Result.FItems);
    raise;
  end;
end;

procedure TTAChart.RemoveSeries(ASeries: TBasicChartSeries);
begin
  DeleteSeries(ASeries);
end;

procedure TTAChart.SaveToBitmapFile(const AFileName: String);
begin
  SaveToFile(TBitmap, AFileName);
end;

procedure TTAChart.SaveToFile(AClass: TGraphicClass; AFileName: String);
begin
  with SaveToImage(AClass) do
    try
      SaveToFile(AFileName);
    finally
      Free;
    end;
end;

function TTAChart.SaveToImage(AClass: TGraphicClass): TGraphic;
var
  bmp: TBitmap;
begin
  // Only TBitmap offers a canvas to paint on, so the chart is always rendered
  // into a bitmap first and then converted to the requested graphic class
  // (TPngImage, TJPEGImage, ...).
  Result := AClass.Create;
  try
    bmp := TBitmap.Create;
    try
      bmp.SetSize(Width, Height);
      PaintOnCanvas(bmp.Canvas, Rect(0, 0, Width, Height));
      if Result is TBitmap then
        TBitmap(Result).Assign(bmp)
      else
        Result.Assign(bmp);
    finally
      bmp.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TTAChart.SetAntialiasingMode(AValue: TChartAntialiasingMode);
begin
  if FAntialiasingMode = AValue then exit;
  FAntialiasingMode := AValue;
  StyleChanged(Self);
end;

procedure TTAChart.SetAxisByAlign(AAlign: TChartAxisAlignment; AValue: TChartAxis);
begin
  FAxisList.SetAxisByAlign(AAlign, AValue);
  StyleChanged(AValue);
end;

procedure TTAChart.SetAxisList(AValue: TChartAxisList);
begin
  FAxisList.Assign(AValue);
  StyleChanged(Self);
end;

procedure TTAChart.SetAxisVisible(Value: Boolean);
begin
  FAxisVisible := Value;
  StyleChanged(Self);
end;

procedure TTAChart.SetBackColor(AValue: TColor);
begin
  FBackColor:= AValue;
  StyleChanged(Self);
end;

procedure TTAChart.SetBiDiMode(AValue: TBiDiMode);
begin
  if AValue = BidiMode then
    exit;
  inherited SetBiDiMode(AValue);
  if not (csLoading in ComponentState) then begin
    AxisList.UpdateBidiMode;
    Legend.UpdateBidiMode;
    Title.UpdateBidiMode;
    Foot.UpdateBidiMode;
    Series.UpdateBiDiMode;
  end;
end;

procedure TTAChart.SetChildOrder(Child: TComponent; Order: Integer);
var
  i: Integer;
begin
  i := Series.FList.IndexOf(Child);
  if i >= 0 then
    Series.FList.Move(i, Order);
end;

procedure TTAChart.SetDepth(AValue: TChartDistance);
begin
  if FDepth = AValue then exit;
  FDepth := AValue;
  StyleChanged(Self);
end;

procedure TTAChart.SetExpandPercentage(AValue: Integer);
begin
  if FExpandPercentage = AValue then exit;
  FExpandPercentage := AValue;
  StyleChanged(Self);
end;

procedure TTAChart.SetExtent(AValue: TChartExtent);
begin
  FExtent.Assign(AValue);
  StyleChanged(Self);
end;

procedure TTAChart.SetExtentSizeLimit(AValue: TChartExtent);
begin
  if FExtentSizeLimit = AValue then exit;
  FExtentSizeLimit.Assign(AValue);
  StyleChanged(Self);
end;

procedure TTAChart.SetFoot(Value: TChartTitle);
begin
  FFoot.Assign(Value);
  StyleChanged(Self);
end;

procedure TTAChart.SetFrame(Value: TChartPen);
begin
  FFrame.Assign(Value);
  StyleChanged(Self);
end;

procedure TTAChart.SetGUIConnector(AValue: TChartGUIConnector);
begin
  if FGUIConnector = AValue then exit;
  if FGUIConnector <> nil then
    RemoveFreeNotification(FGUIConnector);
  if FGUIConnectorListener.IsListening then
    FGUIConnector.Broadcaster.Unsubscribe(FGUIConnectorListener);
  FGUIConnector := AValue;
  if FGUIConnector <> nil then begin
    FGUIConnector.Broadcaster.Subscribe(FGUIConnectorListener);
    FreeNotification(FGUIConnector);
  end;
  EffectiveGUIConnector.CreateDrawer(FConnectorData);
  StyleChanged(Self);
end;

procedure TTAChart.SetLegend(Value: TChartLegend);
begin
  FLegend.Assign(Value);
  StyleChanged(Self);
end;

procedure TTAChart.SetLogicalExtent(const AValue: TDoubleRect);
var
  w, h: Double;
begin
  if FLogicalExtent = AValue then exit;
  w := Abs(AValue.a.X - AValue.b.X);
  h := Abs(AValue.a.Y - AValue.b.Y);
  with ExtentSizeLimit do
    if
      UseXMin and (w < XMin) or UseXMax and (w > XMax) or
      UseYMin and (h < YMin) or UseYMax and (h > YMax)
    then
      exit;
  HideReticule;
  FLogicalExtent := AValue;
  FIsZoomed := true;
  StyleChanged(Self);
end;

procedure TTAChart.SetMargins(AValue: TChartMargins);
begin
  FMargins.Assign(AValue);
  StyleChanged(Self);
end;

procedure TTAChart.SetMarginsExternal(AValue: TChartMargins);
begin
  if FMarginsExternal = AValue then exit;
  FMarginsExternal.Assign(AValue);
  StyleChanged(Self);
end;

procedure TTAChart.SetName(const AValue: TComponentName);
var
  oldName: String;
begin
  if Name = AValue then exit;
  oldName := Name;
  inherited SetName(AValue);
  if csDesigning in ComponentState then
    Series.List.ChangeNamePrefix(oldName, AValue);
end;

procedure TTAChart.SetOnAfterDraw(AValue: TChartDrawEvent);
begin
  if TMethod(FOnAfterDraw) = TMethod(AValue) then exit;
  FOnAfterDraw := AValue;
  StyleChanged(Self);
end;

procedure TTAChart.SetOnAfterDrawBackground(AValue: TChartAfterDrawEvent);
begin
  if TMethod(FOnAfterDrawBackground) = TMEthod(AValue) then exit;
  FOnAfterDrawBackground := AValue;
  StyleChanged(Self);
end;

procedure TTAChart.SetOnAfterDrawBackWall(AValue: TChartAfterDrawEvent);
begin
  if TMethod(FOnAfterDrawBackWall) = TMethod(AValue) then exit;
  FOnAfterDrawBackWall := AValue;
  StyleChanged(Self);
end;

procedure TTAChart.SetOnBeforeDrawBackground(AValue: TChartBeforeDrawEvent);
begin
  if TMethod(FOnBeforeDrawBackground) = TMethod(AValue) then exit;
  FOnBeforeDrawBackground := AValue;
  StyleChanged(Self);
end;

procedure TTAChart.SetOnBeforeDrawBackWall(AValue: TChartBeforeDrawEvent);
begin
  if TMethod(FOnBeforeDrawBackWall) = TMethod(AValue) then exit;
  FOnBeforeDrawBackWall := AValue;
  StyleChanged(Self);
end;

procedure TTAChart.SetOnChartPaint(AValue: TChartPaintEvent);
begin
  if TMethod(FOnChartPaint) = TMethod(AValue) then exit;
  FOnChartPaint := AValue;
  StyleChanged(Self);
end;

procedure TTAChart.SetOnDrawLegend(AValue: TChartDrawLegendEvent);
begin
  if TMethod(FOnDrawLegend) = TMethod(AValue) then exit;
  FOnDrawLegend := AValue;
  StyleChanged(self);
end;

procedure TTAChart.SetOnDrawReticule(AValue: TDrawReticuleEvent);
begin
  if TMethod(FOnDrawReticule) = TMethod(AValue) then exit;
  FOnDrawReticule := AValue;
  StyleChanged(Self);
end;

procedure TTAChart.SetProportional(AValue: Boolean);
begin
  if FProportional = AValue then exit;
  FProportional := AValue;
  StyleChanged(Self);
end;

procedure TTAChart.SetRenderingParams(AValue: TChartRenderingParams);
begin
  FScale := AValue.FScale;
  FOffset := AValue.FOffset;
  FClipRect := AValue.FClipRect;
  FLogicalExtent := AValue.FLogicalExtent;
  FPrevLogicalExtent := AValue.FPrevLogicalExtent;
  FIsZoomed := AValue.FIsZoomed;
end;

procedure TTAChart.SetReticuleMode(AValue: TReticuleMode);
begin
  if FReticuleMode = AValue then exit;
  FReticuleMode := AValue;
  StyleChanged(Self);
end;

procedure TTAChart.SetReticulePos(const AValue: TPoint);
begin
  if FReticulePos = AValue then exit;
  DrawReticule(Drawer);
  FReticulePos := AValue;
  DrawReticule(Drawer);
end;

procedure TTAChart.SetTitle(Value: TChartTitle);
begin
  FTitle.Assign(Value);
  StyleChanged(Self);
end;

procedure TTAChart.SetToolset(AValue: TBasicChartToolset);
begin
  if FToolset = AValue then exit;
  if FToolset <> nil then
    RemoveFreeNotification(FToolset);
  FToolset := AValue;
  FActiveToolIndex := -1;
  if FToolset <> nil then
    FreeNotification(FToolset);
end;

procedure TTAChart.StyleChanged(Sender: TObject);
begin
  if FDisableRedrawingCounter > 0 then exit;
  if Sender is TChartExtent then
    ZoomFull;
  Invalidate;
  Broadcaster.Broadcast(Sender);
end;

procedure TTAChart.VisitSources(
  AVisitor: TChartOnSourceVisitor; AAxis: TChartAxis; var AData);
var
  s: TBasicChartSeries;
begin
  for s in Series do
    if s.Active then
      s.VisitSources(AVisitor, AAxis, AData);
end;

function TTAChart.XGraphToImage(AX: Double): Integer;
begin
  Result := RoundChecked(FScale.X * AX + FOffset.X);
end;

function TTAChart.XImageToGraph(AX: Integer): Double;
begin
  Result := (AX - FOffset.X) / FScale.X;
end;

function TTAChart.YGraphToImage(AY: Double): Integer;
begin
  Result := RoundChecked(FScale.Y * AY + FOffset.Y);
end;

function TTAChart.YImageToGraph(AY: Integer): Double;
begin
  Result := (AY - FOffset.Y) / FScale.Y;
end;

procedure TTAChart.ZoomFull(AImmediateRecalc: Boolean);
begin
  if AImmediateRecalc then
    FLogicalExtent := GetFullExtent;
  if not FIsZoomed then exit;
  HideReticule;
  FIsZoomed := false;
  Invalidate;
end;

{ TBasicChartSeries }

procedure TBasicChartSeries.AfterDraw;
begin
  // empty
end;

procedure TBasicChartSeries.Assign(Source: TPersistent);
begin
  if Source is TBasicChartSeries then
    with TBasicChartSeries(Source) do begin
      Self.FActive := FActive;
      Self.FDepth := FDepth;
      Self.FZPosition := FZPosition;
    end;
end;

function TBasicChartSeries.AxisToGraphX(AX: Double): Double;
begin
  Result := AX;
end;

function TBasicChartSeries.AxisToGraphY(AY: Double): Double;
begin
  Result := AY;
end;

procedure TBasicChartSeries.BeforeDraw;
begin
  // empty
end;

destructor TBasicChartSeries.Destroy;
begin
  if FChart <> nil then
    FChart.DeleteSeries(Self);
  inherited;
end;

function TBasicChartSeries.GraphToAxisX(AX: Double): Double;
begin
  Result := AX;
end;

function TBasicChartSeries.GraphToAxisY(AY: Double): Double;
begin
  Result := AY;
end;

function TBasicChartSeries.UsesPolarCoordinates: Boolean;
begin
  Result := false;
end;

procedure TBasicChartSeries.MovePoint(
  var AIndex: Integer; const ANewPos: TDoublePoint);
begin
  Unused(AIndex, ANewPos)
end;

procedure TBasicChartSeries.MovePoint(
  var AIndex: Integer; const ANewPos: TPoint);
begin
  MovePoint(AIndex, FChart.ImageToGraph(ANewPos));
end;

procedure TBasicChartSeries.MovePointEx(
  var AIndex: Integer; AXIndex, AYIndex: Integer; const ANewPos: TDoublePoint);
begin
  Unused(AXIndex, AYIndex);
  MovePoint(AIndex, ANewPos);
end;

procedure TBasicChartSeries.UpdateBiDiMode;
begin
  // normally nothing to do. Override, e.g., to flip arrows
end;

procedure TBasicChartSeries.UpdateMargins(
  ADrawer: IChartDrawer; var AMargins: TRect);
begin
  Unused(ADrawer, AMargins);
end;

procedure TBasicChartSeries.VisitSources(
  AVisitor: TChartOnSourceVisitor; AAxis: TChartAxis; var AData);
begin
  Unused(AVisitor, AAxis);
  Unused(AData);
end;

{ TChartSeriesList }

procedure TChartSeriesList.Clear;
var
  i: Integer;
begin
  if FList.Count > 0 then
    Items[0].FChart.StyleChanged(Items[0].FChart);
  for i := 0 to FList.Count - 1 do begin
    Items[i].FChart := nil;
    Items[i].Free;
  end;
  FList.Clear;
end;

function TChartSeriesList.Count: Integer;
begin
  Result := FList.Count;
end;

constructor TChartSeriesList.Create;
begin
  FList := TIndexedComponentList.Create;
end;

destructor TChartSeriesList.Destroy;
begin
  Clear;
  FreeAndNil(FList);
  inherited;
end;

function TChartSeriesList.GetEnumerator: TBasicChartSeriesEnumerator;
begin
  Result := TBasicChartSeriesEnumerator.Create(FList);
end;

function TChartSeriesList.GetItem(AIndex: Integer): TBasicChartSeries;
begin
  Result := TBasicChartSeries(FList.Items[AIndex]);
end;

procedure TChartSeriesList.UpdateBiDiMode;
var
  s: TBasicChartseries;
begin
  for s in self do
    s.UpdateBiDiMode;
end;

{ TBasicChartTool }

procedure TBasicChartTool.Activate;
begin
  FChart.FActiveToolIndex := Index;
  FChart.MouseCapture := true;
  FChart.FDisablePopupMenu := false;
  FStartMousePos := Mouse.CursorPos;
end;

procedure TBasicChartTool.Deactivate;
begin
  FChart.MouseCapture := false;
  FChart.FActiveToolIndex := -1;
  if PopupMenuConflict then
    FChart.FDisablePopupMenu := true;
end;

function TBasicChartTool.PopupMenuConflict: Boolean;
begin
  Result := false;
end;


initialization
  EnsureSeriesClassRegistry;
  ShowMessageProc := @ShowMessage;
  // Runtime DFM streaming (especially C++Builder) does not run RegisterComponents.
  // Without this, removing the last published TTAChart pointer makes the linker
  // drop TAGraph and the next form load reports "Class TTAChart not found."
  // Series, tools, sources and the rest are registered in TAChartRegistration,
  // which is contained in TAChartRT so the BPL initializes it on load.
  Classes.RegisterClass(TTAChart);

finalization
  FreeAndNil(SeriesClassRegistry);

end.
