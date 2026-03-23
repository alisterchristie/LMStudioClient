unit StreamThread;

// Streams an OpenAI-compatible SSE response from a local LM Studio instance.
// Parses each 'data: {...}' line, extracts choices[0].delta.content, and
// delivers it to the caller via AOnChunk (invoked on the main thread).
// AOnDone is called on the main thread when the stream ends cleanly.

interface

uses
  System.Classes,
  System.SysUtils;

type
  TStreamThread = class(TThread)
  private
    FHost: string;
    FPort: Word;
    FRequestBody: string;
    FSession: Pointer; // HINTERNET — kept as Pointer to isolate WinHTTP from the interface
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
    // Signals the thread to stop and unblocks any pending WinHTTP call.
    procedure Cancel;
  end;

implementation

uses
  Winapi.Windows,
  System.JSON,
  System.Generics.Collections;

// ---- WinHTTP API ----

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

// ---- TStreamThread ----

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
    WinHttpCloseHandle(FSession); // unblocks any pending WinHTTP call
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
          if Available = 0 then Break;
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
    // reference to the anonymous method object. Without this, FreeAndNil
    // inside the callback drops the ref count to zero mid-execution.
    var DoneProc := FOnDone;
    TThread.Queue(nil, procedure begin DoneProc(); end);
  end;
end;

end.
