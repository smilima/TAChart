//---------------------------------------------------------------------------
//  TAChart OpenGL demo - see MainUnit.h.
//---------------------------------------------------------------------------

#include <vcl.h>
#include <cmath>
#include <algorithm>
#include <memory>
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
#pragma link "TAChartGL"
#pragma link "TAFastSeries"
#pragma link "TAGLContext"
#pragma resource "*.dfm"
TMainForm *MainForm;

//---------------------------------------------------------------------------
//  The sample shape.  Y is always computed from the index and the phase, never
//  accumulated, so animating for a long time cannot make the data drift.
//---------------------------------------------------------------------------
static inline float SampleY(int AIndex, double APhase)
{
	return (float)(std::sin(AIndex * 0.00007) * 100.0 +
				   std::sin(AIndex * 0.0032 + APhase) * 12.0);
}

static double NowMs()
{
	LARGE_INTEGER t, f;
	QueryPerformanceCounter(&t);
	QueryPerformanceFrequency(&f);
	return 1000.0 * (double)t.QuadPart / (double)f.QuadPart;
}

//---------------------------------------------------------------------------
__fastcall TMainForm::TMainForm(TComponent* Owner)
	: TForm(Owner), FAnimPos(0), FPhase(0), FFrameMs(0), FLoadMs(0)
{
}

//---------------------------------------------------------------------------
int __fastcall TMainForm::SelectedCount()
{
	switch (cbCount->ItemIndex) {
		case 0:  return 100000;
		case 1:  return 1000000;
		case 2:  return 5000000;
		default: return 10000000;
	}
}

//---------------------------------------------------------------------------
//  Bulk load.  SetSampleCount allocates once, the fill writes straight into
//  the packed buffer through SamplePtr, and DataChanged publishes the result.
//  Going through AddXY instead would reallocate as it grew and cost far more.
//---------------------------------------------------------------------------
void __fastcall TMainForm::LoadSamples(int ACount)
{
	// No try/__finally here: that is SEH, and a function cannot mix it with
	// C++ try/catch.  The cursor is restored on each path instead.
	Screen->Cursor = crHourGlass;
	double t0 = NowMs();

	try {
		Series->SetSampleCount(ACount);
	}
	catch (const EOutOfMemory &) {
		// 10 M samples is 76 MB; a 32 bit process may legitimately refuse.
		Screen->Cursor = crDefault;
		ShowMessage("Not enough memory for " + IntToStr(ACount) +
			" samples in a 32 bit process.  Try a smaller count, or build the "
			"demo for Win64.");
		return;
	}
	catch (...) {
		Screen->Cursor = crDefault;
		throw;
	}

	TChartFastPoint *p = Series->SamplePtr();
	for (int i = 0; i < ACount; ++i) {
		p[i].X = (float)(i / 1000.0);
		p[i].Y = SampleY(i, 0.0);
	}
	Series->DataChanged();

	FAnimPos = 0;
	FPhase = 0;
	FLoadMs = NowMs() - t0;
	Screen->Cursor = crDefault;

	Redraw();
}

//---------------------------------------------------------------------------
void __fastcall TMainForm::Redraw()
{
	double t0 = NowMs();
	TAChartGL1->Repaint();
	FFrameMs = NowMs() - t0;
	UpdateStats();
}

//---------------------------------------------------------------------------
double __fastcall TMainForm::MeasureRepaints(int ACount)
{
	// Note this is wall-clock per frame including SwapBuffers, so once the
	// chart is drawing faster than the display refreshes it measures vsync
	// rather than rendering, and stops separating cheap work from cheaper.
	// It is the honest number for "frames the window can present", which is
	// what an interactive chart is limited by.
	for (int i = 0; i < 3; ++i) {          // warm-up, not measured
		TAChartGL1->Repaint();
		Application->ProcessMessages();
	}
	double t0 = NowMs();
	for (int i = 0; i < ACount; ++i) {
		TAChartGL1->Repaint();
		Application->ProcessMessages();
	}
	FFrameMs = (NowMs() - t0) / ACount;
	UpdateStats();
	return FFrameMs;
}

//---------------------------------------------------------------------------
void __fastcall TMainForm::UpdateStats()
{
	Tagpu::TChartAdapterInfo best;
	UnicodeString gpuLine;
	if (Tagpu::BestAdapter(best)) {
		bool onIt = TAChartGL1->OpenGLActive() && TAChartGL1->GLContext != NULL &&
			Tagpu::RendererMatchesAdapter(TAChartGL1->GLContext->Renderer, best);
		gpuLine = "best adapter: " + best.Description +
			(onIt ? UnicodeString("  (in use)")
				  : UnicodeString("  (NOT in use - relaunch to switch)"));
	}

	UnicodeString renderer;
	if (TAChartGL1->OpenGLActive() && TAChartGL1->GLContext != NULL)
		renderer = "OpenGL " + TAChartGL1->GLContext->Version +
				   "  -  " + TAChartGL1->GLContext->Renderer;
	else
		renderer = "GDI fallback (no OpenGL context)";

	UnicodeString vbo;
	if (!TAChartGL1->OpenGLActive())
		vbo = "n/a";
	else if (Series->UsingVBO())
		vbo = "yes";
	else if (Series->Decimate)
		vbo = "not needed (decimated)";
	else
		vbo = "no (client arrays)";

	int drawn = Series->LastDrawnVertexCount;
	UnicodeString reduction = "-";
	if (drawn > 0 && Series->SampleCount > 0)
		reduction = FormatFloat("0",
			(double)Series->SampleCount / (double)drawn) + "x fewer";

	// Built by concatenation rather than Format/ARRAYOFCONST: a plain double
	// has an ambiguous conversion to TVarRec, and casting every argument to
	// Extended just to satisfy the macro reads worse than this.
	lblStats->Caption =
		renderer + "\r\n" +
		"samples "           + FormatFloat("#,##0", (double)Series->SampleCount) +
		"      vertices drawn " + FormatFloat("#,##0", (double)drawn) +
		" ("                 + reduction + ")" +
		"      vertex buffer: " + vbo + "\r\n" +
		"frame "             + FormatFloat("0.00", FFrameMs) + " ms (incl. swap)" +
		"      last load "   + FormatFloat("0", FLoadMs) + " ms" +
		"      X ascending: " + UnicodeString(Series->XAscending ? "yes" : "no");
}

//---------------------------------------------------------------------------
void __fastcall TMainForm::FormShow(TObject *Sender)
{
	TAChartGL1->Title->Text->Text = "TAChart on the GPU";
	Series->Title = "fast line";
	Series->LinePen->Color = clNavy;

	cbCount->ItemIndex = 1;			// a million to start with
	chkDecimate->Checked = Series->Decimate;
	chkOpenGL->Checked = TAChartGL1->UseOpenGL;
	chkAnimate->Checked = false;
	Timer->Enabled = false;

	// In self-test mode the caller chooses the sample count, so skip the
	// interactive default rather than loading twice.
	if (!((ParamCount() >= 1) && SameText(ParamStr(1), "--selftest")))
		LoadSamples(SelectedCount());
}

//---------------------------------------------------------------------------
void __fastcall TMainForm::btnLoadClick(TObject *Sender)
{
	LoadSamples(SelectedCount());
}

//---------------------------------------------------------------------------
void __fastcall TMainForm::chkDecimateClick(TObject *Sender)
{
	Series->Decimate = chkDecimate->Checked;
	Redraw();
}

//---------------------------------------------------------------------------
void __fastcall TMainForm::chkAnimateClick(TObject *Sender)
{
	Timer->Enabled = chkAnimate->Checked;
}

//---------------------------------------------------------------------------
//  Turning OpenGL off recreates the window handle, which drops the context.
//  The series notices that its vertex buffer belonged to the old context and
//  abandons it, so this is safe to toggle repeatedly.
//---------------------------------------------------------------------------
void __fastcall TMainForm::chkOpenGLClick(TObject *Sender)
{
	TAChartGL1->UseOpenGL = chkOpenGL->Checked;
	Redraw();
}

//---------------------------------------------------------------------------
//  One animation step.  Only Y changes and X is left alone, so ValuesChanged
//  can patch just the pixel columns those samples fall in rather than rebuild
//  the whole reduction - which is what keeps this cheap on a huge series.
//---------------------------------------------------------------------------
void __fastcall TMainForm::TimerTimer(TObject *Sender)
{
	int n = Series->SampleCount;
	if (n < 2) return;

	int span = std::max(1, n / 200);
	if (FAnimPos + span > n) {
		FAnimPos = 0;
		FPhase += 0.35;
	}

	TChartFastPoint *p = Series->SamplePtr();
	for (int i = 0; i < span; ++i) {
		int k = FAnimPos + i;
		p[k].Y = SampleY(k, FPhase);
	}
	Series->ValuesChanged(FAnimPos, span);
	FAnimPos += span;

	Redraw();
}
//---------------------------------------------------------------------------

//---------------------------------------------------------------------------
void __fastcall TMainForm::SelfTest(int ACount, const UnicodeString AFile)
{
	std::unique_ptr<TStringList> log(new TStringList());
	LoadSamples(ACount);

	chkDecimate->Checked = false;
	Series->Decimate = false;
	MeasureRepaints(20);
	int fullVerts = Series->LastDrawnVertexCount;
	double fullMs = FFrameMs;
	bool vbo = Series->UsingVBO();

	chkDecimate->Checked = true;
	Series->Decimate = true;
	MeasureRepaints(20);
	int decVerts = Series->LastDrawnVertexCount;
	double decMs = FFrameMs;

	// One animation step, the case ValuesChanged exists for.
	TimerTimer(NULL);
	double animMs = FFrameMs;

	log->Add("openGLActive   = " + UnicodeString(
		TAChartGL1->OpenGLActive() ? "yes" : "no"));
	if (TAChartGL1->OpenGLActive() && TAChartGL1->GLContext != NULL) {
		log->Add("renderer       = " + TAChartGL1->GLContext->Renderer);
		log->Add("glVersion      = " + TAChartGL1->GLContext->Version);
		log->Add("hasVBO         = " + UnicodeString(
			TAChartGL1->GLContext->HasVBO ? "yes" : "no"));
	}
	log->Add("samples        = " + IntToStr(Series->SampleCount));
	log->Add("xAscending     = " + UnicodeString(
		Series->XAscending ? "yes" : "no"));
	log->Add("fullVertices   = " + IntToStr(fullVerts));
	log->Add("fullUsingVBO   = " + UnicodeString(vbo ? "yes" : "no"));
	log->Add("fullFrameMs    = " + FormatFloat("0.00", fullMs) +
		"   (wall clock incl. SwapBuffers; vsync-bound once under ~8 ms)");
	log->Add("decVertices    = " + IntToStr(decVerts));
	log->Add("decFrameMs     = " + FormatFloat("0.00", decMs));
	log->Add("animFrameMs    = " + FormatFloat("0.00", animMs));
	log->Add("loadMs         = " + FormatFloat("0", FLoadMs));
	log->SaveToFile(AFile);
}
//---------------------------------------------------------------------------
