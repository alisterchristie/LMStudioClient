object Form49: TForm49
  Left = 0
  Top = 0
  Caption = 'LM Studio Client'
  ClientHeight = 441
  ClientWidth = 1004
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object lblHost: TLabel
    Left = 8
    Top = 28
    Width = 28
    Height = 15
    Caption = 'Host:'
  end
  object lblPort: TLabel
    Left = 242
    Top = 28
    Width = 25
    Height = 15
    Caption = 'Port:'
  end
  object edtHost: TEdit
    Left = 48
    Top = 24
    Width = 184
    Height = 23
    TabOrder = 0
    Text = 'localhost'
  end
  object edtPort: TEdit
    Left = 274
    Top = 24
    Width = 56
    Height = 23
    TabOrder = 1
    Text = '1234'
  end
  object Button1: TButton
    Left = 348
    Top = 24
    Width = 75
    Height = 23
    Caption = 'Ask'
    TabOrder = 2
    OnClick = Button1Click
  end
  object Memo1: TMemo
    Left = 32
    Top = 55
    Width = 457
    Height = 154
    Lines.Strings = (
      'Write me a story')
    TabOrder = 3
  end
  object mmoResponse: TMemo
    Left = 32
    Top = 215
    Width = 457
    Height = 186
    Lines.Strings = (
      'mmoResponse')
    TabOrder = 4
  end
  object EdgeBrowser1: TEdgeBrowser
    Left = 512
    Top = 55
    Width = 484
    Height = 338
    TabOrder = 5
    AllowSingleSignOnUsingOSPrimaryAccount = False
    TargetCompatibleBrowserVersion = '137.0.3296.44'
    UserDataFolder = '%LOCALAPPDATA%\bds.exe.WebView2'
  end
end
