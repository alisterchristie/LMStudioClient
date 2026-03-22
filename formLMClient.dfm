object Form49: TForm49
  Left = 0
  Top = 0
  Caption = 'LM Studio Client'
  ClientHeight = 708
  ClientWidth = 810
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object Memo1: TMemo
    AlignWithMargins = True
    Left = 3
    Top = 41
    Width = 804
    Height = 112
    Align = alTop
    Lines.Strings = (
      'Write me a story')
    TabOrder = 0
    ExplicitLeft = -2
    ExplicitTop = 37
    ExplicitWidth = 998
  end
  object EdgeBrowser1: TEdgeBrowser
    AlignWithMargins = True
    Left = 3
    Top = 159
    Width = 804
    Height = 546
    Align = alClient
    TabOrder = 1
    AllowSingleSignOnUsingOSPrimaryAccount = False
    TargetCompatibleBrowserVersion = '137.0.3296.44'
    UserDataFolder = '%LOCALAPPDATA%\bds.exe.WebView2'
    OnNavigationCompleted = EdgeBrowser1NavigationCompleted
    ExplicitLeft = 36
    ExplicitTop = 287
    ExplicitWidth = 960
    ExplicitHeight = 218
  end
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 810
    Height = 38
    Align = alTop
    BevelOuter = bvNone
    Caption = 'pnlTop'
    ShowCaption = False
    TabOrder = 2
    object lblHost: TLabel
      Left = 144
      Top = 13
      Width = 28
      Height = 15
      Caption = 'Host:'
    end
    object lblPort: TLabel
      Left = 378
      Top = 13
      Width = 25
      Height = 15
      Caption = 'Port:'
    end
    object edtHost: TEdit
      Left = 178
      Top = 10
      Width = 184
      Height = 23
      TabOrder = 0
      Text = 'localhost'
    end
    object edtPort: TEdit
      Left = 409
      Top = 10
      Width = 56
      Height = 23
      TabOrder = 1
      Text = '1234'
    end
    object Button1: TButton
      Left = 3
      Top = 10
      Width = 105
      Height = 23
      Caption = 'Ask'
      TabOrder = 2
      OnClick = Button1Click
    end
  end
end
