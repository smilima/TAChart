{
 *****************************************************************************
  Runtime DFM class registration for every streamable TAChart component.

  Design-time RegisterComponents / RegisterNoIcon live in TAChartReg and are
  not executed in an application.  This unit is contained in TAChartRT so the
  BPL registers every series, tool, transform, source and auxiliary component
  when the package loads.

  Do not use this unit from TAGraph or from any design-time unit: a circular
  uses clause crashes C++Builder at startup, and using it from TAChartReg
  compiles it into TAChartDT as well, which the IDE refuses to load.
 *****************************************************************************
}

unit TAChartRegistration;

{$I TAChartDefines.inc}

interface

procedure RegisterTAChartRuntimeClasses;

implementation

uses
  System.Classes,
  TAGraph, TASeries, TARadialSeries, TAMultiSeries, TAFuncSeries,
  TASources, TAIntervalSources, TADbSource,
  TATools, TADataTools, TATransformations, TAStyles,
  TAChartListbox, TAChartCombos, TAChartImageList, TAChartExtentLink,
  TALegendPanel, TANavigation;

procedure SafeRegisterClass(AClass: TPersistentClass);
var
  existing: TPersistentClass;
begin
  if AClass = nil then
    exit;
  existing := GetClass(AClass.ClassName);
  if existing = nil then
    RegisterClass(AClass);
end;

procedure RegisterTAChartRuntimeClasses;
begin
  // Chart
  SafeRegisterClass(TTAChart);

  // Series (owned by the form, nested in the chart DFM)
  SafeRegisterClass(TTALineSeries);
  SafeRegisterClass(TTAAreaSeries);
  SafeRegisterClass(TTABarSeries);
  SafeRegisterClass(TTAPieSeries);
  SafeRegisterClass(TUserDrawnSeries);
  SafeRegisterClass(TConstantLine);
  SafeRegisterClass(TManhattanSeries);
  SafeRegisterClass(TTAPolarSeries);
  SafeRegisterClass(TTABubbleSeries);
  SafeRegisterClass(TBoxAndWhiskerSeries);
  SafeRegisterClass(TOpenHighLowCloseSeries);
  SafeRegisterClass(TFieldSeries);
  SafeRegisterClass(TFuncSeries);
  SafeRegisterClass(TParametricCurveSeries);
  SafeRegisterClass(TBSplineSeries);
  SafeRegisterClass(TCubicSplineSeries);
  SafeRegisterClass(TFitSeries);
  SafeRegisterClass(TColorMapSeries);

  // Tools
  SafeRegisterClass(TChartToolset);
  SafeRegisterClass(TUserDefinedTool);
  SafeRegisterClass(TZoomDragTool);
  SafeRegisterClass(TZoomClickTool);
  SafeRegisterClass(TZoomMouseWheelTool);
  SafeRegisterClass(TPanDragTool);
  SafeRegisterClass(TPanClickTool);
  SafeRegisterClass(TPanMouseWheelTool);
  SafeRegisterClass(TDataPointClickTool);
  SafeRegisterClass(TDataPointDragTool);
  SafeRegisterClass(TDataPointHintTool);
  SafeRegisterClass(TDataPointCrosshairTool);
  SafeRegisterClass(TDataPointDistanceTool);

  // Axis transformations
  SafeRegisterClass(TChartAxisTransformations);
  SafeRegisterClass(TAutoScaleAxisTransform);
  SafeRegisterClass(TCumulNormDistrAxisTransform);
  SafeRegisterClass(TLinearAxisTransform);
  SafeRegisterClass(TLogarithmAxisTransform);
  SafeRegisterClass(TUserDefinedAxisTransform);

  // Chart sources
  SafeRegisterClass(TListChartSource);
  SafeRegisterClass(TRandomChartSource);
  SafeRegisterClass(TUserDefinedChartSource);
  SafeRegisterClass(TCalculatedChartSource);
  SafeRegisterClass(TIntervalChartSource);
  SafeRegisterClass(TDateTimeIntervalChartSource);
  SafeRegisterClass(TDbChartSource);

  // Auxiliary components
  SafeRegisterClass(TChartStyles);
  SafeRegisterClass(TChartListbox);
  SafeRegisterClass(TChartComboBox);
  SafeRegisterClass(TChartExtentLink);
  SafeRegisterClass(TChartImageList);
  SafeRegisterClass(TChartLegendPanel);
  SafeRegisterClass(TChartNavScrollBar);
  SafeRegisterClass(TChartNavPanel);
end;

initialization
  RegisterTAChartRuntimeClasses;

end.
