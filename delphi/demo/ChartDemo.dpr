program ChartDemo;

{$APPTYPE GUI}

uses
  Vcl.Forms,
  System.SysUtils,
  ChartDemoMain in 'ChartDemoMain.pas';

{$R *.res}

var
  frm: TDemoForm;
  outFile: String;
begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;

  // --render <file> draws the chart to a PNG and exits; used as a smoke test.
  if (ParamCount >= 2) and SameText(ParamStr(1), '--render') then begin
    outFile := ParamStr(2);
    frm := TDemoForm.CreateNew(Application);
    try
      frm.RenderToFile(outFile);
      frm.RenderExtrasToFile(ChangeFileExt(outFile, '') + '-extras.png');
    finally
      frm.Free;
    end;
    Halt(0);
  end;

  Application.CreateForm(TDemoForm, frm);
  Application.Run;
end.
