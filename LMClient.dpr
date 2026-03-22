program LMClient;

uses
  Vcl.Forms,
  formLMClient in 'formLMClient.pas' {Form49};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm49, Form49);
  Application.Run;
end.
