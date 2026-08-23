{
 *****************************************************************************
  Shared compiler directives for the Delphi/VCL port of TAChart.

  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************
}

{$IFNDEF TACHART_DEFINES_INCLUDED}
{$DEFINE TACHART_DEFINES_INCLUDED}

{$H+}               // long strings
{$B-}               // short-circuit boolean evaluation
{$T-}               // untyped pointers
{$X+}               // extended syntax
{$P+}               // open string parameters
{$J-}               // typed constants are read only
{$MINENUMSIZE 1}
// Several series write straight into a raw 32 bit image through a typed
// pointer, which Delphi only allows with pointer arithmetic enabled.
{$POINTERMATH ON}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}
{$WARN GARBAGE OFF}

// TAChart relies on comparing and inspecting floating point values that can be
// NaN or Infinity (see TAMath / TAChartUtils).  Turning off floating point
// exceptions is done at run time by the chart itself; the directives below just
// keep the ported arithmetic identical to the FPC original.
{$IFOPT Q+}{$DEFINE TACHART_OVERFLOWCHECKS}{$ENDIF}
{$Q-}               // no overflow checking (matches FPC release build)

{$ENDIF}
