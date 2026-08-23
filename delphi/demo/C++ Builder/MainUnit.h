//---------------------------------------------------------------------------
//  TAChart OpenGL demo - exercises TTAChartGL and TFastLineSeries from C++.
//
//  Load a few million samples, watch the vertex count collapse when
//  decimation is on, animate part of the data through ValuesChanged, and
//  switch OpenGL off to see the same chart fall back to GDI.
//---------------------------------------------------------------------------

#ifndef MainUnitH
#define MainUnitH
//---------------------------------------------------------------------------
#include <System.Classes.hpp>
#include <Vcl.Controls.hpp>
#include <Vcl.StdCtrls.hpp>
#include <Vcl.Forms.hpp>
#include <Vcl.ExtCtrls.hpp>
#include "TAGraph.hpp"
#include "TASeries.hpp"
#include "TATypes.hpp"
#include "TAChartUtils.hpp"
#include "TACustomSeries.hpp"
#include "TARadialSeries.hpp"
#include "TAChartGL.hpp"
#include "TAFastSeries.hpp"
#include "TAGLContext.hpp"
#include "TAGPU.hpp"
//---------------------------------------------------------------------------
class TMainForm : public TForm
{
__published:	// IDE-managed Components
	TTimer *Timer;
	TTAChartGL *TAChartGL1;
	TFastLineSeries *Series;
	TPanel *ControlPanel;
	TLabel *lblCount;
	TComboBox *cbCount;
	TButton *btnLoad;
	TCheckBox *chkDecimate;
	TCheckBox *chkAnimate;
	TCheckBox *chkOpenGL;
	TLabel *lblStats;
	void __fastcall FormShow(TObject *Sender);
	void __fastcall TimerTimer(TObject *Sender);
	void __fastcall btnLoadClick(TObject *Sender);
	void __fastcall chkDecimateClick(TObject *Sender);
	void __fastcall chkAnimateClick(TObject *Sender);
	void __fastcall chkOpenGLClick(TObject *Sender);
private:	// User declarations
	int FAnimPos;			// next sample span the animation will move
	double FPhase;			// animation phase, so Y is recomputed not drifted
	double FFrameMs;		// last measured frame time, incl. swap
	double FRenderMs;		// last measured render cost, vsync off
	double FLoadMs;			// time the last load took

	void __fastcall LoadSamples(int ACount);
	void __fastcall Redraw();
	// Averaged repaint time.  A single frame is not a measurement: the first
	// frame after a context comes up pays driver warm-up, which on a discrete
	// adapter is large enough to make it look slower than the integrated one.
	double __fastcall MeasureRepaints(int ACount);
	// What drawing actually costs: vsync off so SwapBuffers stops blocking,
	// and a Finish each frame so the GPU has really done the work rather
	// than merely accepted it.  Returns -1 when the driver has no swap
	// control, since without it the figure would still be vsync.
	double __fastcall MeasureRenderCost(int ACount);
	void __fastcall UpdateStats();
	int __fastcall SelectedCount();
public:		// User declarations
	__fastcall TMainForm(TComponent* Owner);
	// Headless check: load ACount samples, draw once with decimation off and
	// once with it on, and write what happened to AFile.  Same idea as
	// ChartDemo's --render switch, so the demo can be verified without a
	// person watching it.
	void __fastcall SelfTest(int ACount, const UnicodeString AFile);
};
//---------------------------------------------------------------------------
extern PACKAGE TMainForm *MainForm;
//---------------------------------------------------------------------------
#endif
