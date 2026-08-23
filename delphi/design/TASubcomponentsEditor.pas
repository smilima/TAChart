{
 *****************************************************************************
  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  Author: Alexander Klenin

  Delphi/VCL port note
  --------------------
  The Lazarus original drives the IDE through GlobalDesignHook and
  TPersistentSelectionList.  Delphi's equivalents live in DesignIntf: IDesigner
  for the designer itself, IDesignerSelections for selections and
  IDesignNotification for the change callbacks.  The editor window is built in
  code rather than loaded from a form resource, so the design-time package
  needs no .dfm of its own.
}

unit TASubcomponentsEditor;

{$I TAChartDefines.inc}

interface

uses
  System.Classes, System.SysUtils, System.Types,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Menus, Vcl.Buttons,
  DesignIntf, DesignEditors;

type
  TComponentListEditorForm = class;

  { TSubComponentListEditor -- component editor adding a single "edit the
    child list" verb. }
  TSubComponentListEditor = class(TComponentEditor)
  protected
    function MakeEditorForm: TComponentListEditorForm; virtual; abstract;
  public
    procedure ExecuteVerb(Index: Integer); override;
    function GetVerbCount: Integer; override;
  end;

  { TComponentListPropertyEditor -- shows the same window from the Object
    Inspector, and displays the child count as the property value. }
  TComponentListPropertyEditor = class(TPropertyEditor)
  protected
    function GetChildrenCount: Integer; virtual; abstract;
    function MakeEditorForm: TComponentListEditorForm; virtual; abstract;
  public
    procedure Edit; override;
    function GetAttributes: TPropertyAttributes; override;
    function GetValue: string; override;
  end;

  { TComponentListEditorForm }

  TComponentListEditorForm = class(TForm, IDesignNotification)
  strict private
    FChildrenListBox: TListBox;
    FMenuAddItem: TPopupMenu;
    FToolPanel: TPanel;
    FBtnAdd: TButton;
    FBtnDelete: TButton;
    FBtnMoveUp: TButton;
    FBtnMoveDown: TButton;
    FComponentEditor: TSubComponentListEditor;
    FDesigner: IDesigner;
    FParent: TComponent;
    FPropertyEditor: TComponentListPropertyEditor;
    FUpdatingSelection: Boolean;
    procedure BtnAddClick(Sender: TObject);
    procedure BtnDeleteClick(Sender: TObject);
    procedure BtnMoveDownClick(Sender: TObject);
    procedure BtnMoveUpClick(Sender: TObject);
    procedure BuildControls;
    procedure ChildrenListBoxClick(Sender: TObject);
    function FindChild(ACandidate: TPersistent; out AIndex: Integer): Boolean;
    procedure MenuAddClick(Sender: TObject);
    procedure MoveSelection(AStart, ADir: Integer);
    procedure PushSelectionToDesigner(AOrderChanged: Boolean = false);
  strict protected
    // IDesignNotification
    procedure ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
    procedure ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
    procedure ItemsModified(const ADesigner: IDesigner);
    procedure SelectionChanged(const ADesigner: IDesigner;
      const ASelection: IDesignerSelections);
    procedure DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
    procedure DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
  protected
    procedure AddSubcomponent(AParent, AChild: TComponent); virtual; abstract;
    procedure AddSubcomponentClass(const ACaption: String; ATag: Integer);
    procedure BuildCaption; virtual; abstract;
    function ChildClass: TComponentClass; virtual; abstract;
    procedure DoClose(var Action: TCloseAction); override;
    procedure EnumerateSubcomponentClasses; virtual; abstract;
    function GetChildrenList: TList; virtual; abstract;
    function MakeSubcomponent(
      AOwner: TComponent; ATag: Integer): TComponent; virtual; abstract;
    procedure RefreshList;
    property Parent: TComponent read FParent;
  public
    constructor Create(
      AOwner, AParent: TComponent; AComponentEditor: TSubComponentListEditor;
      APropertyEditor: TComponentListPropertyEditor;
      const ADesigner: IDesigner); reintroduce;
    destructor Destroy; override;
    // Called once the descendant's overrides are in place.
    procedure Initialize;
  end;

// Keeps one editor window per edited component, so invoking the verb twice
// brings the existing window forward instead of opening a second one.
function FindEditorForm(AParent: TPersistent): TComponentListEditorForm;
procedure RegisterEditorForm(
  AForm: TComponentListEditorForm; AParent: TPersistent);
procedure UnregisterEditorForm(AForm: TComponentListEditorForm);

implementation

uses
  System.Math, System.Generics.Collections,
  TAChartStrConsts, TAChartUtils;

var
  VEditorForms: TList = nil;
  VEditorParents: TList = nil;

function FindEditorForm(AParent: TPersistent): TComponentListEditorForm;
var
  i: Integer;
begin
  Result := nil;
  if VEditorParents = nil then exit;
  i := VEditorParents.IndexOf(Pointer(AParent));
  if i >= 0 then
    Result := TComponentListEditorForm(VEditorForms[i]);
end;

procedure RegisterEditorForm(
  AForm: TComponentListEditorForm; AParent: TPersistent);
begin
  if VEditorForms = nil then begin
    VEditorForms := TList.Create;
    VEditorParents := TList.Create;
  end;
  VEditorForms.Add(AForm);
  VEditorParents.Add(Pointer(AParent));
end;

procedure UnregisterEditorForm(AForm: TComponentListEditorForm);
var
  i: Integer;
begin
  if VEditorForms = nil then exit;
  i := VEditorForms.IndexOf(AForm);
  if i >= 0 then begin
    VEditorForms.Delete(i);
    VEditorParents.Delete(i);
  end;
end;

function ShowEditorFor(AParent: TPersistent;
  AMake: TFunc<TComponentListEditorForm>): TComponentListEditorForm;
begin
  Result := FindEditorForm(AParent);
  if Result = nil then begin
    Result := AMake();
    Result.Initialize;
    RegisterEditorForm(Result, AParent);
  end;
  Result.Show;
  Result.BringToFront;
end;

{ TSubComponentListEditor }

procedure TSubComponentListEditor.ExecuteVerb(Index: Integer);
var
  c: TPersistent;
begin
  if Index <> 0 then exit;
  c := GetComponent;
  if c = nil then
    raise Exception.Create('TSubComponentListEditor.Component = nil');
  ShowEditorFor(c, MakeEditorForm);
end;

function TSubComponentListEditor.GetVerbCount: Integer;
begin
  Result := 1;
end;

{ TComponentListPropertyEditor }

procedure TComponentListPropertyEditor.Edit;
var
  c: TPersistent;
begin
  c := GetComponent(0);
  if c = nil then
    raise Exception.Create('TComponentListPropertyEditor.Component = nil');
  ShowEditorFor(c, MakeEditorForm);
end;

function TComponentListPropertyEditor.GetAttributes: TPropertyAttributes;
begin
  Result := [paDialog, paReadOnly];
end;

function TComponentListPropertyEditor.GetValue: string;
var
  c: Integer;
begin
  c := GetChildrenCount;
  if c = 1 then
    Result := '1 item'
  else
    Result := IntToStr(c) + ' items';
end;

{ TComponentListEditorForm }

constructor TComponentListEditorForm.Create(
  AOwner, AParent: TComponent; AComponentEditor: TSubComponentListEditor;
  APropertyEditor: TComponentListPropertyEditor; const ADesigner: IDesigner);
begin
  inherited CreateNew(AOwner);
  FParent := AParent;
  FComponentEditor := AComponentEditor;
  FPropertyEditor := APropertyEditor;
  FDesigner := ADesigner;
  BuildControls;
end;

procedure TComponentListEditorForm.Initialize;
begin
  BuildCaption;
  EnumerateSubcomponentClasses;
  RefreshList;
  RegisterDesignNotification(Self);
  PushSelectionToDesigner;
end;

destructor TComponentListEditorForm.Destroy;
begin
  UnregisterDesignNotification(Self);
  UnregisterEditorForm(Self);
  FDesigner := nil;
  inherited;
end;

procedure TComponentListEditorForm.BuildControls;

  function MakeButton(const ACaption: String; ALeft: Integer;
    AOnClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := FToolPanel;
    Result.SetBounds(ALeft, 4, 80, 25);
    Result.Caption := ACaption;
    Result.OnClick := AOnClick;
  end;

begin
  BorderStyle := bsSizeable;
  Position := poScreenCenter;
  Width := 380;
  Height := 320;

  FToolPanel := TPanel.Create(Self);
  FToolPanel.Parent := Self;
  FToolPanel.Align := alTop;
  FToolPanel.Height := 33;
  FToolPanel.BevelOuter := bvNone;

  FBtnAdd := MakeButton(rsAdd, 4, BtnAddClick);
  FBtnDelete := MakeButton(rsDelete, 88, BtnDeleteClick);
  FBtnMoveUp := MakeButton(rsMoveUp, 172, BtnMoveUpClick);
  FBtnMoveDown := MakeButton(rsMoveDown, 256, BtnMoveDownClick);

  FChildrenListBox := TListBox.Create(Self);
  FChildrenListBox.Parent := Self;
  FChildrenListBox.Align := alClient;
  FChildrenListBox.MultiSelect := true;
  FChildrenListBox.OnClick := ChildrenListBoxClick;

  FMenuAddItem := TPopupMenu.Create(Self);
end;

procedure TComponentListEditorForm.DoClose(var Action: TCloseAction);
begin
  Action := caFree;
  inherited;
end;

procedure TComponentListEditorForm.AddSubcomponentClass(
  const ACaption: String; ATag: Integer);
var
  mi: TMenuItem;
begin
  if ACaption = '' then exit; // Empty names denote deprecated components.
  mi := TMenuItem.Create(Self);
  mi.Caption := ACaption;
  mi.Tag := ATag;
  mi.OnClick := MenuAddClick;
  FMenuAddItem.Items.Add(mi);
end;

procedure TComponentListEditorForm.BtnAddClick(Sender: TObject);
var
  p: TPoint;
begin
  p := FBtnAdd.ClientToScreen(Point(0, FBtnAdd.Height));
  FMenuAddItem.Popup(p.X, p.Y);
end;

procedure TComponentListEditorForm.MenuAddClick(Sender: TObject);
var
  s: TComponent;
  n: String;
begin
  s := MakeSubcomponent(FParent.Owner, (Sender as TMenuItem).Tag);
  try
    n := Copy(s.ClassName, 2, Length(s.ClassName) - 1);
    s.Name := FDesigner.UniqueName(FParent.Name + n);
    AddSubcomponent(FParent, s);
    FDesigner.Modified;
    RefreshList;
    FDesigner.SelectComponent(s);
  except
    s.Free;
    raise;
  end;
end;

procedure TComponentListEditorForm.BtnDeleteClick(Sender: TObject);
var
  i: Integer;
  doomed: TList;
begin
  if FChildrenListBox.SelCount = 0 then exit;
  doomed := TList.Create;
  try
    for i := 0 to FChildrenListBox.Count - 1 do
      if FChildrenListBox.Selected[i] then
        doomed.Add(FChildrenListBox.Items.Objects[i]);
    for i := 0 to doomed.Count - 1 do
      TComponent(doomed[i]).Free;
  finally
    doomed.Free;
  end;
  FDesigner.Modified;
  RefreshList;
  PushSelectionToDesigner;
end;

procedure TComponentListEditorForm.BtnMoveDownClick(Sender: TObject);
begin
  MoveSelection(FChildrenListBox.Count - 1, 1);
end;

procedure TComponentListEditorForm.BtnMoveUpClick(Sender: TObject);
begin
  MoveSelection(0, -1);
end;

procedure TComponentListEditorForm.ChildrenListBoxClick(Sender: TObject);
begin
  PushSelectionToDesigner;
end;

function TComponentListEditorForm.FindChild(
  ACandidate: TPersistent; out AIndex: Integer): Boolean;
begin
  if ACandidate is ChildClass then
    AIndex := FChildrenListBox.Items.IndexOfObject(ACandidate)
  else
    AIndex := -1;
  Result := AIndex >= 0;
end;

procedure TComponentListEditorForm.MoveSelection(AStart, ADir: Integer);
var
  i: Integer;
begin
  if FChildrenListBox.SelCount = 0 then exit;
  i := AStart - ADir;
  with FChildrenListBox do
    while InRange(i, 0, Count - 1) and InRange(i + ADir, 0, Count - 1) do begin
      if Selected[i] and not Selected[i + ADir] then begin
        with TIndexedComponent(Items.Objects[i]) do
          Index := Index + ADir;
        Items.Move(i, i + ADir);
        Selected[i + ADir] := true;
        Selected[i] := false;
      end;
      i := i - ADir;
    end;
  FDesigner.Modified;
  PushSelectionToDesigner(true);
end;

procedure TComponentListEditorForm.RefreshList;
var
  ci: TStrings;
  i: Integer;
  lst: TList;
begin
  ci := FChildrenListBox.Items;
  ci.BeginUpdate;
  try
    ci.Clear;
    lst := GetChildrenList;
    for i := 0 to lst.Count - 1 do
      ci.AddObject(TComponent(lst[i]).Name, TObject(lst[i]));
  finally
    ci.EndUpdate;
  end;
end;

procedure TComponentListEditorForm.PushSelectionToDesigner(
  AOrderChanged: Boolean);
var
  sel: IDesignerSelections;
  i: Integer;
begin
  if (FDesigner = nil) or FUpdatingSelection then exit;
  FUpdatingSelection := true;
  try
    sel := CreateSelectionList;
    for i := 0 to FChildrenListBox.Count - 1 do
      if FChildrenListBox.Selected[i] then
        sel.Add(TPersistent(FChildrenListBox.Items.Objects[i]));
    if (sel.Count = 0) and not AOrderChanged then
      FDesigner.SelectComponent(FParent)
    else
      FDesigner.SetSelections(sel);
  finally
    FUpdatingSelection := false;
  end;
end;

{ IDesignNotification }

procedure TComponentListEditorForm.ItemDeleted(
  const ADesigner: IDesigner; AItem: TPersistent);
var
  i, wasSelected: Integer;
begin
  if AItem = FParent then begin
    Release;
    exit;
  end;
  if not FindChild(AItem, i) then exit;
  with FChildrenListBox do begin
    wasSelected := ItemIndex;
    Items.Delete(i);
    ItemIndex := Min(wasSelected, Count - 1);
  end;
end;

procedure TComponentListEditorForm.ItemInserted(
  const ADesigner: IDesigner; AItem: TPersistent);
var
  s: TComponent;
begin
  if (AItem = nil) or not (AItem is ChildClass) then exit;
  s := AItem as TComponent;
  if s.GetParentComponent <> FParent then exit;
  if FChildrenListBox.Items.IndexOfObject(s) < 0 then
    FChildrenListBox.Items.AddObject(s.Name, s);
end;

procedure TComponentListEditorForm.ItemsModified(const ADesigner: IDesigner);
var
  i: Integer;
begin
  // Names may have changed.
  for i := 0 to FChildrenListBox.Count - 1 do
    FChildrenListBox.Items[i] := TComponent(FChildrenListBox.Items.Objects[i]).Name;
  if FParent <> nil then
    BuildCaption;
end;

procedure TComponentListEditorForm.SelectionChanged(
  const ADesigner: IDesigner; const ASelection: IDesignerSelections);
var
  i, j: Integer;
begin
  if (ASelection = nil) or FUpdatingSelection then exit;
  FUpdatingSelection := true;
  try
    FChildrenListBox.ClearSelection;
    for i := 0 to ASelection.Count - 1 do
      if FindChild(ASelection[i], j) then
        FChildrenListBox.Selected[j] := true;
  finally
    FUpdatingSelection := false;
  end;
end;

procedure TComponentListEditorForm.DesignerOpened(
  const ADesigner: IDesigner; AResurrecting: Boolean);
begin
  // Nothing to do.
end;

procedure TComponentListEditorForm.DesignerClosed(
  const ADesigner: IDesigner; AGoingDormant: Boolean);
begin
  if ADesigner = FDesigner then
    Release;
end;

initialization

finalization
  FreeAndNil(VEditorForms);
  FreeAndNil(VEditorParents);

end.
