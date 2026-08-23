//---------------------------------------------------------------------------

#include <vcl.h>
#include <cmath>
#pragma hdrstop

#include "MainUnit.h"
//---------------------------------------------------------------------------
#pragma package(smart_init)
#pragma link "TAGraph"
#pragma link "TASeries"
#pragma link "TATools"
#pragma link "TATypes"
#pragma link "TAChartUtils"
#pragma link "TACustomSeries"
#pragma link "TARadialSeries"
#pragma resource "*.dfm"
TForm3 *Form3;
//---------------------------------------------------------------------------
__fastcall TForm3::TForm3(TComponent* Owner)
	: TForm(Owner)
{
}
//---------------------------------------------------------------------------
void __fastcall TForm3::FormShow(TObject *Sender)
{
//	const double kPi = std::acos(-1.0);
//	AChart1TAPolarSeries1->Title = "Polar";
//	AChart1TAPolarSeries1->CloseCircle = true;
//	AChart1TAPolarSeries1->LinePen->Width = 2;
//	AChart1TAPolarSeries1->Clear();
//	for (int i = 0; i <= 72; ++i) {
//		const double angle = i * 2.0 * kPi / 72.0;
//		AChart1TAPolarSeries1->AddXY(angle, 2.0);
//	}
}
//---------------------------------------------------------------------------

