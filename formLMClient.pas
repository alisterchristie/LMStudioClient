unit formLMClient;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Winapi.WebView2,
  Winapi.ActiveX, Vcl.Edge, Vcl.ExtCtrls;

type
  TForm49 = class(TForm)
    Button1: TButton;
    Memo1: TMemo;
    EdgeBrowser1: TEdgeBrowser;
    lblHost: TLabel;
    edtHost: TEdit;
    lblPort: TLabel;
    edtPort: TEdit;
    pnlTop: TPanel;
    procedure Button1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure EdgeBrowser1NavigationCompleted(Sender: TCustomEdgeBrowser;
      IsSuccess: Boolean; WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
  private
    FStreamThread: TThread;
    FPageReady: Boolean;
    FAccumulatedText: string;
    procedure LoadSettings;
    procedure SaveSettings;
    function BuildRequestJSON(const APrompt: string): string;
    procedure StartStreaming(const APrompt: string);
    procedure UpdateEdgeBrowser;
  public
  end;

var
  Form49: TForm49;

implementation

uses
  System.JSON, System.IOUtils, IniFiles,
  StreamThread;

{$R *.dfm}

// ---- Page template ----

const
  CPageCSS =
    'body{font-family:Segoe UI,sans-serif;margin:16px;line-height:1.6}' +
    'pre{background:#f5f5f5;padding:12px;border-radius:4px;overflow-x:auto;font-size:.9em}' +
    'code{background:#f5f5f5;padding:2px 5px;border-radius:3px;font-size:.9em}' +
    'pre code{background:none;padding:0}' +
    'h1,h2,h3,h4{margin:.8em 0 .3em}ul,ol{padding-left:1.5em}p{margin:.5em 0}' +
    'table{border-collapse:collapse;width:100%;margin:.5em 0}' +
    'th,td{border:1px solid #ddd;padding:6px 10px;text-align:left}' +
    'th{background:#f0f0f0;font-weight:600}' +
    'tr:nth-child(even){background:#fafafa}' +
    'blockquote{border-left:3px solid #ccc;margin:0 0 .5em;padding:.2em .8em;color:#555}' +
    'del{text-decoration:line-through}' +
    'hr{border:none;border-top:1px solid #ddd;margin:1em 0}';

  // Inline markdown renderer — no CDN, no timing issues
  CRenderJS =
    'function render(md){' +
    'function esc(s){return s.replace(/&/g,''&amp;'').replace(/</g,''&lt;'').replace(/>/g,''&gt;'')}' +
    'function inl(s){return esc(s)' +
    '.replace(/`([^`]+)`/g,''<code>$1</code>'')' +
    '.replace(/\*\*([^*\n]+)\*\*/g,''<strong>$1</strong>'')' +
    '.replace(/\*([^*\n]+)\*/g,''<em>$1</em>'')' +
    '.replace(/~~([^~\n]+)~~/g,''<del>$1</del>'')}' +
    'function cells(r){return r.replace(/^\||\|$/g,'''').split(''|'').map(function(c){return c.trim()})}' +
    'function isSep(s){return /^[\s|:\-]+$/.test(s)&&s.indexOf(''|'')>=0&&s.indexOf(''-'')>=0}' +
    'var lines=md.split(''\n''),i=0,out='''';' +
    'while(i<lines.length){var L=lines[i];' +
    'if(!L.trim()){i++;continue}' +
    'if(/^```/.test(L)){var code='''';i++;' +
    'while(i<lines.length&&!/^```/.test(lines[i])){code+=esc(lines[i])+''\n'';i++}' +
    'i++;out+=''<pre><code>''+code+''</code></pre>'';continue}' +
    'var hm=L.match(/^(#{1,6}) (.*)/);' +
    'if(hm){out+=''<h''+hm[1].length+''>''+inl(hm[2])+''</h''+hm[1].length+''>'';i++;continue}' +
    'if(/^([-*_]){3,}\s*$/.test(L)){out+=''<hr>'';i++;continue}' +
    'if(/^>/.test(L)){var bq='''';' +
    'while(i<lines.length&&/^>/.test(lines[i])){bq+=lines[i].slice(1)+''\n'';i++}' +
    'out+=''<blockquote>''+render(bq)+''</blockquote>'';continue}' +
    'if(i+1<lines.length&&isSep(lines[i+1])){var hdrs=cells(L);i+=2;' +
    'out+=''<table><thead><tr>'';' +
    'hdrs.forEach(function(h){out+=''<th>''+inl(h)+''</th>''});' +
    'out+=''</tr></thead><tbody>'';' +
    'while(i<lines.length&&lines[i].trim()&&lines[i].indexOf(''|'')>=0){' +
    'out+=''<tr>'';cells(lines[i]).forEach(function(c){out+=''<td>''+inl(c)+''</td>''});' +
    'out+=''</tr>'';i++}' +
    'out+=''</tbody></table>'';continue}' +
    'if(/^[-*+] /.test(L)){out+=''<ul>'';' +
    'while(i<lines.length&&/^[-*+] /.test(lines[i])){out+=''<li>''+inl(lines[i].slice(2))+''</li>'';i++}' +
    'out+=''</ul>'';continue}' +
    'if(/^\d+\. /.test(L)){out+=''<ol>'';' +
    'while(i<lines.length&&/^\d+\. /.test(lines[i])){out+=''<li>''+inl(lines[i].replace(/^\d+\.\s+/,''''))+''</li>'';i++}' +
    'out+=''</ol>'';continue}' +
    'var p='''';' +
    'while(i<lines.length&&lines[i].trim()' +
    '&&!/^(#{1,6} |```|>|[-*+] |\d+\. )/.test(lines[i])' +
    '&&!/^([-*_]){3,}\s*$/.test(lines[i])' +
    '&&!(i+1<lines.length&&isSep(lines[i+1]))){' +
    'p+=(p?''\n'':'''')+lines[i];i++}' +
    'if(p)out+=''<p>''+inl(p)+''</p>''}' +
    'return out}';

// ---- Settings ----

function IniFilePath: string;
begin
  Result := ChangeFileExt(Application.ExeName, '.ini');
end;

procedure TForm49.LoadSettings;
begin
  var Ini := TIniFile.Create(IniFilePath);
  try
    edtHost.Text := Ini.ReadString('Connection', 'Host', 'localhost');
    edtPort.Text := Ini.ReadString('Connection', 'Port', '1234');
  finally
    Ini.Free;
  end;
end;

procedure TForm49.SaveSettings;
begin
  var Ini := TIniFile.Create(IniFilePath);
  try
    Ini.WriteString('Connection', 'Host', edtHost.Text);
    Ini.WriteString('Connection', 'Port', edtPort.Text);
  finally
    Ini.Free;
  end;
end;

procedure TForm49.FormCreate(Sender: TObject);
begin
  LoadSettings;
end;

procedure TForm49.FormDestroy(Sender: TObject);
begin
  if Assigned(FStreamThread) then
  begin
    TStreamThread(FStreamThread).Cancel;
    FStreamThread.WaitFor;
    FreeAndNil(FStreamThread);
  end;
  SaveSettings;
end;

// ---- Request building ----

function TForm49.BuildRequestJSON(const APrompt: string): string;
var
  JSONRequest: TJSONObject;
  JSONMessages: TJSONArray;
begin
  JSONMessages := TJSONArray.Create;
  JSONMessages.Add(
    TJSONObject.Create
      .AddPair('role', 'user')
      .AddPair('content', APrompt)
  );

  JSONRequest := TJSONObject.Create;
  try
    JSONRequest.AddPair('model', 'local-model'); // any string works
    JSONRequest.AddPair('messages', JSONMessages);
    JSONRequest.AddPair('temperature', TJSONNumber.Create(0.7));
    JSONRequest.AddPair('stream', TJSONBool.Create(True));
    Result := JSONRequest.ToString;
  finally
    JSONRequest.Free;
  end;
end;

// ---- EdgeBrowser streaming updates ----

procedure TForm49.EdgeBrowser1NavigationCompleted(Sender: TCustomEdgeBrowser;
  IsSuccess: Boolean; WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
begin
  FPageReady := IsSuccess;
  if FPageReady then
    UpdateEdgeBrowser; // render whatever has already arrived
end;

procedure TForm49.UpdateEdgeBrowser;
var
  JSStr: TJSONString;
begin
  if not FPageReady then Exit;
  JSStr := TJSONString.Create(FAccumulatedText);
  try
    EdgeBrowser1.ExecuteScript('update(' + JSStr.ToJSON + ')');
  finally
    JSStr.Free;
  end;
end;

// ---- Streaming ----

procedure TForm49.StartStreaming(const APrompt: string);
var
  TempFile, HTML: string;
begin
  FAccumulatedText := '';
  FPageReady := False;
  Button1.Enabled := False;
  Button1.Caption := 'Asking…';

  // Navigate to skeleton page with render + update functions pre-loaded.
  // ExecuteScript calls are deferred until OnNavigationCompleted fires.
  HTML :=
    '<!DOCTYPE html><html><head><meta charset="utf-8"><style>' + CPageCSS +
    '</style></head><body><div id="c"></div><script>' + CRenderJS +
    'function update(md){document.getElementById(''c'').innerHTML=render(md);' +
    'window.scrollTo(0,document.body.scrollHeight)}</script></body></html>';
  TempFile := TPath.Combine(TPath.GetTempPath, 'lmclient_response.html');
  TFile.WriteAllText(TempFile, HTML, TEncoding.UTF8);
  EdgeBrowser1.Navigate('file:///' + StringReplace(TempFile, '\', '/', [rfReplaceAll]));

  FStreamThread := TStreamThread.Create(
    edtHost.Text,
    StrToIntDef(edtPort.Text, 1234),
    BuildRequestJSON(APrompt),
    procedure(AText: string)
    begin
      FAccumulatedText := FAccumulatedText + AText;
      UpdateEdgeBrowser;
    end,
    procedure
    begin
      FreeAndNil(FStreamThread);
      Button1.Enabled := True;
      Button1.Caption := 'Ask';
      UpdateEdgeBrowser;
    end
  );
end;

procedure TForm49.Button1Click(Sender: TObject);
begin
  StartStreaming(Memo1.Text);
end;

end.
