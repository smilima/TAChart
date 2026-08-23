{
 *****************************************************************************
  This file is part of the Delphi/VCL port of TAChart.

  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  Component palette registration.

  Lazarus spreads a Register procedure over most of the runtime units.  Delphi
  keeps design-time code out of the runtime package, so all registration is
  collected here instead.

  Series, tools and axis transforms are not dropped from the palette; they are
  created through the chart / toolset / transform editors.  They still need
  RegisterClass + RegisterNoIcon so the form designer can stream them.
  Runtime streaming is handled by TAChartRegistration (C++Builder does not
  execute this unit).
}

unit TAChartReg;

{$I TAChartDefines.inc}

interface

procedure Register;

implementation

uses
  System.Classes, System.TypInfo,
  DesignIntf, DesignEditors,
  // runtime
  TAChartUtils, TACustomSeries, TAGraph, TASeries, TAMultiSeries,
  TARadialSeries, TAFuncSeries, TASources, TAIntervalSources, TADbSource,
  TAStyles, TATools, TADataTools, TATransformations, TAChartListbox, TAChartCombos,
  TAChartImageList, TAChartExtentLink, TALegendPanel, TANavigation,
  TAChartAxis, TAChartGL, TAFastSeries,
  // design time
  TASeriesEditorUnit, TAToolEditors, TATransformsEditor, TASeriesPropEditors,
  TASubcomponentsEditor, TADataPointsEditor;

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

procedure RegisterSeriesClasses;
begin
  SafeRegisterClass(TTALineSeries);
  SafeRegisterClass(TFastLineSeries);
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

  RegisterNoIcon([
    TTALineSeries,
    TFastLineSeries,
    TTAAreaSeries,
    TTABarSeries,
    TTAPieSeries,
    TUserDrawnSeries,
    TConstantLine,
    TManhattanSeries,
    TTAPolarSeries,
    TTABubbleSeries,
    TBoxAndWhiskerSeries,
    TOpenHighLowCloseSeries,
    TFieldSeries,
    TFuncSeries,
    TParametricCurveSeries,
    TBSplineSeries,
    TCubicSplineSeries,
    TFitSeries,
    TColorMapSeries
  ]);
end;

procedure RegisterToolClasses;
begin
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

  RegisterNoIcon([
    TUserDefinedTool,
    TZoomDragTool,
    TZoomClickTool,
    TZoomMouseWheelTool,
    TPanDragTool,
    TPanClickTool,
    TPanMouseWheelTool,
    TDataPointClickTool,
    TDataPointDragTool,
    TDataPointHintTool,
    TDataPointCrosshairTool,
    TDataPointDistanceTool
  ]);
end;

procedure RegisterAxisTransformClasses;
begin
  SafeRegisterClass(TChartAxisTransformations);
  SafeRegisterClass(TAutoScaleAxisTransform);
  SafeRegisterClass(TCumulNormDistrAxisTransform);
  SafeRegisterClass(TLinearAxisTransform);
  SafeRegisterClass(TLogarithmAxisTransform);
  SafeRegisterClass(TUserDefinedAxisTransform);

  RegisterNoIcon([
    TAutoScaleAxisTransform,
    TCumulNormDistrAxisTransform,
    TLinearAxisTransform,
    TLogarithmAxisTransform,
    TUserDefinedAxisTransform
  ]);
end;

procedure RegisterSourceClasses;
begin
  SafeRegisterClass(TListChartSource);
  SafeRegisterClass(TRandomChartSource);
  SafeRegisterClass(TUserDefinedChartSource);
  SafeRegisterClass(TCalculatedChartSource);
  SafeRegisterClass(TIntervalChartSource);
  SafeRegisterClass(TDateTimeIntervalChartSource);
  SafeRegisterClass(TDbChartSource);
end;

procedure RegisterAuxiliaryClasses;
begin
  SafeRegisterClass(TTAChart);
  SafeRegisterClass(TChartStyles);
  SafeRegisterClass(TChartListbox);
  SafeRegisterClass(TChartComboBox);
  SafeRegisterClass(TChartExtentLink);
  SafeRegisterClass(TChartImageList);
  SafeRegisterClass(TChartLegendPanel);
  SafeRegisterClass(TChartNavScrollBar);
  SafeRegisterClass(TChartNavPanel);
  SafeRegisterClass(TTAChartGL);
end;

procedure Register;
begin
  // Keep the package loaded so its components stay on the Tool Palette.
  // Without this, modern Delphi demand-loads design packages and a VCL-only
  // set can be filtered away until a form already uses them.
  ForceDemandLoadState(dlDisable);

  // TTAChart, not TChart: TeeChart already registered TChart (dclfmxtee / dcltee).
  RegisterComponents(CHART_COMPONENT_IDE_PAGE, [
    TTAChart,
    // Same chart, rendered on the GPU.  Falls back to GDI where there is no
    // OpenGL, so it is safe to use in place of TTAChart.
    TTAChartGL,
    TChartToolset,
    TChartAxisTransformations,
    TChartStyles,
    TListChartSource,
    TRandomChartSource,
    TUserDefinedChartSource,
    TCalculatedChartSource,
    TIntervalChartSource,
    TDateTimeIntervalChartSource,
    TDbChartSource,
    TChartListbox,
    TChartComboBox,
    TChartExtentLink,
    TChartImageList,
    TChartLegendPanel,
    TChartNavScrollBar,
    TChartNavPanel
  ]);

  // Series, tools and axis transformations are created through their editors
  // rather than dropped from the palette, but still have to be streamable.
  // A leftover ClassName clash with TeeChart must not roll back the palette.
  try
    RegisterSeriesClasses;
    RegisterToolClasses;
    RegisterAxisTransformClasses;
    RegisterSourceClasses;
    RegisterAuxiliaryClasses;
  except
    on EFilerError do
      ;
  end;

  // Component and property editors.
  RegisterComponentEditor(TTAChart, TSeriesComponentEditor);
  RegisterPropertyEditor(
    TypeInfo(TChartSeriesList), TTAChart, 'Series', TSeriesPropertyEditor);

  RegisterComponentEditor(TChartToolset, TToolsComponentEditor);
  RegisterPropertyEditor(
    TypeInfo(TChartTools), TChartToolset, 'Tools', TToolsPropertyEditor);

  RegisterComponentEditor(
    TChartAxisTransformations, TAxisTransformsComponentEditor);
  RegisterPropertyEditor(
    TypeInfo(TAxisTransformList), TChartAxisTransformations, 'List',
    TAxisTransformsPropertyEditor);

  RegisterPropertyEditor(
    TypeInfo(TChartAxisIndex), TCustomChartSeries, '',
    TAxisIndexPropertyEditor);

  RegisterPropertyEditor(
    TypeInfo(TStrings), TListChartSource, 'DataPoints',
    TDataPointsPropertyEditor);
end;

end.
