#pragma rtGlobals=1		// Use modern global access method.
#include "  Macintosh HD:Users:jadz:Documents:Notebook:Igor:onlineAnalysis:Tested:GetThresholds"

// ******************************************* //

static constant PSTHbin = .01
static constant PSTHperiod = .500191   // 30*framePeriod, in seconds

// ******************************************* //

Function GetPSTH_OA_Init(s)
	STRUCT WMBackgroundStruct &s
	
	DFREF rec_DF = root:recording
	NVAR running=rec_DF:running

	// do whatever is necessary at startUp	
	print "Running GetPSTH_OA_Init()"

	DFREF OA_DF = root:OA

	// (*) Make waves needed for GetPSTH_OA
	//		w_PSTH holds each channels' psth
	//		w_hist, spike times are moded with the PSTHperiod and histogram in w_hist
	//		v_startT,	when the PSTH started being computed.
	make /o/n=(64, ceil(PSTHperiod/PSTHbin)) OA_DF:w_PSTH=0
	setscale /p x, 0, 1, "channel", OA_DF:w_PSTH
	setscale /p y, 0, PSTHbin, "s", OA_DF:w_PSTH
	setscale /p d, 0, 1, "Hz", OA_DF:w_PSTH
	make /o OA_DF:w_hist

	// (*) Grab the time at which the PSTH is starting?
	variable /G OA_DF:v_startT
	NVAR v_startT = OA_DF:v_startT
	NVAR runningTime = rec_DF:runningTime		// Defined in DK's MEA recording, keeps track of total recorded time.  Gets reset to 0 when you stop acquiring data
	v_startT = numtype(runningTime)==2? 0 : runningTime

	string gname = "gPSTH"
	if (strlen(winlist(gname, ";", "win:1")))
		killwindow $gname
	endif
	ShowPSTH()
	
	CtrlNamedBackground OA_init, stop
	CtrlNamedBackground OA_init, kill
	if(running)
		CtrlNamedBackground OnAnalysis,start
	endif
end
	
Function GetPSTH_OA(s)
	// init and get thresholds
	STRUCT WMBackgroundStruct &s

	DFREF OA_DF = root:OA
	DFREF rec_DF = root:recording

	NVAR onlineAnalysis=rec_DF:onlineAnalysis
	if(!onlineAnalysis)
		// onlineAnalysis is design by DK, is the flag that tells you whether to start the analysis or not
		//	if set don't get in here and do whatever calculation you want to
		return 0
	endif

		
	// (*) axess some needed waves from OA_DF
	wave w_selected = OA_DF:w_selected
	wave w_threshold = OA_DF:w_threshold
	wave w_PSTH = OA_DF:w_PSTH
	wave w_hist = OA_DF:w_hist

	// (*) compute number of trials that went into the PSTH before adding last block and once the new block is added. Each block lasts "LENGTH" seconds
	NVAR v_startT = OA_DF:v_startT, LENGTH = rec_DF:length, runningTime = rec_DF:runningTime
	variable previousTrialsN = ceil((runningTime - v_startT-LENGTH)/PSTHperiod)
	variable newTrialsN = ceil((runningTIme - v_startT)/PSTHperiod)

	variable i, j, spikePnt
	for (i=0; i<numChans; i+=1)
		if (w_selected[i])
			// (*) Find # and position of thresholds crossings for each channel
			wave w_ch = rec_DF:$"wv"+num2str(i)
			findlevels /q /edge=1   w_ch, w_threshold[i]	// discard crossings that are closer than 0.5 ms 
			if (V_levelsFound==0)
				continue
			endif
			wave W_FindLevels
			w_findLevels += runningTime - LENGTH - v_startT
			// (*) convert the spike times to rx
			w_findLevels = mod(w_findLevels, PSTHperiod)

			if (V_levelsFound==0)
				continue
			elseif (V_levelsFound==1)
				w_hist = 0
				w_hist[floor(w_findLevels/PSTHbin)] = 1
			else
				// (*) change the spike times to pnt coordinates of w_PSTH
				histogram /b={0, PSTHbin, PSTHperiod/PSTHbin} w_findLevels, w_hist
			endif	

			// (*) update PSTH for channel i taking into account number of trials already executed.
			w_PSTH[i][] = (  w_PSTH[i][q]*previousTrialsN+w_hist[q]   )/(newTrialsN)
		endif
	endfor
	onlineAnalysis=0
	return 0
end

Function GetPSTH_OA_Finish(s)
	STRUCT WMBackgroundStruct &s
	
	print "Running GetThresholds_OA_Finish()"
	DFREF OA_DF = root:OA
	
	// clean after running getThresholds
	wave w_hist = OA_DF:w_hist	
	killwaves w_hist
	killvariables OA_DF:v_startT
	
	CtrlNamedBackground OA_finish, stop
	CtrlNamedBackground OA_finish, kill
end

Function ShowPSTH()
	DFREF OA_DF = root:OA
	
	wave /SDFR = OA_DF w_selected, w_PSTH

	colorTab2Wave rainbow16//dbz21
	wave M_colors	
	variable colorsN = dimsize(M_colors,0)
	
	wavestats /q w_selected
	variable step = 5// max(round((colorsN-1)/V_max/2), 1)

	// (*) make display if not already created
	string gname = "gPSTH"
	if (strlen(winlist(gname, ";", "win:1"))==0)
		display /n=$gname/k=1 as gname
		controlbar 40
		
		ValDisplay period, pos={10,10}, bodyWidth=50, title="Period (s)", value = _NUM:PSTHPeriod
		ValDisplay binning, pos={200,10}, bodyWidth=50, title="Binning (s)", value = _NUM:PSTHBin
		variable i, index, indexColor
		for (i=0; i<numChans; i+=1)
			if (w_selected[i])
				appendtograph /w=$gname w_PSTH[i][]
				indexColor = mod(index*step, colorsN)		
				modifygraph /w=$gname rgb[index] = (M_colors[indexColor][0],M_colors[indexColor][1],M_colors[indexColor][2])
				index+=1
			endif
		endfor
		
		Legend/C/N=text0/F=0/A=MC
	endif
	
end

