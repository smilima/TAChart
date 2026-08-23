{
  Validation harness for TANumLib, the hand-written replacement for the Free
  Pascal NumLib routines that TAChart depends on.  Run it after changing
  anything in TANumLib.pas:

      NumLibCheck.exe

  Exit code is 0 when every check passes, 1 otherwise.
}

program NumLibCheck;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Math, System.StrUtils,
  TANumLib;

var
  Failures: Integer = 0;

procedure Check(const AName: String; AGot, AWant, ATol: Double);
var
  ok: Boolean;
begin
  ok := Abs(AGot - AWant) <= ATol;
  if not ok then Inc(Failures);
  WriteLn(Format('%-46s got %-22.15g want %-22.15g  %s',
    [AName, AGot, AWant, IfThen(ok, 'ok', '** FAILED **')]));
end;

procedure CheckErf;
begin
  WriteLn('-- speerf (error function) ------------------------------------');
  // Reference values from the standard erf.
  Check('erf(0)',    speerf(0.0),  0.0,                  1e-15);
  Check('erf(0.1)',  speerf(0.1),  0.112462916018285,    1e-14);
  Check('erf(0.5)',  speerf(0.5),  0.520499877813047,    1e-14);
  Check('erf(1)',    speerf(1.0),  0.842700792949715,    1e-14);
  Check('erf(2)',    speerf(2.0),  0.995322265018953,    1e-14);
  Check('erf(3)',    speerf(3.0),  0.999977909503001,    1e-14);
  Check('erf(5)',    speerf(5.0),  0.999999999998463,    1e-14);
  Check('erf(-1)',   speerf(-1.0), -0.842700792949715,   1e-14);
  Check('erf(-0.5)', speerf(-0.5), -0.520499877813047,   1e-14);
  WriteLn;
end;

procedure CheckSpline;
var
  x, y, d2s: array of ArbFloat;
  term, i: ArbInt;
  minv, maxv: ArbFloat;
begin
  WriteLn('-- ipfisn / ipfspn (natural cubic spline) ---------------------');

  // Three points (0,0) (1,1) (2,0).  With the natural end conditions the only
  // unknown second derivative is sigma(1) = -3, and s(0.5) = s(1.5) = 0.6875.
  SetLength(x, 3); SetLength(y, 3); SetLength(d2s, 3);
  x[0] := 0; x[1] := 1; x[2] := 2;
  y[0] := 0; y[1] := 1; y[2] := 0;
  term := 0;
  ipfisn(2, x[0], y[0], d2s[0], term);
  Check('term after ipfisn', term, 1, 0);
  Check('sigma(1)', d2s[0], -3.0, 1e-12);
  Check('s(0.5)', ipfspn(2, x[0], y[0], d2s[0], 0.5, term), 0.6875, 1e-12);
  Check('s(1.5)', ipfspn(2, x[0], y[0], d2s[0], 1.5, term), 0.6875, 1e-12);
  Check('s(1) at knot', ipfspn(2, x[0], y[0], d2s[0], 1.0, term), 1.0, 1e-12);
  Check('s(0) at knot', ipfspn(2, x[0], y[0], d2s[0], 0.0, term), 0.0, 1e-12);
  Check('s(2) at knot', ipfspn(2, x[0], y[0], d2s[0], 2.0, term), 0.0, 1e-12);

  // A straight line must be reproduced exactly: every second derivative is 0.
  SetLength(x, 6); SetLength(y, 6); SetLength(d2s, 6);
  for i := 0 to 5 do begin
    x[i] := i;
    y[i] := 2 * i + 1;
  end;
  ipfisn(5, x[0], y[0], d2s[0], term);
  Check('line: term', term, 1, 0);
  Check('line: s(2.5)', ipfspn(5, x[0], y[0], d2s[0], 2.5, term), 6.0, 1e-10);
  Check('line: s(0.25)', ipfspn(5, x[0], y[0], d2s[0], 0.25, term), 1.5, 1e-10);
  // Outside the knot range ipfspn extrapolates linearly along the end slope.
  Check('line: s(-1) extrapolated',
    ipfspn(5, x[0], y[0], d2s[0], -1.0, term), -1.0, 1e-10);
  Check('line: s(6) extrapolated',
    ipfspn(5, x[0], y[0], d2s[0], 6.0, term), 13.0, 1e-10);

  // A quadratic sampled densely: the spline must stay very close to it.
  SetLength(x, 11); SetLength(y, 11); SetLength(d2s, 11);
  for i := 0 to 10 do begin
    x[i] := i / 10;
    y[i] := Sqr(x[i]);
  end;
  ipfisn(10, x[0], y[0], d2s[0], term);
  Check('parabola: s(0.55)',
    ipfspn(10, x[0], y[0], d2s[0], 0.55, term), 0.3025, 1e-4);

  // Minimum and maximum of a spline with an interior extremum.
  SetLength(x, 5); SetLength(y, 5); SetLength(d2s, 5);
  x[0] := 0; x[1] := 1; x[2] := 2; x[3] := 3; x[4] := 4;
  y[0] := 0; y[1] := 1; y[2] := 0; y[3] := 1; y[4] := 0;
  ipfisn(4, x[0], y[0], d2s[0], term);
  minv := 0;
  maxv := 1;
  ipfsmm(4, x[0], y[0], d2s[0], minv, maxv, term);
  Check('ipfsmm: term', term, 1, 0);
  WriteLn(Format('%-46s min %.6f  max %.6f', ['ipfsmm range', minv, maxv]));
  if (minv > 0) or (maxv < 1) then begin
    WriteLn('   ** FAILED ** extrema must not shrink the seeded range');
    Inc(Failures);
  end;

  // Degenerate input has to be reported, not crash.
  term := 0;
  ipfisn(1, x[0], y[0], d2s[0], term);
  Check('ipfisn with n < 2 reports term=3', term, 3, 0);
  WriteLn;
end;

procedure CheckPolyFit;
var
  x, y, b: array of ArbFloat;
  term, i: ArbInt;
begin
  WriteLn('-- ipfpol (least squares polynomial fit) ----------------------');

  // Points taken exactly from y = 1 + 2x + 3x^2, so a degree 2 fit must
  // recover the coefficients.
  SetLength(x, 7); SetLength(y, 7); SetLength(b, 3);
  for i := 0 to 6 do begin
    x[i] := i - 3;
    y[i] := 1 + 2 * x[i] + 3 * Sqr(x[i]);
  end;
  term := 0;
  ipfpol(7, 2, x[0], y[0], b[0], term);
  Check('term after ipfpol', term, 1, 0);
  Check('b[0] (constant)', b[0], 1.0, 1e-9);
  Check('b[1] (linear)', b[1], 2.0, 1e-9);
  Check('b[2] (quadratic)', b[2], 3.0, 1e-9);

  // Degree 0 is the mean.
  SetLength(b, 1);
  ipfpol(7, 0, x[0], y[0], b[0], term);
  Check('degree 0 = mean', b[0], 1 + 3 * (9 + 4 + 1 + 0 + 1 + 4 + 9) / 7, 1e-9);

  // A straight line through noisy-free points, fitted with degree 1.
  SetLength(x, 5); SetLength(y, 5); SetLength(b, 2);
  for i := 0 to 4 do begin
    x[i] := i;
    y[i] := 4 - 0.5 * i;
  end;
  ipfpol(5, 1, x[0], y[0], b[0], term);
  Check('line fit b[0]', b[0], 4.0, 1e-9);
  Check('line fit b[1]', b[1], -0.5, 1e-9);

  // Asking for a higher degree than the data supports must not crash.
  SetLength(b, 8);
  for i := 0 to 7 do b[i] := 999;
  term := 0;
  ipfpol(3, 7, x[0], y[0], b[0], term);
  Check('over-specified degree: term', term, 1, 0);
  Check('over-specified degree: excess coeff zeroed', b[7], 0.0, 0);
  WriteLn;
end;

begin
  try
    CheckErf;
    CheckSpline;
    CheckPolyFit;
    if Failures = 0 then
      WriteLn('All TANumLib checks passed.')
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
