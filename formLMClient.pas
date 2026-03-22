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
    FStreamThread: TThread;
    procedure ShowMarkdown(const AMarkdown: string);
    procedure LoadSettings;
    procedure SaveSettings;
    function BuildRequestJSON(const APrompt: string): string;
    procedure StartStreaming(const APrompt: string);
  public
  end;

var
  Form49: TForm49;

implementation

uses
  System.JSON, System.IOUtils, IniFiles;

// ---- WinHTTP API (streaming-capable Windows HTTP) ----

type
  HINTERNET = Pointer;

const
  WINHTTP_ACCESS_TYPE_DEFAULT_PROXY = 0;
  WINHTTP_ADDREQ_FLAG_ADD           = $20000000;

function WinHttpOpen(pszUserAgent: PWideChar; dwAccessType: DWORD;
  pszProxyName, pszProxyBypass: PWideChar; dwFlags: DWORD): HINTERNET;
  stdcall; external 'winhttp.dll';
function WinHttpConnect(hSession: HINTERNET; pswzServerName: PWideChar;
  nServerPort: Word; dwReserved: DWORD): HINTERNET;
  stdcall; external 'winhttp.dll';
function WinHttpOpenRequest(hConnect: HINTERNET;
  pwszVerb, pwszObjectName, pwszVersion, pwszReferrer,
  ppwszAcceptTypes: PWideChar; dwFlags: DWORD): HINTERNET;
  stdcall; external 'winhttp.dll';
function WinHttpAddRequestHeaders(hRequest: HINTERNET;
  pwszHeaders: PWideChar; dwHeadersLength, dwModifiers: DWORD): BOOL;
  stdcall; external 'winhttp.dll';
function WinHttpSendRequest(hRequest: HINTERNET;
  pwszHeaders: PWideChar; dwHeadersLength: DWORD;
  lpOptional: Pointer; dwOptionalLength, dwTotalLength, dwContext: DWORD): BOOL;
  stdcall; external 'winhttp.dll';
function WinHttpReceiveResponse(hRequest: HINTERNET; lpReserved: Pointer): BOOL;
  stdcall; external 'winhttp.dll';
function WinHttpQueryDataAvailable(hRequest: HINTERNET;
  lpdwNumberOfBytesAvailable: PDWORD): BOOL;
  stdcall; external 'winhttp.dll';
function WinHttpReadData(hRequest: HINTERNET; lpBuffer: Pointer;
  dwNumberOfBytesToRead: DWORD; lpdwNumberOfBytesRead: PDWORD): BOOL;
  stdcall; external 'winhttp.dll';
function WinHttpCloseHandle(hInternet: HINTERNET): BOOL;
  stdcall; external 'winhttp.dll';

{$R *.dfm}

// ---- Streaming thread ----
//
// Reads the SSE response from LM Studio chunk by chunk.
// Each 'data: {...}' line is parsed and choices[0].delta.content
// is extracted and delivered to FOnChunk (on the main thread).
// FOnDone is called on the main thread when the stream ends cleanly.

type
  TStreamThread = class(TThread)
  private
    FHost: string;
    FPort: Word;
    FRequestBody: string;
    FSession: HINTERNET;
    FOnChunk: TProc<string>;
    FOnDone: TProc;
    procedure ProcessSSEBuffer(var ABuffer: string);
    function ExtractChunkText(const AJSON: string): string;
  protected
    procedure Execute; override;
  public
    constructor Create(const AHost: string; APort: Word;
      const ARequestBody: string;
      AOnChunk: TProc<string>; AOnDone: TProc);
    procedure Cancel;
  end;

constructor TStreamThread.Create(const AHost: string; APort: Word;
  const ARequestBody: string; AOnChunk: TProc<string>; AOnDone: TProc);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FHost        := AHost;
  FPort        := APort;
  FRequestBody := ARequestBody;
  FOnChunk     := AOnChunk;
  FOnDone      := AOnDone;
  FSession     := nil;
end;

procedure TStreamThread.Cancel;
begin
  Terminate;
  if FSession <> nil then
    WinHttpCloseHandle(FSession); // unblocks any pending WinHttp call
end;

function TStreamThread.ExtractChunkText(const AJSON: string): string;
var
  Root: TJSONObject;
  Choices: TJSONArray;
  Choice, Delta: TJSONObject;
begin
  Result := '';
  Root := TJSONObject.ParseJSONValue(AJSON) as TJSONObject;
  if Root = nil then Exit;
  try
    Choices := Root.GetValue<TJSONArray>('choices');
    if (Choices = nil) or (Choices.Count = 0) then Exit;
    Choice := Choices.Items[0] as TJSONObject;
    if Choice = nil then Exit;
    Delta := Choice.GetValue<TJSONObject>('delta');
    if Delta = nil then Exit;
    Delta.TryGetValue<string>('content', Result);
  finally
    Root.Free;
  end;
end;

procedure TStreamThread.ProcessSSEBuffer(var ABuffer: string);
var
  NLPos: Integer;
  Line, Data, Chunk: string;
begin
  while True do
  begin
    NLPos := ABuffer.IndexOf(#10);
    if NLPos < 0 then Break;
    Line    := ABuffer.Substring(0, NLPos).TrimRight([#13]);
    ABuffer := ABuffer.Substring(NLPos + 1);
    if not Line.StartsWith('data: ') then Continue;
    Data  := Line.Substring(6);
    if Data = '[DONE]' then Continue;
    Chunk := ExtractChunkText(Data);
    if Chunk = '' then Continue;
    TThread.Synchronize(Self, procedure
    begin
      FOnChunk(Chunk);
    end);
  end;
end;

procedure TStreamThread.Execute;
const
  BUF_SIZE = 8192;
var
  Connection, Request: HINTERNET;
  BodyBytes: TBytes;
  RawBuf: TBytes;
  Available, BytesRead: DWORD;
  LineBuffer: string;
begin
  FSession := WinHttpOpen('LMClient/1.0', WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
    nil, nil, 0);
  if FSession = nil then Exit;
  try
    Connection := WinHttpConnect(FSession, PWideChar(FHost), FPort, 0);
    if Connection = nil then Exit;
    try
      Request := WinHttpOpenRequest(Connection, 'POST',
        '/v1/chat/completions', nil, nil, nil, 0);
      if Request = nil then Exit;
      try
        WinHttpAddRequestHeaders(Request,
          'Content-Type: application/json'#13#10,
          DWORD(-1), WINHTTP_ADDREQ_FLAG_ADD);

        BodyBytes := TEncoding.UTF8.GetBytes(FRequestBody);
        if not WinHttpSendRequest(Request, nil, 0,
          Pointer(BodyBytes), Length(BodyBytes), Length(BodyBytes), 0) then Exit;
        if not WinHttpReceiveResponse(Request, nil) then Exit;

        LineBuffer := '';
        SetLength(RawBuf, BUF_SIZE);
        while not Terminated do
        begin
          Available := 0;
          if not WinHttpQueryDataAvailable(Request, @Available) then Break;
          if Available = 0 then Break; // server closed the stream
          if Available > BUF_SIZE then Available := BUF_SIZE;
          BytesRead := 0;
          if not WinHttpReadData(Request, Pointer(RawBuf),
            Available, @BytesRead) then Break;
          if BytesRead = 0 then Break;
          LineBuffer := LineBuffer +
            TEncoding.UTF8.GetString(RawBuf, 0, Integer(BytesRead));
          ProcessSSEBuffer(LineBuffer);
        end;
      finally
        if Request <> nil then WinHttpCloseHandle(Request);
      end;
    finally
      if Connection <> nil then WinHttpCloseHandle(Connection);
    end;
  finally
    if FSession <> nil then
    begin
      WinHttpCloseHandle(FSession);
      FSession := nil;
    end;
  end;

  if not Terminated then
  begin
    // Capture FOnDone by value so the queue wrapper holds its own strong
    // reference to the anonymous method object. Without this, the wrapper
    // only holds a pointer to Self (TStreamThread) and reads Self.FOnDone
    // at call time — but FreeAndNil(FStreamThread) inside the callback
    // drops the ref count to zero and frees the object mid-execution.
    var DoneProc := FOnDone;
    TThread.Queue(nil, procedure begin DoneProc(); end);
  end;
end;

// ---- Page rendering constants ----

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

// ---- Markdown display ----

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

// ---- Streaming ----

procedure TForm49.StartStreaming(const APrompt: string);
begin
  mmoResponse.Clear;
  Button1.Enabled := False;
  Button1.Caption := 'Asking…';

  FStreamThread := TStreamThread.Create(
    edtHost.Text,
    StrToIntDef(edtPort.Text, 1234),
    BuildRequestJSON(APrompt),
    procedure(AText: string) // called on main thread per chunk
    begin
      mmoResponse.Text := mmoResponse.Text + AText;
    end,
    procedure // called on main thread when stream ends
    begin
      FreeAndNil(FStreamThread);
      Button1.Enabled := True;
      Button1.Caption := 'Ask';
      ShowMarkdown(mmoResponse.Text);
    end
  );
end;

procedure TForm49.Button1Click(Sender: TObject);
begin
  StartStreaming(Memo1.Text);
end;

end.
