{
 *****************************************************************************
  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  Author: Alexander Klenin
}

unit TASeriesEditor;

{$I TAChartDefines.inc}

interface

uses
  System.Classes, Vcl.Forms, DesignIntf, DesignEditors,
  TASubcomponentsEditor;

type
  { TSeriesComponentEditor }

  TSeriesComponentEditor = class(TSubComponentListEditor)
  protected
    function MakeEditorForm: TComponentListEditorForm; override;
  public
    function GetVerb(Index: Integer): string; override;
  end;

  { TSeriesPropertyEditor }

  TSeriesPropertyEditor = class(TComponentListPropertyEditor)
  protected
    function GetChildrenCount: Integer; override;
    function MakeEditorForm: TComponentListEditorForm; override;
  end;

  { TSeriesEditorForm }

  TSeriesEditorForm = class(TComponentListEditorForm)
  protected
    procedure AddSubcomponent(AParent, AChild: TComponent); override;
    procedure BuildCaption; override;
    function ChildClass: TComponentClass; override;
    procedure EnumerateSubcomponentClasses; override;
    function GetChildrenList: TList; override;
    function MakeSubcomponent(
      AOwner: TComponent; ATag: Integer): TComponent; override;
  end;

implementation

uses
  System.SysUtils, System.TypInfo,
  TAChartStrConsts, TAGraph;

{ TSeriesComponentEditor }

function TSeriesComponentEditor.GetVerb(Index: Integer): string;
begin
  if Index = 0 then
    Result := sesSeriesEditorTitle
  else
    Result := '';
end;

function TSeriesComponentEditor.MakeEditorForm: TComponentListEditorForm;
begin
  Result := TSeriesEditorForm.Create(
    Application, Component, Self, nil, Designer);
end;

{ TSeriesPropertyEditor }

function TSeriesPropertyEditor.GetChildrenCount: Integer;
begin
  Result := (TObject(GetOrdValue) as TChartSeriesList).Count;
end;

function TSeriesPropertyEditor.MakeEditorForm: TComponentListEditorForm;
begin
  Result := TSeriesEditorForm.Create(
    Application, GetComponent(0) as TComponent, nil, Self, Designer);
end;

{ TSeriesEditorForm }

procedure TSeriesEditorForm.AddSubcomponent(AParent, AChild: TComponent);
begin
  (AParent as TChart).AddSeries(AChild as TBasicChartSeries);
end;

procedure TSeriesEditorForm.BuildCaption;
begin
  Caption := sesSeriesEditorTitle + ' - ' + Parent.Name;
end;

function TSeriesEditorForm.ChildClass: TComponentClass;
begin
  Result := TBasicChartSeries;
end;

procedure TSeriesEditorForm.EnumerateSubcomponentClasses;
var
  i: Integer;
begin
  for i := 0 to SeriesClassRegistry.Count - 1 do
    AddSubcomponentClass(SeriesClassRegistry.GetCaption(i), i);
end;

function TSeriesEditorForm.GetChildrenList: TList;
begin
  Result := (Parent as TChart).Series.List;
end;

function TSeriesEditorForm.MakeSubcomponent(
  AOwner: TComponent; ATag: Integer): TComponent;
begin
  Result := TSeriesClass(SeriesClassRegistry.GetClass(ATag)).Create(AOwner);
end;

end.
