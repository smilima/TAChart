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
// USEFORM alone leaves TMainForm incomplete; the self-test calls its
// members, so the header is needed here too.
#include "MainUnit.h"
//---------------------------------------------------------------------------
USEFORM("MainUnit.cpp", MainForm);
//---------------------------------------------------------------------------
int WINAPI _tWinMain(HINSTANCE, HINSTANCE, LPTSTR, int)
{
	try
	{
		Application->Initialize();
		Application->MainFormOnTaskBar = true;

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
