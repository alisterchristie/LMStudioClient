program LMClient;

uses
  Vcl.Forms,
  formLMClient in 'formLMClient.pas' {frmLMClient};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmLMClient, frmLMClient);
  Application.Run;
end.
