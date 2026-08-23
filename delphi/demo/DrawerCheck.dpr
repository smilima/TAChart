{
  Smoke test for the non-canvas drawing back-ends of the TAChart Delphi port:

    * TADrawerSVG     -> drawercheck.svg
    * TADrawerWMF     -> drawercheck.emf
    * TADrawerOpenGL  -> drawercheck-gl.png (rendered on a memory-DC OpenGL
                         context, read back with glReadPixels)

  Exit code 0 when every check passes.
}

program DrawerCheck;

{$APPTYPE CONSOLE}

uses
  Winapi.Windows, Winapi.OpenGL,
  System.SysUtils, System.Classes, System.Types, System.Math,
  System.StrUtils, System.IOUtils,
  Vcl.Graphics, Vcl.Forms, Vcl.Imaging.pngimage,
  TAGraph, TASeries, TARadialSeries, TASources, TAChartUtils, TALegend,
  TADrawerSVG, TADrawerWMF, TADrawerOpenGL;

const
  W = 640;
  H = 400;
  GL_BGRA = $80E1;   // not in Winapi.OpenGL's GL 1.1 header

var
  Failures: Integer = 0;

procedure Check(const AName: String; ACondition: Boolean; const ADetail: String = '');
begin
  if not ACondition then Inc(Failures);
  WriteLn(Format('%-46s %s %s',
    [AName, string(IfThen(ACondition, 'ok', '** FAILED **')), ADetail]));
end;

function MakeChart(AOwner: TComponent): TChart;
var
  line: TLineSeries;
  bar: TBarSeries;
  pie: TPieSeries;
  i: Integer;
begin
  Result := TChart.Create(AOwner);
  Result.Width := W;
  Result.Height := H;
  Result.Title.Visible := true;
  Result.Title.Text.Text := 'Drawer smoke test <&>';  // exercises XML escaping
  Result.Legend.Visible := true;
  Result.Legend.Alignment := laBottomCenter;
  Result.Legend.ColumnCount := 3;
  Result.AxisList.LeftAxis.Title.Caption := 'rotated y title';
  Result.AxisList.LeftAxis.Title.Visible := true;

  bar := TBarSeries.Create(Result);
  bar.Title := 'Bars';
  for i := 0 to 7 do
    bar.AddXY(i, 1 + i mod 3);
  Result.AddSeries(bar);

  line := TLineSeries.Create(Result);
  line.Title := 'Line';
  line.LinePen.Width := 2;
  line.LinePen.Color := clNavy;
  line.ShowPoints := true;
  for i := 0 to 30 do
    line.AddXY(i / 4, 2 + 2 * Sin(i / 4));
  Result.AddSeries(line);

  pie := TPieSeries.Create(Result);
  pie.Title := 'Pie';
  pie.Active := false;
  pie.AddXY(0, 1, 'a');
  pie.AddXY(0, 2, 'b');
  Result.AddSeries(pie);
end;

procedure CheckSVG(AChart: TChart);
var
  s: TBytes;
  txt: String;
begin
  SaveChartToSVGFile(AChart, 'drawercheck.svg');
  s := TFile.ReadAllBytes('drawercheck.svg');
  txt := TEncoding.UTF8.GetString(s);
  Check('SVG: file written', Length(s) > 500, Format('(%d bytes)', [Length(s)]));
  Check('SVG: <svg root', Pos('<svg ', txt) > 0);
  Check('SVG: closing tag', Pos('</svg>', txt) > 0);
  Check('SVG: text escaped', Pos('&lt;&amp;&gt;', txt) > 0);
  Check('SVG: nothing raw-escaped', Pos('<&>', txt) = 0);
end;

procedure CheckWMF(AChart: TChart);
var
  s: TBytes;
  sig: Cardinal;
begin
  AChart.SaveToWMF('drawercheck.emf');
  s := TFile.ReadAllBytes('drawercheck.emf');
  Check('EMF: file written', Length(s) > 500, Format('(%d bytes)', [Length(s)]));
  if Length(s) >= 44 then begin
    Move(s[40], sig, 4);
    Check('EMF: signature', sig = $464D4520);  // ' EMF'
  end
  else
    Check('EMF: signature', false, '(file too short)');
end;

procedure CheckOpenGL(AChart: TChart);
var
  bmp: TBitmap;
  pfd: TPixelFormatDescriptor;
  pf: Integer;
  rc: HGLRC;
  pixels: array of Cardinal;
  x, y: Integer;
  line: PCardinal;
  png: TPngImage;
  colored: Integer;
  c: Cardinal;
begin
  // A 24/32bpp DIB section plus the GDI generic OpenGL implementation gives a
  // context that works without any window - ideal for testing.
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(W, H);

    FillChar(pfd, SizeOf(pfd), 0);
    pfd.nSize := SizeOf(pfd);
    pfd.nVersion := 1;
    pfd.dwFlags := PFD_DRAW_TO_BITMAP or PFD_SUPPORT_OPENGL or PFD_SUPPORT_GDI;
    pfd.iPixelType := PFD_TYPE_RGBA;
    pfd.cColorBits := 32;
    pfd.cDepthBits := 24;
    pfd.iLayerType := PFD_MAIN_PLANE;

    pf := ChoosePixelFormat(bmp.Canvas.Handle, @pfd);
    Check('GL: pixel format', pf <> 0);
    if pf = 0 then exit;
    Check('GL: SetPixelFormat', SetPixelFormat(bmp.Canvas.Handle, pf, @pfd));

    rc := wglCreateContext(bmp.Canvas.Handle);
    Check('GL: context created', rc <> 0);
    if rc = 0 then exit;
    try
      Check('GL: made current', wglMakeCurrent(bmp.Canvas.Handle, rc));

      glViewport(0, 0, W, H);
      glMatrixMode(GL_PROJECTION);
      glLoadIdentity;
      glOrtho(0, W, H, 0, -1, 1);
      glMatrixMode(GL_MODELVIEW);
      glLoadIdentity;
      glClearColor(1, 1, 1, 1);
      glClear(GL_COLOR_BUFFER_BIT);

      AChart.Draw(TOpenGLDrawer.Create, Rect(0, 0, W, H));
      glFinish;

      // Read back and count pixels that are neither white nor black.
      SetLength(pixels, W * H);
      glReadPixels(0, 0, W, H, GL_BGRA, GL_UNSIGNED_BYTE, @pixels[0]);
      colored := 0;
      for x := 0 to W * H - 1 do begin
        c := pixels[x] and $FFFFFF;
        if (c <> $FFFFFF) and (c <> $000000) then
          Inc(colored);
      end;
      Check('GL: colored pixels rendered', colored > 1000,
        Format('(%d colored)', [colored]));

      // glReadPixels returns bottom-up; flip into the bitmap and save.
      for y := 0 to H - 1 do begin
        line := bmp.ScanLine[y];
        for x := 0 to W - 1 do begin
          line^ := pixels[(H - 1 - y) * W + x] or $FF000000;
          Inc(line);
        end;
      end;
      png := TPngImage.Create;
      try
        png.Assign(bmp);
        png.SaveToFile('drawercheck-gl.png');
      finally
        png.Free;
      end;
      Check('GL: png written', FileExists('drawercheck-gl.png'));
    finally
      ChartGLFreeTextures;
      wglMakeCurrent(0, 0);
      wglDeleteContext(rc);
    end;
  finally
    bmp.Free;
  end;
end;

var
  form: TForm;
  chart: TChart;
begin
  try
    form := TForm.CreateNew(nil);
    try
      chart := MakeChart(form);
      chart.Parent := form;
      CheckSVG(chart);
      CheckWMF(chart);
      CheckOpenGL(chart);
    finally
      form.Free;
    end;
    if Failures = 0 then
      WriteLn('All drawer checks passed.')
    else
      WriteLn(Format('%d check(s) FAILED.', [Failures]));
  except
    on E: Exception do begin
      WriteLn('EXCEPTION: ', E.ClassName, ': ', E.Message);
      Inc(Failures);
    end;
  end;
  Flush(Output);
  Halt(IfThen(Failures = 0, 0, 1));
end.
