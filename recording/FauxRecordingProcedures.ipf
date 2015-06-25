#pragma rtGlobals=1		// Use modern global access method.

CONSTANT numChans=64, delta=0.0001
StrCONSTANT recDF="root:Recording:", OA_DF="root:OA:", room=""
static strconstant MEAGRAPH = recordMEA

function setDefaultGlobals()

	NewDataFolder /o OA
	SetDataFolder root:
	
	NewDataFolder /o/s Recording
	
	variable /g length=2 					//Block Size in second
	variable /g blockSize=length/delta		//Total size of block in samples
	variable /g oAnalysis=0					//To perform online analysis (1) or not (0)
	variable /g totTime=1600				//Total recording time, can be larger than fileLength
	variable /g running=0
	variable /g runTime=0
	variable /g FIFOrange=10
	variable /g loopTime
	variable /g loopTimer
	variable /g displayType=0
	
	string /g analysisFunction="---"				//Name of online analysis function
	
	string /g timeString="Time:"
	
	SetDataFolder root:
end

Menu "Record"
	"Settings",/q, changeSettings()
	"Show Display", /q,showDisplay()
end

//This is what happens when you press start in the display
function Record()

	NVAR length=$recDF+"length"
	NVAR blockSize=$recDF+"blockSize"
	NVAR oAnalysis=$recDF+"oAnalysis"
	NVAR totTime=$recDF+"totTime"
	NVAR running=$recDF+"running"
	
	NVAR FIFOrange=$recDF+"FIFOrange"
	
	running=1
	
	cleanTimers()
	
	SetDataFolder recDF
	
	variable /g cnt=0									//Counter for the number of blocks recorded
	variable /g reps=ceil(totTime/length)				//Total number of blocks to be recorded
	variable /g fileNum=0								//Which file is being saved to
	variable /g transferFIFO							//Running count of points to transfer from the buffer to waves
	variable /g runningTime							//Amount of time recorded
	variable /g onlineAnalysis=0						//Ready to perform an online analysis
	
	variable /g fileRefnum
	variable /g fileOpened
	variable /g headerSize
	open /Z=2/R/F=".bin" fileRefnum
	
	if(!v_flag)
		fileOpened=1
		readHeader(fileRefnum)
		wave /t header
		FIFOrange=-str2num(header[8][1])
		PopupMenu pm1 win=RecordMEA,proc=displayRange,value=doPopUpMenu()
		
		blockSize=str2num(header[6][1])
		totTime=min(str2num(header[3][1])*delta,totTime)
		headerSize=str2num(header[0][1])
	else
		fileOpened=0
	endif
	
	SetDataFolder root:
	
	NVAR cnt=$recDF+"cnt"
	NVAR reps=$recDF+"reps"
	NVAR transferFIFO=$recDF+"transferFIFO"
	NVAR fileRefnum=$recDF+"fileRefnum"
	NVAR fileOpened=$recDF+"fileOpened"
	
	SetDataFolder recDF
	
	variable i
	variable refnum,shouldIstop
	
	SetDataFolder root:
	
	CtrlNamedBackground WriteToWave,proc=WriteToWaveAndFile		//Makes the recording procedure a background task named WriteToWave
	
	variable numTicks=60.15*length
	CtrlNamedBackground WriteToWave,period=numTicks
	
	runningTime=0
	transferFIFO=0
	CtrlNamedBackground WriteToWave,start
	if(oAnalysis)
		CtrlNamedBackground OnAnalysis,start
	endif
end

function WriteToWaveAndFile(s)
	STRUCT WMBackgroundStruct &s

	NVAR reps=$recDF+"reps"
	NVAR transferFIFO=$recDF+"transferFIFO"
	NVAR cnt=$recDF+"cnt"
	NVAR length=$recDF+"length"
	NVAR runningTime=$recDF+"runningTime"
	NVAR blockSize=$recDF+"blockSize"
	NVAR onlineAnalysis=$recDF+"onlineAnalysis"
	NVAR runTime=$recDF+"recordTime"
	
	NVAR fileRefnum=$recDF+"fileRefnum"
	NVAR fileOpened=$recDF+"fileOpened"
	NVAR headerSize=$recDF+"headerSize"
	NVAR loopTime=$recDF+"loopTime"
	NVAR loopTimer=$recDF+"loopTimer"
	
	SVAR timeString=$recDF+"timeString"
	
	variable timer=startMSTimer
	
	onlineAnalysis=0
	
	wave /t chanName=$recDF+"chanName"
	wave whichChan=$recDF+"whichChan"
	
	string chan
	variable i=0
	
	if(fileOpened)
		for(i=0;i<numpnts(whichChan);i+=1)
			wave wv=$recDF+"wv"+num2str(i)
			FsetPos fileRefnum,0
			FsetPos fileRefnum,headerSize+(cnt*blockSize*numChans+i*blockSIze)*2
			FBinRead /b=2 /f=2 fileRefnum,wv
		endfor
	endif
	
	timeString="Time: "+num2str(runningTime)+" - "+num2str(runningTime+length)		//Updating time display
	runningTime+=length			//Updating display time
	transferFIFO+=blockSize
	cnt+=1
	
	if(cnt>=reps)
		doStop(0)
	endif
	
	runTime=StopMSTimer(timer)/1e6
	onlineAnalysis=1
	
	loopTime=stopMSTimer(loopTimer)/1e6
//	print loopTime
	loopTimer=startMSTimer
	
	return 0
end

function readHeader(refnum)
	variable refnum
	
	variable headerSize,type,version,nscans,numberOfChannels
	variable scanRate,blockSize,scaleMult,scaleOff,dateSize,timeSize,userSize
	String dateStr="",timeStr="",userStr=""
	
	
	FBinRead /b=2 /f=3 /u refnum,headerSize
	FBinRead /b=2 /f=2 refnum,type
	FBinRead /b=2 /f=2 refnum,version
	FBinRead /b=2 /f=3 /u refnum,nscans
	FBinRead /b=2 /f=3 refnum,numberOfChannels
	
	make /o/n=(numberOfChannels) whichChan
	
	FBinRead /b=2 /f=2 refnum,whichChan
	FBinRead /b=2 /f=4 refnum,scanRate
	FBinRead /b=2 /f=3 refnum,blockSize
	FBinRead /b=2 /f=4 refnum,scaleMult
	FBinRead /b=2 /f=4 refnum,scaleOff
	FBinRead /b=2 /f=3 refnum,dateSize
	dateStr=PadString(dateStr,dateSize,0)
	FBinRead /b=2 refnum,dateStr
	FBinRead /b=2 /f=3 refnum,timeSize
	timeStr=PadString(timeStr,timeSize,0)
	FBinRead /b=2 refnum,timeStr
	FBinRead /b=2 /f=3 refnum,userSize
	userStr=PadString(userStr,userSize,0)
	FBinRead /b=2 refnum,userStr
	
	make /o/t/n=(11,2) header
	header[0][0]="headerSize"
	header[0][1]=num2str(headerSize)
	header[1][0]="type"
	header[1][1]=num2str(type)
	header[2][0]="version"
	header[2][1]=num2str(version)
	header[3][0]="nscans"
	header[3][1]=num2str(nscans)
	header[4][0]="numberOfChannels"
	header[4][1]=num2str(numberOfChannels)
	header[5][0]="scanRate"
	header[5][1]=num2str(scanRate)
	header[6][0]="blockSize"
	header[6][1]=num2str(blockSize)
	header[7][0]="scaleMult"
	header[7][1]=num2str(scaleMult)
	header[8][0]="scaleOff"
	header[8][1]=num2str(scaleOff)
	header[9][0]="date"
	header[9][1]=dateStr
	header[10][0]="time"
	header[10][1]=timeStr
end

function makeListBoxWaves()
	SetDataFolder recDF
	make /o/n=(numChans) chanSetting=0x30,whichChan=p
	make /o/t/n=(numChans) chanName
	variable i
	for(i=0;i<numChans;i+=1)
		chanName[i]="chan"+num2str(i)
	endfor
	SetDataFolder root:
end

Function CheckAll(name)
	String name

	wave CS=$recDF+"chanSetting"
	
	CS=CS | 0x10
	
	Button b1,title="Check Four",proc=CheckFour,win=Settings
End

Function CheckFour(name)
	String name
	
	wave CS=$recDF+"chanSetting"
	
	CS[0,3]=CS[p] | 0x10
	CS[4,numpnts(CS)-1]=CS[p] & ~0x10
	
	Button b1,title="Check All",proc=CheckAll,win=Settings
End

Function ResetDefaults(name)
	String name
	
	SetDefaultGlobals()
End

Function doneWithSetting(name)
	String name
	
	SetDataFolder recDF
	wave chanSetting
	wave whichChan
	
	duplicate /o chanSetting whichChan
	whichChan=(chanSetting & 0x10)==0x10 ? p : NaN
	sort whichChan,whichChan
	wavestats /q whichChan
	deletepoints v_npnts,v_numNaNs,whichChan
	
	KillWindow Settings
	
	SetDataFolder root:
	
	showDisplay()
End

function changeSettings() 
	
	NVAR /Z length=$recDF+"length"
	if (!NVAR_Exists(length))	
		setDefaultGlobals()
	endif
	
	if(WaveExists($recDF+"chanName")==0)
		makeListBoxWaves()
	endif
	
	wave whichChan=$recDF+"whichChan"

	NewPanel /W=(447,44,782,511)/N=Settings /K=2
	ListBox lb1,pos={0,30},size={150,400},listWave=$recDF+"chanName"
	ListBox lb1,selWave=$recDF+"chanSetting",mode= 4
	
	if(numpnts(whichChan)<numChans)
		Button b1,pos={5,5},size={80,20},proc=CheckAll,title="Check All"
	else
		Button b1,pos={5,5},size={80,20},proc=CheckFour,title="Check Four"
	endif
	
	Button b2,pos={180,5},size={100,20},proc=ResetDefaults,title="Reset Defaults"
	SetVariable setvar1,pos={160,50},size={160,17},title="Block Length (s)"
	SetVariable setvar1,font="Helvetica",fSize=14,value= $recDF+"length"
	PopupMenu pm2 fsize=14,mode=1,pos={160,120},title="Display"
	PopupMenu pm2 proc=whichDisplay,value="default;low density;high density LR;high density UD;hexagonal;"
	Button b3,pos={200,440},size={80,20},proc=doneWithSetting,title="Set"
end

function showDisplay()

	NVAR /Z blockSize=$recDF+"blockSize"
	NVAR /Z length=$recDF+"length"
	if (!NVAR_Exists(length))	
		setDefaultGlobals()
	endif
	
	if(WaveExists($recDF+"chanName")==0)
		makeListBoxWaves()
	endif

	NVAR oAnalysis=$recDF+"oAnalysis"
	NVAR displayType=$recDF+"displayType"
	
	wave whichChan=$recDF+"whichChan"
	
	if(numpnts(whichChan)!=numChans)
		displayType=0
	endif
		
	doWindow RecordMEA
	if(V_flag==1)
		killWindow RecordMEA
	endif
	
	SetDataFolder recDF
	
	variable i,j,k
	for(i=0;i<numChans;i+=1)
		killwaves /z $"wv"+num2str(i)
	endfor
	
	for(i=0;i<numpnts(whichChan);i+=1)
		make /o/w/n=(blockSize) wv
		setscale /p x,0,delta,wv
		duplicate /o wv $"wv"+num2str(i)
	endfor
	
	killwaves /z wv
	
	SetDataFolder root:
	
	display /N=RecordMEA /k=1
	setwindow recordMEA, hook(hSelecteChannels)=GetSelectedChannel
	
	if(WaveExists($OA_DF+"w_selected"))
		wave w_selected=$OA_DF+"w_selected"
		w_selected=0
	endif
	
	makeDisplay(displayType)
	
	modifygraph /W=RecordMEA freepos={0,kwfraction}
	modifygraph /W=RecordMEA rgb=(0,0,0),nticks=2,ZisZ=1,btLen=1.5
	ModifyGraph /W=RecordMEA tick=3,nticks=0,axRGB=(65535,65535,65535)
	ModifyGraph tlblRGB=(65535,65535,65535),alblRGB=(65535,65535,65535)
	movewindow /w=RecordMEA 2,2,2,2

	controlbar 40	
	button bstart win=RecordMEA,fcolor=(3,52428,1),pos={10,5},fsize=14,title="Start",proc=StartStopButton
	SetVariable setvar0,size={140,5},pos={70,5},title="Time (s)"
	SetVariable setvar0,fSize=14,value= $recDF+"totTime"
	PopupMenu pm1 fsize=14,mode=1,pos={550,5},title="Scale"
	PopupMenu pm1 proc=displayRange,value=doPopUpMenu()
	Slider s1 win=RecordMEA,vert=0,value=length,pos={40,800},size={250,0},fsize=12
	variable numTicks=length/.25/2
	Slider s1 live=0,limits={.25,length,.25},proc=timeRescale,ticks=numTicks
	displayRange("pm1",1,"10")
	analyzeButtons()
end

function makeDisplay(type)
	variable type
	
	wave whichChan=$recDF+"whichChan"
	
	variable topPercentage=1
	variable VertSize
	variable horizSize
	variable horizPlace,vertPlace
	string botAxis,leftAxis
	
	variable i,j,k
	k=0
	if(type==0)
		VertSize=(numpnts(whichChan)<16) ? topPercentage/numpnts(whichChan) : topPercentage/16
		horizSize=.96/ceil(numpnts(whichChan)/16)
	
		for(i=0;i<ceil(numpnts(whichChan)/16);i+=1)
			horizPlace=i*horizSize+i*.04/3
			botAxis="b"+num2str(i)
			for(j=0;j<min(numpnts(whichChan),16);j+=1)
				vertPlace=topPercentage-(j+1)*vertSize
				leftAxis="l"+num2str(j)
				wave wv=$recDF+"wv"+num2str(k)
				if(waveexists(wv))
					appendtograph /b=$botAxis /l=$leftAxis wv
					modifygraph axisenab($botAxis)={horizPlace,horizPlace+horizSize},axisenab($leftAxis)={vertPlace,vertPlace+vertSize}
				endif
				k+=1
			endfor
		endfor
	else
		getStructure(type)
		wave displayStructure=$recDF+"displayStructure"
	
		VertSize=topPercentage/dimsize(displayStructure,1)
		horizSize=.96/dimsize(displayStructure,0)
	
		for(i=0;i<dimSize(displayStructure,0);i+=1)
			horizPlace=i*horizSize+i*.04/(dimsize(displayStructure,0)-1)
			botAxis="b"+num2str(i)
			for(j=0;j<dimsize(displayStructure,1);j+=1)
				vertPlace=topPercentage-(j+1)*vertSize
				leftAxis="l"+num2str(j)
				wave wv=$recDF+"wv"+num2str(displayStructure[i][j])
				if(waveexists(wv))
					appendtograph /b=$botAxis /l=$leftAxis wv
					modifygraph axisenab($botAxis)={horizPlace,horizPlace+horizSize},axisenab($leftAxis)={vertPlace,vertPlace+vertSize}
				endif
			endfor
		endfor
	endif
end

function getStructure(type)
	variable type
	setdatafolder recDF
	
	switch(type)
		case 1:
			// Low Density
			make /o/n=(8,8) displayStructure
			displayStructure[0][0]= {0,27, 29, 32, 35, 38, 40,1}
			displayStructure[0][1]= {24, 25, 28, 33, 34, 39, 42, 43}
			displayStructure[0][2]= {22, 23, 26, 31, 36, 41, 44, 45}
			displayStructure[0][3]= {19, 20, 21, 30, 37, 46, 47, 48}
			displayStructure[0][4]= {18, 17, 16, 7, 60, 51, 50, 49}
			displayStructure[0][5]= {15,14, 11, 6, 61, 56, 53, 52}
			displayStructure[0][6]= {13, 12, 9, 4, 63, 58, 55, 54}
			displayStructure[0][7]= {2,10, 8, 5, 62, 59, 57,3}
			break
		case 2:
			// HD Left/Right
			make /o/n=(5,14) displayStructure
			displayStructure[0][0]= {0,1,2,3,NaN}
			displayStructure[0][1]= {53,54,56,58,59}
			displayStructure[0][2]= {51,52,55,60,61}
			displayStructure[0][3]= {49,50,57,62,63}
			displayStructure[0][4]= {48,47,40,35,34}
			displayStructure[0][5]= {46,45,42,37,36}
			displayStructure[0][6]= {44,43,41,39,38}
			displayStructure[0][7]= {NaN,NaN,NaN,NaN,NaN}
			displayStructure[0][8]= {8,9,11,13,14}
			displayStructure[0][9]= {6,7,12,16,17}
			displayStructure[0][10]= {4,5,10,15,18}
			displayStructure[0][11]= {33,32,27,20,19}
			displayStructure[0][12]= {31,30,25,22,21}
			displayStructure[0][13]= {29,28,26,24,23}	
			break
		case 3:
			// HD Up/Down
			make /o/n=(5,14) displayStructure
			displayStructure[0][0]= {0,1,2,3,NaN}
			displayStructure[0][1]= {38,39,41,43,44}
			displayStructure[0][2]= {36,37,40,45,46}
			displayStructure[0][3]= {34,35,42,47,48}
			displayStructure[0][4]= {33,32,25,20,19}
			displayStructure[0][5]= {31,30,27,22,21}
			displayStructure[0][6]= {29,28,26,24,23}
			displayStructure[0][7]= {NaN,NaN,NaN,NaN,NaN}
			displayStructure[0][8]= {53,54,56,58,59}
			displayStructure[0][9]= {51,52,57,60,61}
			displayStructure[0][10]= {49,50,55,62,63}
			displayStructure[0][11]= {18,17,12,5,4}
			displayStructure[0][12]= {16,15,10,7,6}
			displayStructure[0][13]= {14,13,11,9,8}
			break
		case 4:
			// Hexagonal
			make /o/n=(8,9) displayStructure
			displayStructure[0][0]= {0,58,60,63,5,8,NaN,1}
			displayStructure[0][1]= {3,55,57,61,4,7,10,2}
			displayStructure[0][2]= {53,54,56,62,6,11,13,NaN}
			displayStructure[0][3]= {50,51,52,49,59,12,14,16}
			displayStructure[0][4]= {48,47,46,39,9,15,17,18}
			displayStructure[0][5]= {45,44,42,29,19,22,21,20}
			displayStructure[0][6]= {43,41,36,32,26,24,23,NaN}
			displayStructure[0][7]= {NaN,40,37,34,31,27,25,NaN}
			displayStructure[0][8]= {NaN,38,35,33,30,28,NaN,NaN}
			break
	endswitch
	
	setdatafolder root:
end

function analyzeButtons()
	variable which
	
	string list=FunctionList("*_OA",";","")
	
	if(ItemsInList(list,";")>1)
		PopupMenu pm2 fsize=14,mode=1,pos={1050,5},title=""
		PopupMenu pm2 proc=getOAfunc,value=GetOAlist()
		checkbox cb3 win=RecordMEA,mode=0,pos={950,7},fsize=14,title="Analyze",proc=setAnalysis
	endif
end

Function /t getOAlist()
	string list="---;"+FunctionList("*_OA",";","")
	list=RemoveFromList("Template_OA",list)
	
	return list
end

Function getOAfunc(ctrlName,popNum,popStr) : PopupMenuControl
	String ctrlName
	Variable popNum
	String popStr
	
	SVAR analysisFunction=$recDF+"analysisFunction"
	
	analysisFunction=popStr
end

Function StartStopButton(ctrlName) : ButtonControl
	String ctrlName
	if( cmpstr(ctrlName,"bStart") == 0 )
		doStart()
	else
		doStop(1)
	endif
End

Function doStart()
	
	SVAR timeString=$recDF+"timeString"
	
	Button bStart win=RecordMEA,fcolor=(65535,0,0),title="Stop",rename=bstop
	
	killControl /W=RecordMEA setvar0
	KillControl /W=RecordMEA cb1
	KillControl /W=RecordMEA setvar1
	KillControl /W=RecordMEA b2
	KillControl /W=RecordMEA cb2
	KillControl /W=RecordMEA setvar2
	titlebox tb1 win=RecordMEA,fsize=14,pos={100,5},variable=timeString
	
	Record()
	
End

Function doStop(early)
	variable early
	
	NVAR cnt=$recDF+"cnt"
	NVAR runningTime=$recDF+"runningTime"
	NVAR running=$recDF+"running"
	NVAR fileRefnum=$recDF+"fileRefnum"
	NVAR fileOpened=$recDF+"fileOpened"
	
	SVAR timeString=$recDF+"timeString"
	
	variable refnum
	variable i
	wave fileNums=$recDF+"filenums"
	
	CtrlNamedBackground _all_,stop=1
	CtrlNamedBackground WriteToWave, kill
	
	if(fileOpened)
		close fileRefnum
	endif
	
	cnt=0
	runningTime=0
	running=0
	timeString="Time: "
	
	doMiniStop()
End

Function doMiniStop()
	
	doWindow /f RecordMEA

	Button bStop win=RecordMEA,fcolor=(3,52428,1),title="Start",rename=bStart
	KillControl tb1
	KillControl tb2
	KillControl tb3
	SetVariable setvar0,win=RecordMEA,size={140,5},pos={70,5},title="Time (s)"
	SetVariable setvar0,win=RecordMEA,fSize=14,value= $recDF+"totTime"
End

Function setAnalysis(ctrlName,checked) : CheckBoxControl
	String ctrlName
	Variable checked
	
	NVAR running=$recDF+"running"
	
	NVAR oAnalysis=$recDF+"oAnalysis"
	SVAR analysisFunction=$recDF+"analysisFunction"
	
	if(Checked)
		oAnalysis=1
		if(!stringMatch(analysisFunction,"---"))
			KillControl pm2
			titlebox tb4 win=RecordMEA,fsize=14,pos={1050,5},frame=0,title="running "+analysisFunction
			CtrlNamedBackground OnAnalysis, proc=$analysisFunction
			CtrlNamedBackground OA_init, proc=$analysisFunction+"_init"
			CtrlNamedBackground OA_init,start
		endif
	else
		if(!stringMatch(analysisFunction,"---"))
			if(running)
				CtrlNamedBackground OnAnalysis,stop
			endif
			CtrlNamedBackground OnAnalysis, kill
			CtrlNamedBackground OA_finish, proc=$analysisFunction+"_finish"
			CtrlNamedBackground OA_finish,start
			oAnalysis=0
			KillControl tb4
			PopupMenu pm2 win=RecordMEA,fsize=14,mode=1,pos={1050,5},title=""
			PopupMenu pm2 proc=getOAfunc,value=getOAlist()
			analysisFunction="---"
		endif
	endif
End

Function timeRescale(name, value, event) : SliderControl
	String name
	Variable value
	Variable event
	
	wave whichChan=$recDF+"whichChan"	
				
	variable i
	for(i=0;i<ceil(numpnts(whichChan)/16);i+=1)
		SetAxis $"b"+num2str(i) 0,value
	endfor	
					
	return 0
End

Function displayRange(ctrlName,popNum,popStr) : PopupMenuControl
	String ctrlName
	Variable popNum
	String popStr
	
	wave whichChan=$recDF+"whichChan"
	
	string axes=axisList("RecordMEA")
	string thisAxes
	
	variable range=2^16/(2^(popnum-1))/2
	
	variable i
	for(i=0;i<itemsInList(axes);i+=1)
		thisAxes=stringFromList(i,axes)
		if(stringMatch(thisAxes[0],"l"))
			SetAxis $thisAxes -range,range
		endif
	endfor
end

Function whichDisplay(ctrlName,popNum,popStr) : PopupMenuControl
	String ctrlName
	Variable popNum
	String popStr
	
	NVAR displayType=$recDF+"displayType"
	
	displayType=popNum-1
end

function /S doPopUpMenu()

	NVAR FIFOrange=$recDF+"FIFOrange"
	
	string options=""
	
	variable i,range=FIFOrange
	for(i=0;range>.1;i+=1)
		range=floor(FIFOrange/(2^i)*1000)/1000
		options+=num2str(range)+";"
	endfor
	
	return options
end

function cleanTimers()
	variable i,j
	for(i=0;i<10;i+=1)
		j=stopMSTimer(i)
	endfor
end

Function GetSelectedChannel(s)
	// Allows you to click in the MEAGRAPH and select/deselect channels for online analysis
	// In order for this function to work, the following line has to be executed after creation of the MEAGRAPH
	//	setwindow recordMEA, hook(hSelecteChannels)=GetSelectedChannel
	// This function uses and modifies wave $OA_DF+"w_selected"
	STRUCT WMWinHookStruct &s
	
	// access the wave holding all the info related with the channels struct and unpack it
			
	switch(s.eventCode)
		case 3:		//mousedown
			// get the distance between axis L0 and L1
			string axisL0range =  stringByKey("axisEnab(x)", axisinfo("recordmea", "l0"), "=")
			variable v1, v2
			sscanf axisL0range, "{%f, %f}", v1, v2
			variable axisDistance = v2-v1	// in window units. I need it in pixels
			getWindow recordMea wsize	// sets v_top, v_bottom
			axisDistance = floor(axisDistance*(v_bottom-v_top)/2)
			string s_delta = "DELTAX:6;DELTAY:"+num2str(axisDistance)+";"
						
			wave w_selected=$OA_DF+"w_selected"
			if (!waveExists(w_selected))
				make /n=64 $OA_DF+"w_selected"=0
				wave w_selected=$OA_DF+"w_selected"
			endif
			
			string s_trace = StringByKey("TRACE",  TraceFromPixel(s.mouseLoc.h,s.mouseLoc.v,s_delta))

			variable selectedCh = str2num(replaceString("wv", s_trace,""))
			if (numtype(selectedCH)==2)
				return -1
			endif
			
			print s_trace, selectedCh
			if (w_selected[selectedCh])
				// Deselect item. Remove item from list and change color to balck
				w_selected[selectedCH] = 0
				modifygraph /w=recordMEA/z rgb($"wv"+num2str(selectedCH))=(0,0,0)
			else
				// Select item. Remove item from list and change color to red
				w_selected[selectedCH] = 1
				modifygraph /w=recordMEA/z rgb($"wv"+num2str(selectedCH))=(65535,0,0)
			endif
			
			AddChLabel(MEAGRAPH, "wv", yPos = 1)
			AddChannelInfo(selectedCh)
	EndSwitch
end


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

//staticFunction GetSelectedChannel(s)
//	// Allows you to click in the MEAGRAPH and select/deselect channels for online analysis
//	// In order for this function to work, the following line has to be executed after creation of the MEAGRAPH
//	//	setwindow recordMEA, hook(hSelecteChannels)=GetSelectedChannel
//	// This function uses and modifies wave $OA_DF+"w_selected"
//	STRUCT WMWinHookStruct &s
//	
//	// access the wave holding all the info related with the channels struct and unpack it
//			
//	switch(s.eventCode)
//		case 3:		//mousedown
//			// get the distance between axis L0 and L1
//			string axisL0range =  stringByKey("axisEnab(x)", axisinfo("recordmea", "l0"), "=")
//			variable v1, v2
//			sscanf axisL0range, "{%f, %f}", v1, v2
//			variable axisDistance = v2-v1	// in window units. I need it in pixels
//			getWindow recordMea wsize	// sets v_top, v_bottom
//			axisDistance = floor(axisDistance*(v_bottom-v_top)/2)
//			string s_delta = "DELTAX:6;DELTAY:"+num2str(axisDistance)+";"
//						
//			wave w_selected=$OA_DF+"w_selected"
//			if (!waveExists(w_selected))
//				make /n=64 $OA_DF+"w_selected"=1
//				wave w_selected=$OA_DF+"w_selected"
//			endif
//			
//			string s_trace = StringByKey("TRACE",  TraceFromPixel(s.mouseLoc.h,s.mouseLoc.v,s_delta))
//
//			variable selectedCh = str2num(replaceString("wv", s_trace,""))
//			print s_trace, selectedCh
//			if (w_selected[selectedCh])
//				// Deselect item. Remove item from list and change color to balck
//				w_selected[selectedCH] = 0
//				modifygraph /w=recordMEA/z rgb($"wv"+num2str(selectedCH))=(0,0,0)
//			else
//				// Select item. Remove item from list and change color to red
//				w_selected[selectedCH] = 1
//				modifygraph /w=recordMEA/z rgb($"wv"+num2str(selectedCH))=(65535,0,0)
//			endif
//	EndSwitch
//end

function AddChLabel(gname, tracePrefix, [yPos])
	string gname, tracePrefix
	variable yPos
		
	wave w_selected = :OA:w_selected
	if (paramIsDefault(yPos))
		yPos = 1
	endif
	
	variable i
	string myStr =""

	// (*) delete all drawings if any		
	DrawAction /w=$gname getgroup=labels, delete
	SetDrawEnv /w=$gname fsize=16, fstyle=1, textrgb=(65535,0,0), gname=labels, gstart, save
	for (i=0; i<64; i+=1)
		if (w_selected[i])
			// (*) which axes are used for the given RF?
			string leftAxis = StringByKey("YAXIS", imageinfo(gname, tracePrefix+num2str(i), 0))
			string bottomAxis = StringByKey("XAXIS", imageinfo(gname, tracePrefix+num2str(i), 0))

			// if gname has traces instead of images axis will be empty strings
			if (strlen(leftAxis)==0)
				leftAxis = StringByKey("YAXIS", traceinfo(gname, tracePrefix+num2str(i), 0))
				bottomAxis = StringByKey("XAXIS", traceinfo(gname, tracePrefix+num2str(i), 0))
			endif
			GetAxis /w=$gname/q $LeftAxis
			SetDrawEnv /w=$gname xcoord=$bottomAxis, ycoord=$leftAxis
			DrawText /w=$gname 0, floor(v_max)*yPos, num2str(i)
		endif
	endfor
	SetDrawEnv /w=$gname gstop
end

function /wave loadMapping()
	variable refnum

	// (*) Try opening pin-channel-mapping in recording computer path
	string mappingPath = "C:Users:Baccus Lab:Documents:WaveMetrics:Igor Pro 6 User Files:Igor Procedures:pin-channel-mapping.txt"
	open /R refnum as mappingPath
	// (*) if it failed, try opening in PJ computer
	if (refnum==0)
		mappingPath = "~/Documents/Notebook/Igor/MEA Recording/pin-channel-mapping.txt"
		open /R refnum as mappingPath
	endif

	string oneLIne
	
	variable i
	make /o/T/n=(64,4) w_chMapping
	
	string colRow, ch, dist, block
	
	do
		FReadLine refnum, oneLine
		if (strlen(oneLine)==0)
			break
		endif
		
		if (stringmatch(oneLIne, "#*"))
			continue
		else
			splitstring /E="([0-9]*)\t([0-9]*)\t([TRLB])\t([0-9]*)" oneLine, colRow, ch, block, dist
			
			// (*) Flip 180 degrees the preamplifier (change calRow[] by 99-{colRow[1], colRow[0]}
			
			string newColRow = num2str(9-str2num(colRow[0]))
			newColRow+= num2str(9-str2num(colRow[1]))
			
//			print colRow, newColRow, ch, block, dist
			variable pnt = str2num(ch)
			w_chMapping[pnt][0] = newColRow
			w_chMapping[pnt][1] = ch
			w_chMapping[pnt][2] = block
			w_chMapping[pnt][3] = dist
		endif
	while (1)
	
	close refnum
	
	return w_chMapping
end

function 	AddChannelInfo(ch)
	variable ch
	
	string myStr
	wave /T w_chMapping
	if (!waveExists(w_chMapping))
		wave /T w_chMapping = loadMapping()
	endif
	string colRow = w_chMapping[ch][0]
	string block = w_chMapping[ch][2]
	string dist =  w_chMapping[ch][3]
	sprintf myStr, "\Z14ColRow=%s, Block=%s, Distance from Top or Left is %s", colrow, block, dist
	TextBox/N=channelInfo/C/X=-3/Y=100 myStr
end

function writeHeader(refnum, [extraSize])
	variable refnum
	variable extraSize
	
	if (paramIsDefault(extraSize))
		extraSize = 0
	endif
	
	NVAR length=$recDF+"length"
	NVAR fileLength=$recDF+"fileLength"
	NVAR totTime=$recDF+"totTime"
	NVAR blockSize=$recDF+"blockSize"
	NVAR FIFOrange=$recDF+"FIFOrange"
	
	wave whichChan=$recDF+"whichChan"
	
	variable headerSize
	variable nscans
	
	nscans=TotTime/delta
		
	variable type=2
	variable version=1
	variable numberOfChannels=numpnts(whichChan)
	variable scanRate=1/delta
	variable scaleMult=FIFOrange*2/2^16		//To convert from 16 bit data to volts
	variable scaleOff=-FIFOrange
	variable dateSize=strlen(date())
	String dateStr=date()
	variable timeSize=strlen(time())
	String timeStr=time()
	String userStr="recorded in "+room
	variable userSize=strlen(userStr)
	
	headerSize=200 + extraSize
	
	// Remember pointer's position into the file before going to byte 0 to start writing header
	FStatus refnum
	variable next_byte_to_write = v_filepos
	
	fSetPos refnum,0
	FBinWrite /b=2 /f=3 /u refnum,headerSize
	FBinWrite /b=2 /f=2 refnum,type
	FBinWrite /b=2 /f=2 refnum,version
	
	Fstatus refnum
	SetDataFolder recDF
	variable /g nscansPos=v_filePos
	SetDataFolder root:
	
	FBinWrite /b=2 /f=3 /u refnum,nscans
	FBinWrite /b=2 /f=3 refnum,numberOfChannels
	FBinWrite /b=2 /f=2 refnum,whichChan
	FBinWrite /b=2 /f=4 refnum,scanRate
	FBinWrite /b=2 /f=3 refnum,blockSize
	FBinWrite /b=2 /f=4 refnum,scaleMult
	FBinWrite /b=2 /f=4 refnum,scaleOff
	FBinWrite /b=2 /f=3 refnum,dateSize
	FBinWrite /b=2 refnum,dateStr
	FBinWrite /b=2 /f=3 refnum,timeSize
	FBinWrite /b=2 refnum,timeStr
	FBinWrite /b=2 /f=3 refnum,userSize
	FBinWrite /b=2 refnum,userStr
	
	Fstatus refnum
	headerSize=v_filePos
	fsetPOS refnum,0
	
	FBinWrite /b=2/f=3/u refnum,headerSize
	
	fsetPos refnum,headerSize
	fsetPos refnum, next_byte_to_write
end

function writeHeaderNow(refnum, extrasize)
	// 	This function is a patch to be able to link a FIFO to a file and use Davids' writeHeader.
	//	
	//	Start the FIFO and record all the data. At the end write David's header at the beginning of the file
	//	with this function.
	//
	//	the binary file prior to this funciton has Igor FIFO's header first and all experimental data afterwords.
	//	v_filePos points to where next byte would be inserted in the fle
	//	I need to go back to the beginning and write David's header (which is shorter than the FIFO's one and will
	//	not overwrite any data in the file)
	//	After writing the header, go back to the end of data (previous v_filePos) and close the file.
	//	Any bytes after current pointer in file will be lost when the file is closed. Therefore if I close
	//	the file after writing the header, all data will be lost
	variable refnum, extrasize
	
	FStatus refnum
	variable endOfData = v_filePos

	writeHeader(refnum, extraSize = extrasize)		// goes to start of file and writes header

	// set file's pointer back to where it was before this function
	FSetPos refnum, endOfData
		
	// At this point the file has David's header plus some "extrasize" bytes and the data that was recorded up to this point.
	// Now the file can be closed or more data can be added to it.
end