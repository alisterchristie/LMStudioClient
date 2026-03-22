unit formLMClient;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Winapi.WebView2,
  Winapi.ActiveX, Vcl.Edge;

type
  TForm49 = class(TForm)
    Button1: TButton;
    Memo1: TMemo;
    mmoResponse: TMemo;
    EdgeBrowser1: TEdgeBrowser;
    lblHost: TLabel;
    edtHost: TEdit;
    lblPort: TLabel;
    edtPort: TEdit;
    procedure Button1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    function AskLMStudio(const APrompt: string): string;
    procedure ShowMarkdown(const AMarkdown: string);
    procedure LoadSettings;
    procedure SaveSettings;
  public
    { Public declarations }
  end;

var
  Form49: TForm49;

implementation

uses
  System.Net.HttpClient, System.Net.HttpClientComponent,
  System.JSON, System.IOUtils, IniFiles;

{$R *.dfm}

const
  CPageCSS =
    'body{font-family:Segoe UI,sans-serif;margin:16px;line-height:1.6}' +
    'pre{background:#f5f5f5;padding:12px;border-radius:4px;overflow-x:auto;font-size:.9em}' +
    'code{background:#f5f5f5;padding:2px 5px;border-radius:3px;font-size:.9em}' +
    'pre code{background:none;padding:0}' +
    'h1,h2,h3,h4{margin:.8em 0 .3em}ul,ol{padding-left:1.5em}p{margin:.5em 0}';

  // Inline markdown renderer — no CDN, no timing issues
  CRenderJS =
    'function render(md){' +
    'function esc(s){return s.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;")}' +
    'function inl(s){return s.replace(/`([^`]+)`/g,"<code>$1</code>")' +
    '.replace(/\*\*([^*\n]+)\*\*/g,"<strong>$1</strong>")' +
    '.replace(/\*([^*\n]+)\*/g,"<em>$1</em>")}' +
    'var o="",pre=false,ul=false,buf="";' +
    'function fl(){if(buf){o+="<p>"+inl(esc(buf.trim()))+"</p>";buf=""}}' +
    'md.split("\n").forEach(function(l){' +
      'if(pre){if(l.startsWith("```")){o+="</code></pre>";pre=false}else o+=esc(l)+"\n";return}' +
      'if(l.startsWith("```")){fl();if(ul){o+="</ul>";ul=false}o+="<pre><code>";pre=true;return}' +
      'var h=l.match(/^(#{1,6}) (.*)/);' +
      'if(h){fl();if(ul){o+="</ul>";ul=false}o+="<h"+h[1].length+">"+inl(esc(h[2]))+"</h"+h[1].length+">";return}' +
      'var li=l.match(/^[-*+] (.*)/);' +
      'if(li){fl();if(!ul){o+="<ul>";ul=true}o+="<li>"+inl(esc(li[1]))+"</li>";return}' +
      'if(!l.trim()){fl();if(ul){o+="</ul>";ul=false}return}' +
      'buf+=(buf?"\n":"")+l' +
    '});fl();if(ul)o+="</ul>";return o}';

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
  SaveSettings;
end;

procedure TForm49.ShowMarkdown(const AMarkdown: string);
var
  JSStr: TJSONString;
  Encoded: string;
begin
  JSStr := TJSONString.Create(AMarkdown);
  try
    // Break up any </script> sequence that would end the script tag early
    Encoded := StringReplace(JSStr.ToJSON, '</', '<\/', [rfReplaceAll]);
  finally
    JSStr.Free;
  end;
  var HTML :=
    '<!DOCTYPE html><html><head><meta charset="utf-8"><style>' + CPageCSS +
    '</style></head><body><div id="c"></div><script>' + CRenderJS +
    'document.getElementById("c").innerHTML=render(' + Encoded + ')' +
    '</script></body></html>';
  var TempFile := TPath.Combine(TPath.GetTempPath, 'lmclient_response.html');
  TFile.WriteAllText(TempFile, HTML, TEncoding.UTF8);
  EdgeBrowser1.Navigate('file:///' +
    StringReplace(TempFile, '\', '/', [rfReplaceAll]));
end;

function TForm49.AskLMStudio(const APrompt: string): string;
var
  Client: TNetHTTPClient;
  Response: IHTTPResponse;
  RequestBody: TStringStream;
  JSONRequest, JSONResponse: TJSONObject;
  JSONMessages: TJSONArray;
  ResultText: string;
  URL: string;
begin
  Result := '';
  URL := 'http://' + edtHost.Text + ':' + edtPort.Text + '/v1/chat/completions';
  Client := TNetHTTPClient.Create(nil);
  try
    JSONRequest := TJSONObject.Create;
    JSONMessages := TJSONArray.Create;
    try
      Client.ResponseTimeout := 180_000; //3 minutes
      // Build messages array
      JSONMessages.Add(
        TJSONObject.Create
          .AddPair('role', 'user')
          .AddPair('content', APrompt)
      );

      JSONRequest.AddPair('model', 'local-model'); // any string works
      JSONRequest.AddPair('messages', JSONMessages);
      JSONRequest.AddPair('temperature', TJSONNumber.Create(0.7));

      RequestBody := TStringStream.Create(
        JSONRequest.ToString, TEncoding.UTF8);
      try
        Client.ContentType := 'application/json';
        Response := Client.Post(URL, RequestBody);

        // Parse response
        JSONResponse := TJSONObject.ParseJSONValue(
          Response.ContentAsString) as TJSONObject;
        try
          ResultText := JSONResponse
            .GetValue<TJSONArray>('choices')
            .Items[0]
            .GetValue<TJSONObject>('message')
            .GetValue<string>('content');

          Result := ResultText;
        finally
          JSONResponse.Free;
        end;
      finally
        RequestBody.Free;
      end;
    finally
      JSONRequest.Free;
    end;
  finally
    Client.Free;
  end;
end;


procedure TForm49.Button1Click(Sender: TObject);
var
  Response: string;
begin
  Response := AskLMStudio(Memo1.Text);
  mmoResponse.Text := Response;
  ShowMarkdown(Response);
end;

end.
