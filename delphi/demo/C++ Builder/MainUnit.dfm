object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'TAChart OpenGL demo'
  ClientHeight = 614
  ClientWidth = 875
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnShow = FormShow
  TextHeight = 15
  object ControlPanel: TPanel
    Left = 0
    Top = 0
    Width = 875
    Height = 100
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblCount: TLabel
      Left = 8
      Top = 12
      Width = 47
      Height = 15
      Caption = 'Samples:'
    end
    object lblStats: TLabel
      Left = 8
      Top = 40
      Width = 855
      Height = 55
      AutoSize = False
      Caption = '(loading)'
      WordWrap = True
    end
    object cbCount: TComboBox
      Left = 62
      Top = 8
      Width = 124
      Height = 23
      Style = csDropDownList
      TabOrder = 0
      Items.Strings = (
        '100,000'
        '1,000,000'
        '5,000,000'
        '10,000,000')
    end
    object btnLoad: TButton
      Left = 196
      Top = 7
      Width = 80
      Height = 25
      Caption = 'Load'
      TabOrder = 1
      OnClick = btnLoadClick
    end
    object chkDecimate: TCheckBox
      Left = 296
      Top = 11
      Width = 85
      Height = 17
      Caption = 'Decimate'
      Checked = True
      State = cbChecked
      TabOrder = 2
      OnClick = chkDecimateClick
    end
    object chkAnimate: TCheckBox
      Left = 388
      Top = 11
      Width = 80
      Height = 17
      Caption = 'Animate'
      TabOrder = 3
      OnClick = chkAnimateClick
    end
    object chkOpenGL: TCheckBox
      Left = 474
      Top = 11
      Width = 80
      Height = 17
      Caption = 'OpenGL'
      Checked = True
      State = cbChecked
      TabOrder = 4
      OnClick = chkOpenGLClick
    end
  end
  object TAChartGL1: TTAChartGL
    Left = 0
    Top = 100
    Width = 875
    Height = 514
    AxisList = <
      item
        Marks.LabelFont.Charset = DEFAULT_CHARSET
        Marks.LabelFont.Color = clWindowText
        Marks.LabelFont.Height = -12
        Marks.LabelFont.Name = 'Segoe UI'
        Marks.LabelFont.Style = []
        Minors = <>
        Title.LabelFont.Charset = DEFAULT_CHARSET
        Title.LabelFont.Color = clWindowText
        Title.LabelFont.Height = -12
        Title.LabelFont.Name = 'Segoe UI'
        Title.LabelFont.Orientation = 900
        Title.LabelFont.Style = []
      end
      item
        Alignment = calBottom
        Marks.LabelFont.Charset = DEFAULT_CHARSET
        Marks.LabelFont.Color = clWindowText
        Marks.LabelFont.Height = -12
        Marks.LabelFont.Name = 'Segoe UI'
        Marks.LabelFont.Style = []
        Minors = <>
        Title.LabelFont.Charset = DEFAULT_CHARSET
        Title.LabelFont.Color = clWindowText
        Title.LabelFont.Height = -12
        Title.LabelFont.Name = 'Segoe UI'
        Title.LabelFont.Style = []
      end>
    Foot.Brush.Color = clBtnFace
    Foot.Font.Charset = DEFAULT_CHARSET
    Foot.Font.Color = clBlue
    Foot.Font.Height = -12
    Foot.Font.Name = 'Segoe UI'
    Foot.Font.Style = []
    Legend.Font.Charset = DEFAULT_CHARSET
    Legend.Font.Color = clWindowText
    Legend.Font.Height = -12
    Legend.Font.Name = 'Segoe UI'
    Legend.Font.Style = []
    Legend.GroupFont.Charset = DEFAULT_CHARSET
    Legend.GroupFont.Color = clWindowText
    Legend.GroupFont.Height = -12
    Legend.GroupFont.Name = 'Segoe UI'
    Legend.GroupFont.Style = []
    Legend.Visible = True
    Title.Brush.Color = clBtnFace
    Title.Font.Charset = DEFAULT_CHARSET
    Title.Font.Color = clBlue
    Title.Font.Height = -16
    Title.Font.Name = 'Segoe UI'
    Title.Font.Style = []
    Title.Text.Strings = (
      'TAChart')
    Title.Visible = True
    Align = alClient
    object Series: TFastLineSeries
    end
  end
  object Timer: TTimer
    Interval = 16
    OnTimer = TimerTimer
    Left = 720
    Top = 152
  end
end
