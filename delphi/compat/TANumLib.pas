{
 *****************************************************************************
  This file is part of the Delphi/VCL port of TAChart.

  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  Replacement for the handful of Free Pascal NumLib routines that TAChart uses.

  Upstream, TAFuncSeries pulls in the units "typ" and "ipf" and TAMath pulls in
  "spe".  NumLib is a large FPC-only package, so instead of porting it wholesale
  this unit reimplements exactly the five routines the chart needs, keeping the
  original signatures and index conventions so that the ported units compile
  unchanged:

    ipfisn  natural cubic spline: second derivatives at the interior knots
    ipfspn  natural cubic spline: evaluation (with linear extrapolation)
    ipfsmm  natural cubic spline: minimum and maximum over the knot range
    ipfpol  least squares polynomial fit via orthogonal polynomials
    speerf  the error function erf(x)

  Index conventions inherited from NumLib
  ---------------------------------------
  * ipf* take the LAST index n of the data, i.e. the arrays x and y hold n+1
    points x[0..n], y[0..n].
  * The second derivative array d2s only stores the n-1 interior values; d2s[k]
    holds sigma(k+1).  sigma(0) and sigma(n) are zero (the "natural" end
    condition).
  * term is the NumLib status code: 1 = success, 2 = numerical failure,
    3 = invalid input.
}

unit TANumLib;

{$I TAChartDefines.inc}
{$RANGECHECKS OFF}
{$POINTERMATH ON}

interface

type
  ArbInt = Integer;
  ArbFloat = Double;

procedure ipfisn(n: ArbInt; var x, y, d2s: ArbFloat; var term: ArbInt);
function ipfspn(n: ArbInt; var x, y, d2s: ArbFloat; t: ArbFloat;
  var term: ArbInt): ArbFloat;
procedure ipfsmm(n: ArbInt; var x, y, d2s, minv, maxv: ArbFloat;
  var term: ArbInt);
procedure ipfpol(m, n: ArbInt; var x, y, b: ArbFloat; var term: ArbInt);

function speerf(x: ArbFloat): ArbFloat;

implementation

uses
  System.Math;

type
  PArbFloat = ^ArbFloat;

{ ---------------------------------------------------------------------------
  Natural cubic spline
  --------------------------------------------------------------------------- }

{ Solves the symmetric positive definite tridiagonal system

    h[k-1]/6 * s[k-1] + (h[k-1]+h[k])/3 * s[k] + h[k]/6 * s[k+1] = rhs[k]

  for k = 1..n-1 with s[0] = s[n] = 0, which is the classic natural cubic
  spline system.  NumLib solves the same system with a banded Cholesky
  factorisation (slegpb); the matrix is diagonally dominant, so the Thomas
  algorithm used here is equally stable and considerably shorter. }
procedure ipfisn(n: ArbInt; var x, y, d2s: ArbFloat; var term: ArbInt);
var
  px, py, ps: PArbFloat;
  h, diag, upper, rhs: TArray<ArbFloat>;
  i, cnt: ArbInt;
  f: ArbFloat;
begin
  term := 1;
  if n < 2 then begin
    term := 3;
    exit;
  end;

  px := @x;
  py := @y;
  ps := @d2s;

  SetLength(h, n);
  for i := 0 to n - 1 do begin
    h[i] := px[i + 1] - px[i];
    if h[i] <= 0 then begin
      // x must be strictly increasing, otherwise the system is singular.
      term := 2;
      exit;
    end;
  end;

  cnt := n - 1;                         // number of interior knots
  SetLength(diag, cnt);
  SetLength(upper, cnt);
  SetLength(rhs, cnt);
  for i := 0 to cnt - 1 do begin        // i = k-1, so k = i+1
    diag[i] := (h[i] + h[i + 1]) / 3;
    upper[i] := h[i + 1] / 6;
    rhs[i] := (py[i + 2] - py[i + 1]) / h[i + 1] - (py[i + 1] - py[i]) / h[i];
  end;

  // Forward elimination.  The sub-diagonal element of row i equals upper[i-1]
  // because the matrix is symmetric.
  for i := 1 to cnt - 1 do begin
    if diag[i - 1] = 0 then begin
      term := 2;
      exit;
    end;
    f := upper[i - 1] / diag[i - 1];
    diag[i] := diag[i] - f * upper[i - 1];
    rhs[i] := rhs[i] - f * rhs[i - 1];
  end;
  if diag[cnt - 1] = 0 then begin
    term := 2;
    exit;
  end;

  // Back substitution.  ps[k-1] receives sigma(k).
  ps[cnt - 1] := rhs[cnt - 1] / diag[cnt - 1];
  for i := cnt - 2 downto 0 do
    ps[i] := (rhs[i] - upper[i] * ps[i + 1]) / diag[i];
end;

{ Faithful transcription of NumLib's ipfspn, including its linear extrapolation
  outside [x[0], x[n]] and the special casing of the first and last interval
  where one of the two second derivatives is the implicit zero end condition. }
function ipfspn(n: ArbInt; var x, y, d2s: ArbFloat; t: ArbFloat;
  var term: ArbInt): ArbFloat;
var
  px, py, ps: PArbFloat;
  i, j, m: ArbInt;
  d, s3, h, dy: ArbFloat;

  // ps1(k) is NumLib's pd2s^[k], i.e. sigma(k) for k = 1..n-1.
  function ps1(k: ArbInt): ArbFloat;
  begin
    Result := ps[k - 1];
  end;

begin
  Result := 0;
  term := 1;
  if n < 2 then begin
    term := 3;
    exit;
  end;

  px := @x;
  py := @y;
  ps := @d2s;

  if t <= px[0] then begin
    h := px[1] - px[0];
    dy := (py[1] - py[0]) / h - h * ps1(1) / 6;
    Result := py[0] + (t - px[0]) * dy;
  end
  else if t >= px[n] then begin
    h := px[n] - px[n - 1];
    dy := (py[n] - py[n - 1]) / h + h * ps1(n - 1) / 6;
    Result := py[n] + (t - px[n]) * dy;
  end
  else begin
    i := 0;
    j := n;
    while j <> i + 1 do begin
      m := (i + j) div 2;
      if t >= px[m] then i := m else j := m;
    end;
    h := px[i + 1] - px[i];
    d := t - px[i];
    if i = 0 then begin
      s3 := ps1(1) / h;
      dy := (py[1] - py[0]) / h - h * ps1(1) / 6;
      Result := py[0] + d * (dy + d * d * s3 / 6);
    end
    else if i = n - 1 then begin
      s3 := -ps1(n - 1) / h;
      dy := (py[n] - py[n - 1]) / h - h * ps1(n - 1) / 3;
      Result := py[n - 1] + d * (dy + d * (ps1(n - 1) / 2 + d * s3 / 6));
    end
    else begin
      s3 := (ps1(i + 1) - ps1(i)) / h;
      dy := (py[i + 1] - py[i]) / h - h * (2 * ps1(i) + ps1(i + 1)) / 6;
      Result := py[i] + d * (dy + d * (ps1(i) / 2 + d * s3 / 6));
    end;
  end;
end;

{ Minimum and maximum of the spline, found by locating the roots of the
  derivative on every segment.  As in NumLib, the knot values themselves are
  NOT considered - the caller seeds minv/maxv with them. }
procedure ipfsmm(n: ArbInt; var x, y, d2s, minv, maxv: ArbFloat;
  var term: ArbInt);
var
  px, py, ps: PArbFloat;
  i: ArbInt;
  h: ArbFloat;

  function ps1(k: ArbInt): ArbFloat;
  begin
    Result := ps[k - 1];
  end;

  procedure UpdateMinMax(v: ArbFloat);
  begin
    if (0 >= v) or (v >= h) then exit;
    v := ipfspn(n, x, y, d2s, px[i] + v, term);
    if v < minv then minv := v;
    if v > maxv then maxv := v;
  end;

  procedure MinMaxOnSegment;
  var
    a, b, c, d: ArbFloat;
  begin
    h := px[i + 1] - px[i];
    if i = 0 then begin
      a := ps1(1) / h / 2;
      b := 0;
      c := (py[1] - py[0]) / h - h * ps1(1) / 6;
    end
    else if i = n - 1 then begin
      a := -ps1(n - 1) / h / 2;
      b := ps1(n - 1);
      c := (py[n] - py[n - 1]) / h - h * ps1(n - 1) / 3;
    end
    else begin
      a := (ps1(i + 1) - ps1(i)) / h / 2;
      b := ps1(i);
      c := (py[i + 1] - py[i]) / h - h * (2 * ps1(i) + ps1(i + 1)) / 6;
    end;
    if a = 0 then exit;
    d := b * b - 4 * a * c;
    if d < 0 then exit;
    d := Sqrt(d);
    UpdateMinMax((-b + d) / (2 * a));
    UpdateMinMax((-b - d) / (2 * a));
  end;

begin
  term := 1;
  if n < 2 then begin
    term := 3;
    exit;
  end;
  px := @x;
  py := @y;
  ps := @d2s;
  for i := 0 to n - 1 do
    MinMaxOnSegment;
end;

{ ---------------------------------------------------------------------------
  Least squares polynomial fit
  --------------------------------------------------------------------------- }

{ Three-term recurrence coefficients of the polynomials orthogonal on the
  discrete point set x[1..m].  alfa and beta are 1-based, as in NumLib. }
procedure ortpol(m, n: ArbInt; const px: PArbFloat; var alfa, beta: TArray<ArbFloat>);
var
  i, j: ArbInt;
  xppn1, ppn1, ppn, p, alfaj, betaj: ArbFloat;
  pn, pn1: TArray<ArbFloat>;
begin
  SetLength(pn, m + 1);
  SetLength(pn1, m + 1);
  xppn1 := 0;
  ppn1 := m;
  for i := 1 to m do begin
    pn[i] := 0;
    pn1[i] := 1;
    xppn1 := xppn1 + px[i - 1];
  end;
  alfa[1] := xppn1 / ppn1;
  beta[1] := 0;
  for j := 2 to n do begin
    alfaj := alfa[j - 1];
    betaj := beta[j - 1];
    ppn := ppn1;
    ppn1 := 0;
    xppn1 := 0;
    for i := 1 to m do begin
      p := (px[i - 1] - alfaj) * pn1[i] - betaj * pn[i];
      pn[i] := pn1[i];
      pn1[i] := p;
      p := p * p;
      ppn1 := ppn1 + p;
      xppn1 := xppn1 + px[i - 1] * p;
    end;
    alfa[j] := xppn1 / ppn1;
    beta[j] := ppn1 / ppn;
  end;
end;

{ Coefficients of the fit expressed in the orthogonal basis.  a is 0-based. }
procedure ortcoe(m, n: ArbInt; const px, py: PArbFloat;
  const alfa, beta: TArray<ArbFloat>; var a: TArray<ArbFloat>);
var
  i, j: ArbInt;
  fpn, ppn, p, alphaj, betaj: ArbFloat;
  pn, pn1: TArray<ArbFloat>;
begin
  SetLength(pn, m + 1);
  SetLength(pn1, m + 1);
  fpn := 0;
  for i := 1 to m do begin
    pn[i] := 0;
    pn1[i] := 1;
    fpn := fpn + py[i - 1];
  end;
  a[0] := fpn / m;
  for j := 1 to n do begin
    fpn := 0;
    ppn := 0;
    alphaj := alfa[j];
    betaj := beta[j];
    for i := 1 to m do begin
      p := (px[i - 1] - alphaj) * pn1[i] - betaj * pn[i];
      pn[i] := pn1[i];
      pn1[i] := p;
      fpn := fpn + py[i - 1] * p;
      ppn := ppn + p * p;
    end;
    a[j] := fpn / ppn;
  end;
end;

{ Converts from the orthogonal basis to the monomial basis, writing n+1
  coefficients in ascending powers to pb[0..n]. }
procedure polcoe(n: ArbInt; const alfa, beta, a: TArray<ArbFloat>;
  const pb: PArbFloat);
var
  k, j: ArbInt;
begin
  for k := 0 to n do
    pb[k] := a[k];
  for j := 0 to n - 1 do
    for k := n - j - 1 downto 0 do begin
      pb[k + j] := pb[k + j] - alfa[k + 1] * pb[k + j + 1];
      if k + j <> n - 1 then
        pb[k + j] := pb[k + j] - beta[k + 2] * pb[k + j + 2];
    end;
end;

{ Least squares fit of a polynomial of degree n through the m points
  (x[0..m-1], y[0..m-1]).  b receives n+1 coefficients in ascending powers,
  so b[0] is the constant term. }
procedure ipfpol(m, n: ArbInt; var x, y, b: ArbFloat; var term: ArbInt);
var
  i: ArbInt;
  fsum: ArbFloat;
  px, py, pb: PArbFloat;
  alfa, beta, a: TArray<ArbFloat>;
begin
  if (n < 0) or (m < 1) then begin
    term := 3;
    exit;
  end;
  term := 1;
  px := @x;
  py := @y;
  pb := @b;

  if n = 0 then begin
    fsum := 0;
    for i := 0 to m - 1 do
      fsum := fsum + py[i];
    pb[0] := fsum / m;
    exit;
  end;

  if n > m - 1 then begin
    // Not enough points for the requested degree: zero the excess
    // coefficients and fit the highest degree the data supports.
    for i := m to n do
      pb[i] := 0;
    n := m - 1;
  end;

  SetLength(alfa, n + 1);       // 1-based, entries 1..n
  SetLength(beta, n + 1);
  SetLength(a, n + 1);          // 0-based, entries 0..n
  ortpol(m, n, px, alfa, beta);
  ortcoe(m, n, px, py, alfa, beta, a);
  polcoe(n, alfa, beta, a, pb);
end;

{ ---------------------------------------------------------------------------
  Error function
  --------------------------------------------------------------------------- }

{ W. J. Cody's rational Chebyshev approximation (the algorithm behind NumLib's
  speerf and netlib's CALERF), accurate to close to double precision. }
function speerf(x: ArbFloat): ArbFloat;
const
  A: array[0..4] of Double = (
    3.16112374387056560E+00, 1.13864154151050156E+02, 3.77485237685302021E+02,
    3.20937758913846947E+03, 1.85777706184603153E-01);
  B: array[0..3] of Double = (
    2.36012909523441209E+01, 2.44024637934444173E+02, 1.28261652607737228E+03,
    2.84423683343917062E+03);
  C: array[0..8] of Double = (
    5.64188496988670089E-01, 8.88314979438837594E+00, 6.61191906371416295E+01,
    2.98635138197400131E+02, 8.81952221241769090E+02, 1.71204761263407058E+03,
    2.05107837782607147E+03, 1.23033935479799725E+03, 2.15311535474403846E-08);
  D: array[0..7] of Double = (
    1.57449261107098347E+01, 1.17693950891312499E+02, 5.37181101862009858E+02,
    1.62138957456669019E+03, 3.29079923573345963E+03, 4.36261909014324716E+03,
    3.43936767414372164E+03, 1.23033935480374942E+03);
  P: array[0..5] of Double = (
    3.05326634961232344E-01, 3.60344899949804439E-01, 1.25781726111229246E-01,
    1.60837851487422766E-02, 6.58749161529837803E-04, 1.63153871373020978E-02);
  Q: array[0..4] of Double = (
    2.56852019228982242E+00, 1.87295284992346047E+00, 5.27905102951428412E-01,
    6.05183413124413191E-02, 2.33520497626869185E-03);
  INV_SQRT_PI = 5.6418958354775628695E-01;
  X_SMALL = 1.11E-16;
  X_BIG = 26.543;
var
  y, z, ysq, del, xnum, xden, res: Double;
  i: Integer;
begin
  y := Abs(x);

  if y <= 0.46875 then begin
    // erf on the central interval.
    z := 0;
    if y > X_SMALL then z := y * y;
    xnum := A[4] * z;
    xden := z;
    for i := 0 to 2 do begin
      xnum := (xnum + A[i]) * z;
      xden := (xden + B[i]) * z;
    end;
    Result := x * (xnum + A[3]) / (xden + B[3]);
    exit;
  end;

  if y <= 4.0 then begin
    // erfc on the middle interval.
    xnum := C[8] * y;
    xden := y;
    for i := 0 to 6 do begin
      xnum := (xnum + C[i]) * y;
      xden := (xden + D[i]) * y;
    end;
    res := (xnum + C[7]) / (xden + D[7]);
  end
  else begin
    // erfc on the tail.
    if y >= X_BIG then begin
      if x > 0 then Result := 1.0 else Result := -1.0;
      exit;
    end;
    z := 1.0 / (y * y);
    xnum := P[5] * z;
    xden := z;
    for i := 0 to 3 do begin
      xnum := (xnum + P[i]) * z;
      xden := (xden + Q[i]) * z;
    end;
    res := z * (xnum + P[4]) / (xden + Q[4]);
    res := (INV_SQRT_PI - res) / y;
  end;

  // Split the exponent to preserve accuracy, as CALERF does.
  ysq := Int(y * 16.0) / 16.0;
  del := (y - ysq) * (y + ysq);
  res := Exp(-ysq * ysq) * Exp(-del) * res;

  Result := 1.0 - res;
  if x < 0 then
    Result := -Result;
end;

end.
