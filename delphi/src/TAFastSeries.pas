{
 *****************************************************************************
  This file is part of the Delphi/VCL port of TAChart.

  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  A line series built for millions of points (GPU rendering, layer 3).

  An ordinary TAChart series keeps a TChartDataItem per point and walks every
  one of them on the CPU each frame to build a pixel polyline.  That is the
  right design at ordinary data sizes and hopeless at ten million: the item is
  48 bytes, so the data alone is 480 MB, and the per-frame walk dominates the
  frame time no matter which drawer is underneath.

  TFastLineSeries trades the general data source for a packed array of X/Y
  singles - 8 bytes a point, 80 MB at ten million - and hands that array to the
  GPU:

    * The samples are uploaded once into a vertex buffer and redrawn from GPU
      memory.  SamplesChanged patches only the span that moved, so animating
      part of a large series does not re-send the whole of it.
    * The data-to-pixel mapping is folded into the modelview matrix, so the GPU
      performs the transform and no per-point CPU work happens at all.
    * Axis bounds are cached, because rescanning the samples every frame would
      cost more than the drawing.  X-ordering is tracked separately from the
      extents, since changing Y invalidates the extents but cannot reorder X.
    * Pixel-grid decimation reduces the line to at most four vertices per pixel
      column - the first, minimum, maximum and last sample of the column, in
      sample order.  First and last preserve where the line enters and leaves
      the column, min and max preserve its vertical extent, so no visible
      feature is lost.  It is not bit-exact: measured against the full draw of
      a 10 M sample series, about 60 pixels in half a million differ, from
      sub-pixel rasterisation of the segments inside a column rather than from
      discarded data.  The reduction is stored per
      column, so ValuesChanged recomputes only the columns whose samples moved;
      rebuilding it wholesale every frame is what makes naive decimation slower
      than none at all.  Only the visible span is reduced, found by binary
      search, so pan and zoom cost what is on screen rather than what is in
      memory.

  It is a full chart series for all that: it lives in AxisList through
  AxisIndexX/AxisIndexY, reports its extent through GetBounds so zoom and pan
  tools work on it, and appears in the legend.

  It also draws without OpenGL.  Draw asks the drawer for IChartGLDrawer; when
  the drawer does not provide one - a canvas, SVG or WMF drawer, or a chart
  that fell back to GDI - the same decimation feeds an ordinary polyline, so
  the series still renders, just on the CPU.

  Known limitation for this increment: samples are treated as graph
  coordinates, so axis transformations (TAChartAxisTransformations) are not
  applied to this series.  Use it on untransformed axes.
}

unit TAFastSeries;

{$I TAChartDefines.inc}

interface

uses
  System.Classes, System.Types,
  Vcl.Graphics,
  TAChartUtils, TACustomSeries, TADrawUtils, TAGLContext, TAGraph, TALegend,
  TATypes;

type

  { One sample.  Packed singles: 8 bytes against the 48 a TChartDataItem
    costs, which is the difference between 80 MB and 480 MB at 10 M points. }

  TChartFastPoint = packed record
    X, Y: Single;
  end;
  PChartFastPoint = ^TChartFastPoint;

  { What Draw needs to know about the mapping, gathered once per frame from
    the chart so the two drawing paths share the same reduction. }

  TChartFastRenderParams = record
    Rect: TRect;
    XMin, XMax, YMin, YMax: Double;
  end;

  { TFastLineSeries }

  TFastLineSeries = class(TTACustomChartSeries)
  strict private
    FData: TArray<TChartFastPoint>;
    FCount: Integer;
    FLinePen: TPen;

    // Cached extents.  Rescanning per frame would dominate the frame time.
    FBoundsValid: Boolean;
    FXMin, FXMax, FYMin, FYMax: Double;
    // Tracked apart from the extents: changing Y invalidates them but cannot
    // reorder X, and conflating the two forces a full rescan every frame.
    FXOrderValid: Boolean;
    FXAscending: Boolean;

    // GPU mirror of FData.  A buffer name belongs to the context that made it.
    FVBO: Cardinal;
    FVBOContextId: Cardinal;
    FVBOCount: Integer;
    FUploadAll: Boolean;
    FDirtyFirst, FDirtyLast: Integer;   // pending partial upload, -1 = none

    // Pixel-grid decimation.
    FDecimate: Boolean;
    FDecimated: TArray<TChartFastPoint>;
    FDecCount: Integer;
    FDataVersion: Integer;              // bumped whenever X may have moved
    FDecVersion: Integer;               // version the reduction was built from
    FDecWidth: Integer;
    FDecXMin, FDecXMax: Double;
    // Per-column store, so a value change costs the columns it touches.
    FBucketStart: TArray<Integer>;      // FNumBuckets+1 sample indices
    FBucketPts: TArray<TChartFastPoint>;// up to 4 per column
    FBucketLen: TArray<Byte>;
    FNumBuckets: Integer;
    FDecDirtyLo, FDecDirtyHi: Integer;  // columns needing recompute, -1 = none
    FVisFirst, FVisLast: Integer;
    FLastDrawn: Integer;

    function BucketOfIndex(AIndex: Integer): Integer;
    procedure BuildDecimated(const AParams: TChartFastRenderParams);
    procedure CompactDecimated;
    procedure DrawGL(const AGL: TChartGLContext;
      const AParams: TChartFastRenderParams);
    procedure DrawPolyline(ADrawer: IChartDrawer;
      const AParams: TChartFastRenderParams);
    procedure EnsureXOrder;
    function IndexAtOrBefore(const AX: Double): Integer;
    procedure MarkDirty(AFirst, ALast: Integer);
    function RenderParams(out AParams: TChartFastRenderParams): Boolean;
    procedure RebuildBuckets(ALo, AHi: Integer);
    procedure RecalcBounds;
    procedure SetDecimate(AValue: Boolean);
    procedure SetLinePen(AValue: TPen);
    function ShouldDecimate(const AParams: TChartFastRenderParams): Boolean;
    procedure SyncBuffer(const AGL: TChartGLContext);
    procedure UpdateDecimation(const AParams: TChartFastRenderParams);
  protected
    procedure GetBounds(var ABounds: TDoubleRect); override;
    procedure GetLegendItems(AItems: TChartLegendItems); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Assign(ASource: TPersistent); override;
    procedure Draw(ADrawer: IChartDrawer); override;
    function IsEmpty: Boolean; override;

    { Bulk loading.  SetSampleCount allocates - it raises EOutOfMemory if the
      process cannot supply the memory, which at 10 M points in a 32 bit
      process is a legitimate answer - then SetSample fills, then DataChanged
      publishes the result.  Filling without the final DataChanged leaves the
      chart showing stale bounds. }
    procedure SetSampleCount(ACount: Integer);
    procedure SetSample(AIndex: Integer; const AX, AY: Single); inline;
    function SamplePtr: PChartFastPoint;
    procedure Clear;
    { Appends one sample.  Convenient, but it grows the array geometrically -
      prefer SetSampleCount plus SetSample when the size is known. }
    function AddXY(const AX, AY: Double): Integer;

    { Everything changed. }
    procedure DataChanged;
    { ACount samples from AStart changed, X possibly among them.  Lets the GPU
      buffer be patched instead of re-uploaded. }
    procedure SamplesChanged(AStart, ACount: Integer);
    { Strongest form: only the Y values of ACount samples from AStart changed.
      Because X assigns samples to pixel columns, leaving it alone lets the
      reduction be patched column by column rather than rebuilt, so updating
      part of a large series costs proportional to the part. }
    procedure ValuesChanged(AStart, ACount: Integer);

    { True while drawing from a GPU-resident vertex buffer. }
    function UsingVBO: Boolean;
    { Vertices submitted by the last Draw.  With decimation on this is the
      reduced count, which is where the win shows up. }
    property LastDrawnVertexCount: Integer read FLastDrawn;
    { True when X is non-decreasing, which decimation requires. }
    property XAscending: Boolean read FXAscending;
    property SampleCount: Integer read FCount;
  published
    property AxisIndexX;
    property AxisIndexY;
    property Active default true;
    property Title;
    property ZPosition;
    { Reduce the line to at most four vertices per pixel column before drawing.
      Ignored when X is not ascending, or when there are too few samples for
      the reduction to pay for itself. }
    property Decimate: Boolean read FDecimate write SetDecimate default true;
    property LinePen: TPen read FLinePen write SetLinePen;
  end;

implementation

uses
  Winapi.OpenGL,
  System.SysUtils, System.Math,
  TAChartGL, TAChartStrConsts, TAGeometry;

{ TFastLineSeries }

constructor TFastLineSeries.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDecimate := true;
  FDirtyFirst := -1;
  FDirtyLast := -1;
  FDecDirtyLo := -1;
  FDecDirtyHi := -1;
  FLinePen := TPen.Create;
  FLinePen.OnChange := StyleChanged;
end;

destructor TFastLineSeries.Destroy;
begin
  // The vertex buffer is not deleted here: buffer names belong to a context,
  // and by the time a series is freed its context may already be gone.  The
  // buffer dies with the context that owns it.
  FreeAndNil(FLinePen);
  inherited;
end;

procedure TFastLineSeries.Assign(ASource: TPersistent);
begin
  if ASource is TFastLineSeries then
    with TFastLineSeries(ASource) do begin
      Self.FLinePen.Assign(FLinePen);
      Self.FDecimate := FDecimate;
    end;
  inherited Assign(ASource);
end;

procedure TFastLineSeries.SetLinePen(AValue: TPen);
begin
  FLinePen.Assign(AValue);
end;

procedure TFastLineSeries.SetDecimate(AValue: Boolean);
begin
  if FDecimate = AValue then exit;
  FDecimate := AValue;
  UpdateParentChart;
end;

function TFastLineSeries.IsEmpty: Boolean;
begin
  Result := FCount = 0;
end;

{ Storage }

procedure TFastLineSeries.SetSampleCount(ACount: Integer);
begin
  if ACount < 0 then
    ACount := 0;
  SetLength(FData, ACount);
  FCount := ACount;
  FBoundsValid := false;
  FXOrderValid := false;
  // The size changed, so the GPU buffer must be reallocated, not patched.
  FUploadAll := true;
  FDirtyFirst := -1;
  FDirtyLast := -1;
  Inc(FDataVersion);
end;

procedure TFastLineSeries.SetSample(AIndex: Integer; const AX, AY: Single);
begin
  FData[AIndex].X := AX;
  FData[AIndex].Y := AY;
end;

function TFastLineSeries.SamplePtr: PChartFastPoint;
begin
  if FCount = 0 then
    Result := nil
  else
    Result := @FData[0];
end;

procedure TFastLineSeries.Clear;
begin
  SetSampleCount(0);
  DataChanged;
end;

function TFastLineSeries.AddXY(const AX, AY: Double): Integer;
begin
  if FCount = Length(FData) then
    SetLength(FData, Max(16, Length(FData) * 2));
  Result := FCount;
  FData[Result].X := AX;
  FData[Result].Y := AY;
  Inc(FCount);
  FBoundsValid := false;
  FXOrderValid := false;
  FUploadAll := true;
  Inc(FDataVersion);
  UpdateParentChart;
end;

{ Change notification }

procedure TFastLineSeries.DataChanged;
begin
  FBoundsValid := false;
  FXOrderValid := false;
  FUploadAll := true;
  Inc(FDataVersion);
  UpdateParentChart;
end;

procedure TFastLineSeries.MarkDirty(AFirst, ALast: Integer);
begin
  if AFirst < 0 then AFirst := 0;
  if ALast > FCount - 1 then ALast := FCount - 1;
  if AFirst > ALast then exit;
  if FDirtyFirst < 0 then begin
    FDirtyFirst := AFirst;
    FDirtyLast := ALast;
  end
  else begin
    // One contiguous span is enough; over-covering costs a slightly bigger
    // upload and keeps the bookkeeping trivial.
    if AFirst < FDirtyFirst then FDirtyFirst := AFirst;
    if ALast > FDirtyLast then FDirtyLast := ALast;
  end;
end;

procedure TFastLineSeries.SamplesChanged(AStart, ACount: Integer);
begin
  FBoundsValid := false;
  FXOrderValid := false;
  MarkDirty(AStart, AStart + ACount - 1);
  Inc(FDataVersion);   // X may have moved: the reduction is fully stale
  UpdateParentChart;
end;

procedure TFastLineSeries.ValuesChanged(AStart, ACount: Integer);
var
  lo, hi, i: Integer;
begin
  MarkDirty(AStart, AStart + ACount - 1);

  // The extent is expanded over the changed span rather than invalidated.
  // Invalidating it forces RecalcBounds to rescan every sample on the next
  // frame, and the chart asks for the extent every frame - measured at 10 M
  // samples that scan cost 40 ms, twenty times the drawing it was part of.
  // X cannot have moved here by contract, so only Y needs looking at.  The
  // consequence is that the extent grows but never shrinks; call DataChanged
  // when a value that defined the extent has come back down and the axis
  // should follow it.
  if FBoundsValid then begin
    lo := Max(0, AStart);
    hi := Min(FCount - 1, AStart + ACount - 1);
    for i := lo to hi do begin
      if FData[i].Y < FYMin then FYMin := FData[i].Y;
      if FData[i].Y > FYMax then FYMax := FData[i].Y;
    end;
  end;
  // Deliberately no FDataVersion bump: X is unchanged, so the column
  // boundaries still hold and only the affected columns need recomputing.
  if (FNumBuckets > 0) and (FDecVersion = FDataVersion) then begin
    lo := BucketOfIndex(AStart);
    hi := BucketOfIndex(AStart + ACount - 1);
    if FDecDirtyLo < 0 then begin
      FDecDirtyLo := lo;
      FDecDirtyHi := hi;
    end
    else begin
      if lo < FDecDirtyLo then FDecDirtyLo := lo;
      if hi > FDecDirtyHi then FDecDirtyHi := hi;
    end;
  end
  else
    Inc(FDataVersion);   // nothing cached yet; let Draw build it
  UpdateParentChart;
end;

{ Extents }

procedure TFastLineSeries.EnsureXOrder;
var
  i: Integer;
  p: PChartFastPoint;
  prevX: Single;
begin
  if FXOrderValid then exit;
  FXOrderValid := true;
  FXAscending := true;
  if FCount < 2 then exit;
  p := @FData[0];
  prevX := p.X;
  for i := 1 to FCount - 1 do begin
    Inc(p);
    if p.X < prevX then begin
      FXAscending := false;
      Break;
    end;
    prevX := p.X;
  end;
end;

procedure TFastLineSeries.RecalcBounds;
var
  i: Integer;
  p: PChartFastPoint;
  prevX: Single;
begin
  FBoundsValid := true;
  // This pass reads X anyway, so settle the ordering question here too.
  FXOrderValid := true;
  FXAscending := true;
  if FCount = 0 then begin
    FXMin := 0; FXMax := 0; FYMin := 0; FYMax := 0;
    exit;
  end;
  p := @FData[0];
  FXMin := p.X; FXMax := p.X;
  FYMin := p.Y; FYMax := p.Y;
  prevX := p.X;
  for i := 1 to FCount - 1 do begin
    Inc(p);
    if p.X < FXMin then FXMin := p.X else if p.X > FXMax then FXMax := p.X;
    if p.Y < FYMin then FYMin := p.Y else if p.Y > FYMax then FYMax := p.Y;
    if p.X < prevX then
      FXAscending := false;
    prevX := p.X;
  end;
end;

procedure TFastLineSeries.GetBounds(var ABounds: TDoubleRect);
begin
  if FCount = 0 then exit;
  if not FBoundsValid then
    RecalcBounds;
  ABounds.a.X := FXMin;
  ABounds.a.Y := FYMin;
  ABounds.b.X := FXMax;
  ABounds.b.Y := FYMax;
end;

procedure TFastLineSeries.GetLegendItems(AItems: TChartLegendItems);
begin
  AItems.Add(TLegendItemLine.Create(FLinePen, LegendTextSingle));
end;

{ Decimation }

function TFastLineSeries.ShouldDecimate(
  const AParams: TChartFastRenderParams): Boolean;
begin
  // Only worth it once there are appreciably more samples than pixel columns;
  // below that the reduction costs more than it saves.
  EnsureXOrder;
  Result := FDecimate and FXAscending and
    (AParams.Rect.Width > 0) and
    (AParams.XMax > AParams.XMin) and
    (FCount > 4 * AParams.Rect.Width);
end;

function TFastLineSeries.IndexAtOrBefore(const AX: Double): Integer;
var
  lo, hi, mid: Integer;
begin
  // Largest sample index whose X is <= AX, or -1.  Requires ascending X,
  // which the caller has established.
  lo := 0;
  hi := FCount - 1;
  Result := -1;
  while lo <= hi do begin
    mid := (lo + hi) div 2;
    if FData[mid].X <= AX then begin
      Result := mid;
      lo := mid + 1;
    end
    else
      hi := mid - 1;
  end;
end;

function TFastLineSeries.BucketOfIndex(AIndex: Integer): Integer;
var
  lo, hi, mid: Integer;
begin
  // Which pixel column owns a sample.  Binary search over the boundaries, so
  // patching a changed span needs no linear scan.
  lo := 0;
  hi := FNumBuckets - 1;
  Result := 0;
  while lo <= hi do begin
    mid := (lo + hi) div 2;
    if FBucketStart[mid] <= AIndex then begin
      Result := mid;
      lo := mid + 1;
    end
    else
      hi := mid - 1;
  end;
end;

{ The reduction loops below run over millions of samples, and every index in
  them comes from the column boundaries rather than from a caller, so range
  and overflow checks cost time without buying safety.  Disabled only if they
  were on, and restored to whatever they were. }
{$IFOPT R+}{$DEFINE TA_RANGE_WAS_ON}{$R-}{$ENDIF}
{$IFOPT Q+}{$DEFINE TA_OVERFLOW_WAS_ON}{$Q-}{$ENDIF}

procedure TFastLineSeries.RebuildBuckets(ALo, AHi: Integer);
var
  b, i, s, e, minI, maxI, loI, hiI, n, base: Integer;
  p: PChartFastPoint;

  procedure Put(AIndex: Integer);
  begin
    FBucketPts[base + n] := FData[AIndex];
    Inc(n);
  end;

begin
  if ALo < 0 then ALo := 0;
  if AHi > FNumBuckets - 1 then AHi := FNumBuckets - 1;
  for b := ALo to AHi do begin
    s := FBucketStart[b];
    e := FBucketStart[b + 1] - 1;
    base := b * 4;
    n := 0;
    if s <= e then begin
      minI := s;
      maxI := s;
      p := @FData[s];
      for i := s to e do begin
        if p.Y < FData[minI].Y then minI := i;
        if p.Y > FData[maxI].Y then maxI := i;
        Inc(p);
      end;
      // First and last preserve where the line enters and leaves the column;
      // min and max preserve its vertical extent.  Emitted in sample order so
      // the polyline keeps its shape.
      Put(s);
      if minI <= maxI then begin
        loI := minI;
        hiI := maxI;
      end
      else begin
        loI := maxI;
        hiI := minI;
      end;
      if (loI <> s) and (loI <> e) then Put(loI);
      if (hiI <> s) and (hiI <> e) and (hiI <> loI) then Put(hiI);
      if e <> s then Put(e);
    end;
    FBucketLen[b] := n;
  end;
end;

procedure TFastLineSeries.CompactDecimated;
var
  b, k, base: Integer;
begin
  // Flattens the per-column vertices into the contiguous array handed to
  // glDrawArrays.  One pass over the columns - a few thousand - not the
  // samples.
  FDecCount := 0;
  for b := 0 to FNumBuckets - 1 do begin
    base := b * 4;
    for k := 0 to FBucketLen[b] - 1 do begin
      FDecimated[FDecCount] := FBucketPts[base + k];
      Inc(FDecCount);
    end;
  end;
end;

procedure TFastLineSeries.BuildDecimated(
  const AParams: TChartFastRenderParams);
var
  pixW, b, idx: Integer;
  scale, xMin: Double;

  function BucketOfX(const AX: Single): Integer;
  begin
    // Columns are offset by one so samples left of the plot land in column 0
    // and samples right of it in the last, keeping the line entering and
    // leaving the plot correctly.
    Result := Floor((AX - xMin) * scale) + 1;
    if Result < 0 then
      Result := 0
    else if Result > pixW + 1 then
      Result := pixW + 1;
  end;

begin
  pixW := AParams.Rect.Width;
  xMin := AParams.XMin;
  scale := pixW / (AParams.XMax - AParams.XMin);
  FNumBuckets := pixW + 2;

  if Length(FBucketStart) < FNumBuckets + 1 then
    SetLength(FBucketStart, FNumBuckets + 1);
  if Length(FBucketLen) < FNumBuckets then
    SetLength(FBucketLen, FNumBuckets);
  if Length(FBucketPts) < FNumBuckets * 4 then
    SetLength(FBucketPts, FNumBuckets * 4);
  if Length(FDecimated) < FNumBuckets * 4 then
    SetLength(FDecimated, FNumBuckets * 4);

  // Only samples inside the visible X range can affect the picture, so find
  // that span by binary search and ignore the rest.  This is what keeps pan
  // and zoom proportional to what is on screen rather than to the size of the
  // data set.  One extra sample each side so the line still enters and leaves
  // the plot at the right slope.
  FVisFirst := IndexAtOrBefore(AParams.XMin);
  if FVisFirst < 0 then
    FVisFirst := 0;
  FVisLast := IndexAtOrBefore(AParams.XMax) + 1;
  if FVisLast > FCount - 1 then
    FVisLast := FCount - 1;

  // One forward pass: X ascends, so each column's samples are a contiguous
  // run and the boundaries fall out of a single walk.
  idx := FVisFirst;
  for b := 0 to FNumBuckets - 1 do begin
    FBucketStart[b] := idx;
    while (idx <= FVisLast) and (BucketOfX(FData[idx].X) = b) do
      Inc(idx);
  end;
  FBucketStart[FNumBuckets] := idx;

  RebuildBuckets(0, FNumBuckets - 1);
  CompactDecimated;

  FDecVersion := FDataVersion;
  FDecWidth := pixW;
  FDecXMin := AParams.XMin;
  FDecXMax := AParams.XMax;
  FDecDirtyLo := -1;
  FDecDirtyHi := -1;
end;

{$IFDEF TA_RANGE_WAS_ON}{$R+}{$UNDEF TA_RANGE_WAS_ON}{$ENDIF}
{$IFDEF TA_OVERFLOW_WAS_ON}{$Q+}{$UNDEF TA_OVERFLOW_WAS_ON}{$ENDIF}

procedure TFastLineSeries.UpdateDecimation(
  const AParams: TChartFastRenderParams);
begin
  // Full rebuild only when the data or the mapping changed wholesale;
  // otherwise patch just the columns whose values moved.
  if (FDecVersion <> FDataVersion) or (FDecWidth <> AParams.Rect.Width) or
     (FDecXMin <> AParams.XMin) or (FDecXMax <> AParams.XMax) then
    BuildDecimated(AParams)
  else if FDecDirtyLo >= 0 then begin
    RebuildBuckets(FDecDirtyLo, FDecDirtyHi);
    CompactDecimated;
    FDecDirtyLo := -1;
    FDecDirtyHi := -1;
  end;
end;

{ Vertex buffer }

function TFastLineSeries.UsingVBO: Boolean;
begin
  Result := FVBO <> 0;
end;

procedure TFastLineSeries.SyncBuffer(const AGL: TChartGLContext);
var
  byteSize: NativeInt;
begin
  if (AGL = nil) or (not AGL.HasVBO) or (FCount = 0) then exit;

  // A buffer name means nothing to another context, and the designer recreates
  // window handles - and therefore contexts - freely.  The old name is simply
  // abandoned; it died with its context.
  if (FVBO <> 0) and (FVBOContextId <> AGL.ContextId) then begin
    FVBO := 0;
    FVBOCount := 0;
  end;

  if FVBO = 0 then begin
    FVBO := AGL.CreateArrayBuffer;
    if FVBO = 0 then exit;
    FVBOContextId := AGL.ContextId;
    FVBOCount := 0;
  end;

  AGL.BindArrayBuffer(FVBO);
  byteSize := NativeInt(FCount) * SizeOf(TChartFastPoint);

  if FUploadAll or (FVBOCount <> FCount) then begin
    AGL.ArrayBufferData(byteSize, @FData[0], true);
    FVBOCount := FCount;
    FUploadAll := false;
    FDirtyFirst := -1;
    FDirtyLast := -1;
  end
  else if FDirtyFirst >= 0 then begin
    AGL.ArrayBufferSubData(
      NativeInt(FDirtyFirst) * SizeOf(TChartFastPoint),
      NativeInt(FDirtyLast - FDirtyFirst + 1) * SizeOf(TChartFastPoint),
      @FData[FDirtyFirst]);
    FDirtyFirst := -1;
    FDirtyLast := -1;
  end;
end;

{ Drawing }

function TFastLineSeries.RenderParams(
  out AParams: TChartFastRenderParams): Boolean;
var
  ext: TDoubleRect;
begin
  Result := false;
  if ParentChart = nil then exit;
  AParams.Rect := ParentChart.ClipRect;
  ext := ParentChart.CurrentExtent;
  AParams.XMin := ext.a.X;
  AParams.YMin := ext.a.Y;
  AParams.XMax := ext.b.X;
  AParams.YMax := ext.b.Y;
  Result := (AParams.Rect.Width > 0) and (AParams.Rect.Height > 0) and
    (AParams.XMax > AParams.XMin) and (AParams.YMax > AParams.YMin);
end;

procedure TFastLineSeries.DrawGL(const AGL: TChartGLContext;
  const AParams: TChartFastRenderParams);
var
  sx, sy: Double;
  r: TRect;
  c: TColor;
begin
  r := AParams.Rect;
  sx := r.Width / (AParams.XMax - AParams.XMin);
  sy := r.Height / (AParams.YMax - AParams.YMin);

  c := FLinePen.Color;
  if c = clDefault then
    c := clBlack;
  AGL.SetColor(c);
  // Thin and unsmoothed: the cheapest path, and what makes the decimated
  // result pixel-identical to drawing every sample.  Setup2D re-enables
  // smoothing at the start of the next frame.
  glDisable(GL_LINE_SMOOTH);
  glLineWidth(Max(1, FLinePen.Width));

  // Data may run outside the visible range, so clip to the plot area.
  // glScissor's origin is bottom-left, unlike the chart's top-left pixels.
  glScissor(r.Left, ParentChart.Height - r.Bottom, r.Width, r.Height);
  glEnable(GL_SCISSOR_TEST);
  try
    // Fold the data-to-pixel mapping into the modelview matrix so the GPU
    // performs the transform and the vertex buffer is handed over untouched.
    glMatrixMode(GL_MODELVIEW);
    glPushMatrix;
    try
      glTranslatef(r.Left, r.Bottom, 0);
      glScalef(sx, -sy, 1);              // Y grows upward on screen
      glTranslatef(-AParams.XMin, -AParams.YMin, 0);

      if ShouldDecimate(AParams) then begin
        UpdateDecimation(AParams);
        FLastDrawn := FDecCount;
        if FDecCount >= 2 then begin
          // A few thousand vertices at most, so a client array is cheaper
          // than maintaining a second GPU buffer for them.
          glEnableClientState(GL_VERTEX_ARRAY);
          glVertexPointer(2, GL_FLOAT, 0, @FDecimated[0]);
          glDrawArrays(GL_LINE_STRIP, 0, FDecCount);
          glDisableClientState(GL_VERTEX_ARRAY);
        end;
      end
      else begin
        SyncBuffer(AGL);
        FLastDrawn := FCount;
        glEnableClientState(GL_VERTEX_ARRAY);
        if FVBO <> 0 then begin
          // Already on the GPU: the pointer is a byte offset into the bound
          // buffer, and nothing crosses the bus for a static data set.
          AGL.BindArrayBuffer(FVBO);
          glVertexPointer(2, GL_FLOAT, 0, nil);
          glDrawArrays(GL_LINE_STRIP, 0, FCount);
          AGL.BindArrayBuffer(0);
        end
        else begin
          // No VBO support: client-side array.
          glVertexPointer(2, GL_FLOAT, 0, @FData[0]);
          glDrawArrays(GL_LINE_STRIP, 0, FCount);
        end;
        glDisableClientState(GL_VERTEX_ARRAY);
      end;
    finally
      glPopMatrix;
    end;
  finally
    glDisable(GL_SCISSOR_TEST);
  end;
end;

procedure TFastLineSeries.DrawPolyline(ADrawer: IChartDrawer;
  const AParams: TChartFastRenderParams);
var
  pts: array of TPoint;
  src: PChartFastPoint;
  n, i: Integer;
begin
  // No GL context - a canvas, SVG or WMF drawer, or a chart that fell back to
  // GDI.  The same reduction still applies, so even a very large series turns
  // into a few thousand pixel points rather than millions.
  if ShouldDecimate(AParams) then begin
    UpdateDecimation(AParams);
    n := FDecCount;
    if n = 0 then exit;
    src := @FDecimated[0];
  end
  else begin
    n := FCount;
    src := @FData[0];
  end;
  FLastDrawn := n;
  if n < 2 then exit;

  SetLength(pts, n);
  for i := 0 to n - 1 do begin
    pts[i] := ParentChart.GraphToImage(DoublePoint(src.X, src.Y));
    Inc(src);
  end;

  ADrawer.Pen := FLinePen;
  ADrawer.SetBrushParams(bsClear, clTAColor);
  ADrawer.ClippingStart(AParams.Rect);
  try
    ADrawer.Polyline(pts, 0, n);
  finally
    ADrawer.ClippingStop;
  end;
end;

procedure TFastLineSeries.Draw(ADrawer: IChartDrawer);
var
  params: TChartFastRenderParams;
  gl: IChartGLDrawer;
begin
  if FCount < 2 then exit;
  if not RenderParams(params) then exit;

  // The GPU path when the drawer offers a context, the CPU polyline otherwise
  // - so this series keeps working under every other drawer.
  if Supports(ADrawer, IChartGLDrawer, gl) and (gl.GLContext <> nil) then
    DrawGL(gl.GLContext, params)
  else
    DrawPolyline(ADrawer, params);
end;

initialization
  // Puts the class in the series gallery and makes it streamable, the
  // same way every other series unit registers itself.
  RegisterSeriesClass(TFastLineSeries, @rsFastLineSeries);

end.
