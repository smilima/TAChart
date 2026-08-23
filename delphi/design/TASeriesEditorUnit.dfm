object SeriesGalleryForm: TSeriesGalleryForm
  Left = 0
  Top = 0
  Caption = 'Edit series'
  ClientHeight = 561
  ClientWidth = 644
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnResize = FormResize
  TextHeight = 15
  object GalleryGrid: TDrawGrid
    Left = 0
    Top = 0
    Width = 644
    Height = 520
    Align = alClient
    ColCount = 4
    DefaultColWidth = 156
    DefaultDrawing = False
    DefaultRowHeight = 140
    FixedCols = 0
    FixedRows = 0
    RowCount = 1
    Options = [goThumbTracking]
    ScrollBars = ssVertical
    TabOrder = 0
    OnDblClick = GalleryGridDblClick
    OnDrawCell = GalleryGridDrawCell
    OnSelectCell = GalleryGridSelectCell
  end
  object ButtonPanel: TPanel
    Left = 0
    Top = 520
    Width = 644
    Height = 41
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object OKButton: TButton
      Left = 466
      Top = 6
      Width = 84
      Height = 27
      Anchors = [akTop, akRight]
      Caption = 'OK'
      Default = True
      ModalResult = 1
      TabOrder = 0
    end
    object CancelButton: TButton
      Left = 556
      Top = 6
      Width = 84
      Height = 27
      Anchors = [akTop, akRight]
      Cancel = True
      Caption = 'Cancel'
      ModalResult = 2
      TabOrder = 1
    end
  end
end
