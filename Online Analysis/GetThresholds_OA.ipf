#pragma rtGlobals=1		// Use modern global access method.

// To perform an online analysis copy this template into your own procedure and include the appropriate
//		actions and functions into the template. Make sure to change the name of the function from "Template"
//		to a name of your choosing.
//
// Load your procedure into the IGOR recording experiment, and change the Analysis Fxn name in the setting window
//		from "Template" to the name of your function. Then check the "Analyze" checkbox

// VERY IMPORTANT: make sure your analysis does not take longer than the time left over after saving and recording.

// The following global variables are defined in the recordMEA procedure	and are all stored in
// the recording data folder that can be accessed through recDF (a string constant).
// You can access them and modify them AT YOUR OWN RISK
//
//	variable /g length=2 					//Block Size in second
//	variable /g blockSize=length/delta		//Total size of block in samples
//	variable /g FIFOsize=length/delta*2		//Buffer Size
//	variable /g saveFile=0					//To save (1) or not to save (0)
//	variable /g cInject=0					//To inject current (1) or not to inject current (0)
//	variable /g oAnalysis=0				//To perform online analysis (1) or not (0)
//	variable /g fileLength=1650				//Length of each file in seconds
//	variable /g totTime=1600				//Total recording time, can be larger than fileLenght
//	variable /g numDigitalPulse=1			//Number of digital pulses being sent to stimulus (visual) computer
//	variable /g lengthDigitalPulse=.2		//Lenght of the digital pulse in seconds
//	variable /g FIFOrange=10
//	variable /g isPathSet=0
//	variable /g PhotodiodeLevel=-.1			//Level, in volts, of the photodiode signal to trigger current injection.
//										//Remember that Photodiode display is the negative of what the device sees
//	
//	
//	string /g saveName=""										//Name or core name for saved file
//	string /g analysisFunction="Template"				//Name of online analysis function
//	string /g cWave=""					//Name of wave in igor data folder that contains the current waveform
//										//Range of y values cannot exceed 10 to -10
//										//The sample rate and number of samples is set by the wave scaling and the number of data points in the waves.
//	string /g timeString="Time:"
//	string /g colorList=""
//	string /g FIFOname="BaccusFIFO"
//	string /g NIDAQdevice=""
//	
//
//	variable /g cnt=0									//Counter for the number of blocks recorded
//	variable /g reps=ceil(totTime/length)				//Total number of blocks to be recorded
//	variable /g repsPerFile=ceil(fileLength/length)		//Number of blocks in a single file
//	variable /g fileNum=0								//Which file is being saved to
//	variable /g transferFIFO							//Running count of points to transfer from the buffer to waves
//	variable /g runningTime							//Amount of time recorded
//	variable /g onlineAnalysis=0							//Ready to perform an online analysis

static constant  FRAMEPERIOD = 0.01
static constant delta=.0001
strconstant MEAGRAPH = recordMEA



Function GetThresholds_OA_Init(s)
	STRUCT WMBackgroundStruct &s
	DFREF rec_DF = root:recording
	
	NVAR running=rec_DF:running

	// do whatever is necessary at startUp	
	print "Running GetThresholds_OA_Init()"
	
	// axess OA DF
	DFREF OA_DF= root:OA
	 
	// Init all waves
	make /o/n=64 OA_DF:w_sdev 		= 0
	make /o/n=64 OA_DF:w_threshold 	= 0
	make /o/n=64 OA_DF:w_multiplier = 1
	make /o/n=64 OA_DF:w_counter	= 0
	make /o/n=64 OA_DF:w_meanV		= 0
	
	SetVariable sv1 win=$MEAGRAPH, fsize=16, font="Helvetica", pos={700, 10}, size={120,50}, value=_NUM:4, title="Threshold", noProc
	
	CtrlNamedBackground OA_init, stop
	CtrlNamedBackground OA_init, kill
	
	if(running)
		CtrlNamedBackground OnAnalysis,start
	endif
end
	
Function GetThresholds_OA(s)
	STRUCT WMBackgroundStruct &s

	NVAR onlineAnalysis=rec_DF:onlineAnalysis
	if(!onlineAnalysis)
		// onlineAnalysis is design by DK, is the flag that tells you whether to start the analysis or not
		//	if set, you can do whatever calculation you want to but if not set, you have to return
		return 0
	endif

	// (*) Axess OA DF
	DFREF OA_DF = root:OA
	
	// (*) axess channel related waves
	wave w_threshold 	= OA_DF:w_threshold
	wave w_multiplier 	= OA_DF:w_multiplier
	wave w_sdev 		= OA_DF:w_sdev
	wave w_counter 	= OA_DF:w_counter
	wave w_meanV 		= OA_DF:w_meanV
	
	controlInfo /w=$MEAGRAPH sv1
	variable v_threshold = v_value
	
	// (*) loop through all selected channels and update each sdev threshold
	variable i
	for (i=0; i<numChans; i+=1)
		// (*) compute the sdev of the channel
		wave w_ch = $recDF + "wv"+num2str(i)
		wavestats /q w_ch

		// (*) update the mean voltage
		w_meanV[i] =(w_meanV[i]*w_counter[i]+V_avg)/ (w_counter[i]+1)

		// (*) update the sdev for channel i, (avg sigma^2, not sigma)
		variable sdev = w_sdev[i]
		sdev = sqrt( (sdev^2*w_counter[i]+V_sdev^2)/(w_counter[i]+1))
		w_sdev[i] 	= sdev
		w_threshold[i]  = w_meanV[i]+v_threshold*sdev*w_multiplier[i]
		w_counter[i]	+= 1
	endfor
		
	// (*) Update threshold display every so often
	wavestats /q w_counter
	if (mod(V_max, 5)==1)
		DisplayThresholds()
	endif

	onlineAnalysis=0
	return 0
end

Function GetThresholds_OA_Finish(s)
	STRUCT WMBackgroundStruct &s
	
	print "Running GetThresholds_OA_Finish()"
	DFREF OA_DF = root:OA
		
	// clean after running getThresholds
	wave thresholdCounter = OA_DF:w_counter
	wave meanV = OA_DF:w_meanV
	wave sdev = OA_DF:w_sdev
	
	killwaves thresholdCounter, meanV
	KillControl /w=$MEAGRAPH sv1
	
	CtrlNamedBackground OA_finish, stop
	CtrlNamedBackground OA_finish, kill
end

function DisplayThresholds()
	DFREF OA_DF = root:OA
	DFREF rec_DF = root:recording
	
	wave w_threshold=OA_DF:w_threshold
	wave w_selected = OA_DF:w_selected
	
	if (!waveexists (w_threshold))
		return 0
	endif
	variable i

	NVAR length = rec_DF:LENGTH

	// delete all the lines
	DrawAction /w=$MEAGRAPH getgroup=thresholds, delete
	if (V_flag)
//		DrawAction /w=$MEAGRAPH getgroup=thresholds, delete
	endif
//	Print S_recreation
//	for (i=0; i<2; i+=1)
	SetDrawEnv /w=$MEAGRAPH gstart, gname=thresholds
	for (i=0; i<numChans; i+=1)
		wave wv = :Recording:$"wv"+num2str(i)
		string s_axisInfo = TraceInfo(MEAGRAPH, "wv"+num2str(i), 0)
		string leftAxis = StringBykey("YAXIS", s_axisInfo)
		string bottomAxis = StringByKey("XAXIS", s_axisInfo)
		SetDrawEnv /w=$MEAGRAPH linefgc=(0,0,65535), xcoord=$bottomAxis, ycoord=$leftAxis
		DrawLine /w=$MEAGRAPH 0, w_threshold[i], length, w_threshold[i]
	endfor
	SetDrawEnv /w=$MEAGRAPH gstop
end

