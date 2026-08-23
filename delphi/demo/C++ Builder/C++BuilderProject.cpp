//---------------------------------------------------------------------------
//  TAChart OpenGL demo.
//
//  Run with no arguments for the interactive window.  Run
//
//      C++BuilderProject.exe --selftest <samples> <outfile>
//
//  to load that many samples, draw once with decimation off and once with it
//  on, take one animation step, write the numbers to <outfile> and exit - so
//  the demo can be checked without a person watching it.  <samples> and
//  <outfile> are optional and default to 1000000 and selftest.txt.
//---------------------------------------------------------------------------

#include <vcl.h>
#pragma hdrstop
#include <tchar.h>
#include <shellapi.h>
// USEFORM alone leaves TMainForm incomplete; the self-test calls its
// members, so the header is needed here too.
#include "MainUnit.h"
#include "TAGPU.hpp"
//---------------------------------------------------------------------------
//  Ask for the discrete GPU on a switchable-graphics laptop.
//
//  The NVIDIA and AMD drivers look for these exported symbols in the
//  *executable* when the process starts, before any OpenGL call, and hand it
//  the high-performance adapter.  It has to be the exe: a symbol exported
//  from a package or DLL is not what the driver inspects, so TAChart cannot
//  do this on an application's behalf.
//---------------------------------------------------------------------------
extern "C" {
	__declspec(dllexport) DWORD NvOptimusEnablement = 0x00000001;
	__declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
}
//---------------------------------------------------------------------------
USEFORM("MainUnit.cpp", MainForm);
//---------------------------------------------------------------------------
int WINAPI _tWinMain(HINSTANCE, HINSTANCE, LPTSTR, int)
{
	try
	{
		Application->Initialize();
		Application->MainFormOnTaskBar = true;

		// Pick the most capable adapter before anything creates a GL context.
		// Windows resolves which GPU a process gets at process start, so a
		// preference set now cannot affect this run - the only way to act on it
		// is to start again.  --relaunched makes that happen at most once.
		bool relaunched = false;
		for (int i = 1; i <= ParamCount(); ++i)
			if (SameText(ParamStr(i), "--relaunched")) relaunched = true;

		// Which adapter suits what this run will draw, rather than which is
		// the most capable - with decimation on the most capable one is the
		// slower of the two.  The workload has to be declared up front because
		// Windows fixes the adapter before any chart exists.
		Tagpu::TChartGPUWorkload workload;
		workload.PointCount = (ParamCount() >= 2)
			? StrToInt64Def(ParamStr(2), 1000000) : 1000000;
		workload.Decimated = true;      // the demo starts with Decimate checked

		if (!relaunched &&
			Tagpu::ApplyWorkloadPreference(Tagpu::HostExecutablePath(), workload))
		{
			UnicodeString args;
			for (int i = 1; i <= ParamCount(); ++i)
				args += "\"" + ParamStr(i) + "\" ";
			args += "--relaunched";
			ShellExecute(0, L"open", ParamStr(0).c_str(), args.c_str(),
				ExtractFilePath(ParamStr(0)).c_str(), SW_SHOWNORMAL);
			return 0;
		}

		if ((ParamCount() >= 1) && SameText(ParamStr(1), "--selftest"))
		{
			int count = (ParamCount() >= 2) ? StrToIntDef(ParamStr(2), 1000000)
										    : 1000000;
			UnicodeString outFile = (ParamCount() >= 3) ? ParamStr(3)
													    : "selftest.txt";
			// The chart needs a window handle before it can make a GL context,
			// so the form has to be shown - but only briefly, and off-screen so
			// it does not steal focus from whatever is in front.
			Application->CreateForm(__classid(TMainForm), &MainForm);
			MainForm->Position = poDesigned;
			MainForm->Left = -32000;
			MainForm->Top = -32000;
			MainForm->Show();
			Application->ProcessMessages();
			MainForm->SelfTest(count, outFile);
			// Shut down the same way the interactive run does.  Returning
			// straight out of _tWinMain without ever entering the message
			// loop tears the VCL down in an order it does not expect, and
			// faults on the way out.
			MainForm->Close();
			Application->Run();
			return 0;
		}

		Application->CreateForm(__classid(TMainForm), &MainForm);
		Application->Run();
	}
	catch (Exception &exception)
	{
		Application->ShowException(&exception);
	}
	catch (...)
	{
		try
		{
			throw Exception("");
		}
		catch (Exception &exception)
		{
			Application->ShowException(&exception);
		}
	}
	return 0;
}
//---------------------------------------------------------------------------
