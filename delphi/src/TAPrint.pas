{
 *****************************************************************************
  See the file COPYING.modifiedLGPL.txt, included in this distribution,
  for details about the license.
 *****************************************************************************

  Authors: Alexander Klenin
}

unit TAPrint;

{$I TAChartDefines.inc}

interface

uses
  Vcl.Printers, TADrawerCanvas;

type

  { TPrinterDrawer }

  TPrinterDrawer = class(TScaledCanvasDrawer)
  private
    FPrinter: TPrinter;
  public
    constructor Create(APrinter: TPrinter; AScalePens: Boolean = false);
  end;

implementation

uses
  Winapi.Windows, System.Math, Vcl.Forms, TADrawUtils;

{ TPrinterDrawer }

constructor TPrinterDrawer.Create(APrinter: TPrinter;
  AScalePens: Boolean = false);
var
  f: Double;
  si: TScaleItems;
begin
  FPrinter := APrinter;
  // Lazarus reads TPrinter.XDPI/YDPI; the VCL exposes the same numbers
  // through the device caps of the printer DC.
  f := Max(
    GetDeviceCaps(FPrinter.Handle, LOGPIXELSX),
    GetDeviceCaps(FPrinter.Handle, LOGPIXELSY)) / Screen.PixelsPerInch;
  if AScalePens then si := [scalePen] else si := [];
  // Fonts are not in AScaleItems: TFont.Size is in points, which the printer
  // canvas already maps through its own PixelsPerInch.
  inherited Create(FPrinter.Canvas, f, si);
end;

end.
