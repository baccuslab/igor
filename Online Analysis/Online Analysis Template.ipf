#pragma rtGlobals=1		// Use modern global access method.

// To perform an online analysis copy this template into your own procedure window and include the appropriate
//		actions and functions. Make sure to load your procedure before displaying the RecordMEA display.
//
// You must have three functions:
//		1) A main function that performs your online analysis. It must have an '_OA' at the end of its name
//		2) An initialization function that has the same name as your main function with '_init' appended to the end
//		3) A finalization function that has the same name as your main function with '_finish' appended to the end
//
// If you have loaded a procedure with a function ending with '_OA', then there will be a drop-down menu containing
//		all functions ending with '_OA.' Select your desired function from the drop-down menu.
//
// When you check the "Analyze"  checkbox the initialization procedure will run, and if you are already recording the
//		main function will start as well. If you have not started recording then the main function will begin with the recording.
//
// After you are done with the analysis, when you uncheck the analyze button the finalization procedure will run.
//
// VERY IMPORTANT: make sure your analysis does not take longer than the time left over after saving and recording.


function Template_OA(s)
	STRUCT WMBackgroundStruct &s
	
	NVAR onlineAnalysis=$recDF+"onlineAnalysis"
	
	if(!onlineAnalysis)
		return 0
	endif
	
// Place code here.
//
// Will be working on waves titled "wvN" where N is the channel number starting from 0
// These waves are stored in the Recording data folder, which can be accessed using
//		the string constant recDF, i.e. wave wv0 = $recDF+"wv0"
// If you are recording from all 64 channels:
//		wv0 = phototdiode
//		wv1 = voltage
//		wv2 = current
//		wv3 = not in use
//		wv4 - wv63 = MEA channels
// Otherwise waves are namesd in order from 0 - # of channels being recorded
	
	onlineAnalysis=0
	
	return 0
end


// This initialization procedure is started when you check the analyze box. It will run once and then kill itself.
function Template_OA_init(s)
	STRUCT WMBackgroundStruct &s
	
	NVAR running=$recDF+"running"

//	
// Place initialization code here.
//

	CtrlNamedBackground OA_init, stop
	CtrlNamedBackground OA_init, kill
	
	if(running)
		CtrlNamedBackground OnAnalysis,start
	endif
end


// This finalization procedure is started when you uncheck the analyze box. It will run once and then kill itself.
function Template_OA_finish(s)
	STRUCT WMBackgroundStruct &s
	
//	
// Place finalization code here.
//

	CtrlNamedBackground OA_finish, stop
	CtrlNamedBackground OA_finish, kill
end