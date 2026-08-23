//---------------------------------------------------------------------------

#ifndef MainUnitH
#define MainUnitH
//---------------------------------------------------------------------------
#include <System.Classes.hpp>
#include <Vcl.Controls.hpp>
#include <Vcl.StdCtrls.hpp>
#include <Vcl.Forms.hpp>
#include "TAGraph.hpp"
#include "TASeries.hpp"
#include "TATypes.hpp"
#include "TAChartUtils.hpp"
#include "TACustomSeries.hpp"
#include "TARadialSeries.hpp"
//---------------------------------------------------------------------------
class TForm3 : public TForm
{
__published:	// IDE-managed Components
	void __fastcall FormShow(TObject *Sender);
private:	// User declarations
public:		// User declarations
	__fastcall TForm3(TComponent* Owner);
};
//---------------------------------------------------------------------------
extern PACKAGE TForm3 *Form3;
//---------------------------------------------------------------------------
#endif
