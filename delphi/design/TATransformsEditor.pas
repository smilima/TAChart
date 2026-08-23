{
 *****************************************************************************
  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  Authors: Alexander Klenin

  In Lazarus these editors live inside TATransformations itself; in Delphi
  design-time code has to sit in the design-time package, so they were moved
  into a unit of their own.
}

unit TATransformsEditor;

{$I TAChartDefines.inc}

interface

uses
  System.Classes, Vcl.Forms, DesignIntf, DesignEditors,
  TASubcomponentsEditor;

type
  { TAxisTransformsComponentEditor }

  TAxisTransformsComponentEditor = class(TSubComponentListEditor)
  protected
    function MakeEditorForm: TComponentListEditorForm; override;
  public
    function GetVerb(Index: Integer): string; override;
  end;

  { TAxisTransformsPropertyEditor }

  TAxisTransformsPropertyEditor = class(TComponentListPropertyEditor)
  protected
    function GetChildrenCount: Integer; override;
    function MakeEditorForm: TComponentListEditorForm; override;
  end;

  { TAxisTransformsEditorForm }

  TAxisTransformsEditorForm = class(TComponentListEditorForm)
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
  TAChartStrConsts, TATransformations;

{ TAxisTransformsComponentEditor }

function TAxisTransformsComponentEditor.GetVerb(Index: Integer): string;
begin
  if Index = 0 then
    Result := tasAxisTransformsEditorTitle
  else
    Result := '';
end;

function TAxisTransformsComponentEditor.MakeEditorForm: TComponentListEditorForm;
begin
  Result := TAxisTransformsEditorForm.Create(
    Application, Component, Self, nil, Designer);
end;

{ TAxisTransformsPropertyEditor }

function TAxisTransformsPropertyEditor.GetChildrenCount: Integer;
begin
  Result := (TObject(GetOrdValue) as TAxisTransformList).Count;
end;

function TAxisTransformsPropertyEditor.MakeEditorForm: TComponentListEditorForm;
begin
  Result := TAxisTransformsEditorForm.Create(
    Application, GetComponent(0) as TComponent, nil, Self, Designer);
end;

{ TAxisTransformsEditorForm }

procedure TAxisTransformsEditorForm.AddSubcomponent(
  AParent, AChild: TComponent);
begin
  (AChild as TAxisTransform).Transformations :=
    AParent as TChartAxisTransformations;
end;

procedure TAxisTransformsEditorForm.BuildCaption;
begin
  Caption := tasAxisTransformsEditorTitle + ' - ' + Parent.Name;
end;

function TAxisTransformsEditorForm.ChildClass: TComponentClass;
begin
  Result := TAxisTransform;
end;

procedure TAxisTransformsEditorForm.EnumerateSubcomponentClasses;
var
  i: Integer;
begin
  for i := 0 to AxisTransformsClassRegistry.Count - 1 do
    AddSubcomponentClass(AxisTransformsClassRegistry.GetCaption(i), i);
end;

function TAxisTransformsEditorForm.GetChildrenList: TList;
begin
  Result := (Parent as TChartAxisTransformations).List;
end;

function TAxisTransformsEditorForm.MakeSubcomponent(
  AOwner: TComponent; ATag: Integer): TComponent;
begin
  Result := TAxisTransformClass(
    AxisTransformsClassRegistry.GetClass(ATag)).Create(AOwner);
end;

end.
