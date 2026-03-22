object Form49: TForm49
  Left = 0
  Top = 0
  Caption = 'Form49'
  ClientHeight = 441
  ClientWidth = 1004
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  TextHeight = 15
  object Button1: TButton
    Left = 32
    Top = 24
    Width = 75
    Height = 25
    Caption = 'Button1'
    TabOrder = 0
    OnClick = Button1Click
  end
  object Memo1: TMemo
    Left = 32
    Top = 55
    Width = 457
    Height = 154
    Lines.Strings = (
      'Write me a story')
    TabOrder = 1
  end
  object mmoResponse: TMemo
    Left = 32
    Top = 215
    Width = 457
    Height = 186
    Lines.Strings = (
      'mmoResponse')
    TabOrder = 2
  end
  object EdgeBrowser1: TEdgeBrowser
    Left = 512
    Top = 55
    Width = 484
    Height = 338
    TabOrder = 3
    AllowSingleSignOnUsingOSPrimaryAccount = False
    TargetCompatibleBrowserVersion = '137.0.3296.44'
    UserDataFolder = '%LOCALAPPDATA%\bds.exe.WebView2'
  end
end
