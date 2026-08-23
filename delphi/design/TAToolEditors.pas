{
 *****************************************************************************
  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  Authors: Alexander Klenin
}

unit TAToolEditors;

{$I TAChartDefines.inc}

interface

uses
  System.Classes, Vcl.Forms, DesignIntf, DesignEditors,
  TASubcomponentsEditor;

type
  { TToolsComponentEditor }

  TToolsComponentEditor = class(TSubComponentListEditor)
  protected
    function MakeEditorForm: TComponentListEditorForm; override;
  public
    function GetVerb(Index: Integer): string; override;
  end;

  { TToolsPropertyEditor }

  TToolsPropertyEditor = class(TComponentListPropertyEditor)
  protected
    function GetChildrenCount: Integer; override;
    function MakeEditorForm: TComponentListEditorForm; override;
  end;

  { TToolsEditorForm }

  TToolsEditorForm = class(TComponentListEditorForm)
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
  System.SysUtils,
  TAChartStrConsts, TATools;

{ TToolsComponentEditor }

function TToolsComponentEditor.GetVerb(Index: Integer): string;
begin
  if Index = 0 then
    Result := tasToolsEditorTitle
  else
    Result := '';
end;

function TToolsComponentEditor.MakeEditorForm: TComponentListEditorForm;
begin
  Result := TToolsEditorForm.Create(
    Application, Component, Self, nil, Designer);
end;

{ TToolsPropertyEditor }

function TToolsPropertyEditor.GetChildrenCount: Integer;
begin
  Result := (TObject(GetOrdValue) as TChartTools).Count;
end;

function TToolsPropertyEditor.MakeEditorForm: TComponentListEditorForm;
begin
  Result := TToolsEditorForm.Create(
    Application, GetComponent(0) as TComponent, nil, Self, Designer);
end;

{ TToolsEditorForm }

procedure TToolsEditorForm.AddSubcomponent(AParent, AChild: TComponent);
begin
  (AChild as TChartTool).Toolset := (AParent as TChartToolset);
end;

procedure TToolsEditorForm.BuildCaption;
begin
  Caption := tasToolsEditorTitle + ' - ' + Parent.Name;
end;

function TToolsEditorForm.ChildClass: TComponentClass;
begin
  Result := TChartTool;
end;

procedure TToolsEditorForm.EnumerateSubcomponentClasses;
var
  i: Integer;
begin
  for i := 0 to ToolsClassRegistry.Count - 1 do
    AddSubcomponentClass(ToolsClassRegistry.GetCaption(i), i);
end;

function TToolsEditorForm.GetChildrenList: TList;
begin
  Result := (Parent as TChartToolset).Tools;
end;

function TToolsEditorForm.MakeSubcomponent(
  AOwner: TComponent; ATag: Integer): TComponent;
begin
  Result := TChartToolClass(ToolsClassRegistry.GetClass(ATag)).Create(AOwner);
end;

end.
