#pragma rtGlobals=1		// Use modern global access method.

// on 111913 PJ is changing code to always save the experiment. In the event that someone forgets to click the save button it will still save the experiment to a default location with a default name.

CONSTANT numChans=64, delta=0.0001
CONSTANT FIFO_HEADER_SIZE1=304		// length of FIFOFIleHeader, independent of # of recorded channels
CONSTANT FIFO_HEADER_SIZE2=76			// length of ChartChanInfo, part of FIFO header that depends on # of channel. This is the size per channel

StrCONSTANT WiringType="NRSE",recDF="root:Recording:"
StrCONSTANT OA_DF="root:OA:"
StrCONSTANT room="d239"
StrConstant s_defaultName = "Default"	// added by PJ on 111913

function setDefaultGlobals()

	NewDataFolder /o OA
	
	NewDataFolder /o/s Recording
	
	variable /g length=2 					//Block Size in second
	variable /g blockSize=length/delta		//Total size of block in samples
	variable /g FIFOsize=length/delta*2		//Buffer Size
	variable /g saveFile=0					//To save (1) or not to save (0)
	variable /g cInject=0					//To inject current (1) or not to inject current (0)
	variable /g oAnalysis=0				//To perform online analysis (1) or not (0)
	variable /g fileLength=1650				//Length of each file in seconds
	variable /g totTime=1600				//Total recording time, can be larger than fileLenght
	variable /g numDigitalPulse=1			//Number of digital pulses being sent to stimulus (visual) computer
	variable /g lengthDigitalPulse=.2		//Lenght of the digital pulse in seconds
	variable /g FIFOrange=10
	variable /g isPathSet=0
	variable /g running=0
	variable /g runTime=0
	variable /g loopTime
	variable /g loopTimer
	variable /g displayType=0				// Which display will be presented. 0 is the default display. This refers
											// to electrode arrangment in RecordMEA
	variable /g PhotodiodeLevel=-.1			//Level, in volts, of the photodiode signal to trigger current injection.
											//Remember that Photodiode display is the negative of what the device sees
	
	variable /g start_time=-1				// added by PJ on 150317, time stamp with experiment start time
	variable /g refnum	= 0					// pointer to file storing data
	variable /g FIFO_refnum=0				// pointer to file storing FIFO's header and data. Only needed when using MEA_display
	
	string /g saveName=getDate()			//Name or core name for saved file
	string /g analysisFunction="---"			//Name of online analysis function
	string /g cWave=""						//Name of wave in igor data folder that contains the current waveform
											//		must end with "_cur"
											//Range of y values cannot exceed 10 to -10
											//The sample rate and number of samples is set by the wave scaling and
											//		the number of data points in the waves.
	string /g timeString="Time:"
	string /g colorList=""
	string /g FIFOname="BaccusFIFO"
	string /g NIDAQdevice=""
	string /g Display_name					// to distinguish between RecordMEA and MEA_display
	
	SetDataFolder root:
end

Menu "Record"
	"Settings",/q, changeSettings()
	"Show Fancy", /q, showDisplay()
	"Show Simple", /q,MEA_display()
end

//This is what happens when you press start in the display
function Record()

	NVAR length=$recDF+"length"
	NVAR blockSize=$recDF+"blockSize"
	NVAR saveFile=$recDF+"saveFile"
	NVAR cInject=$recDF+"cInject"
	NVAR oAnalysis=$recDF+"oAnalysis"
	NVAR fileLength=$recDF+"fileLength"
	NVAR totTime=$recDF+"totTime"
	NVAR running=$recDF+"running"
	NVAR PhotoDiodeLevel=$recDF+"PhotodiodeLevel"
	
	// bnaecker 20 Jan 2015
	NVAR FIFOrange = $recDF + "FIFOrange"
	//
	
	// PJ 150317
	NVAR start_time = $recDF + "start_time"
	
	start_time = datetime
	//

	SVAR FIFOname=$recDF+"FIFOname"
	SVAR NIDAQdevice=$recDF+"NIDAQdevice"
	SVAR saveName=$recDF+"saveName"
	SVAR cWave=$recDF+"cWave"
	SVAR display_name=$recDF+"display_name"
	
	running=1
	
	cleanTimers()
	
	SetDataFolder recDF
	
	variable /g cnt=0									//Counter for the number of blocks recorded
	variable /g reps=ceil(totTime/length)				//Total number of blocks to be recorded
	variable /g transferFIFO							//Running count of points to transfer from the buffer to waves
	variable /g runningTime							//Amount of time recorded
	variable /g onlineAnalysis=0						//Ready to perform an online analysis
	
	SetDataFolder root:
	
	NVAR cnt=$recDF+"cnt"
	NVAR reps=$recDF+"reps"
	NVAR transferFIFO=$recDF+"transferFIFO"
	NVAR refnum = $recDF+"refnum"
	NVAR fifo_refnum = $recDF+"FIFO_refnum"
	
	SetDataFolder recDF
	
	variable i
	variable overwrite
	
	
	//Create and open file for saving. what we do with the file and its exact name depends on the display
	//	RecordMEA:		write the header for the time being
	//					file extension is .bin
	//	MEA_display:	Writes 2 files, our header on one side and the FIFO's header and data.
	//					That file will be populated by the FIFO, just open it now and keep it around
	if(saveFile)
		//checking if file already exists
		open /P=path1/F=".bin"/R/Z=1 refnum as saveName+".bin" 
		if(v_flag==0) 
			//file exists, should we overwrite it?
			close refnum
			overwrite = fileExists(saveName+".bin")	//ask if you want to overwrite file
			if(overwrite)
				SetDataFolder root:
				doMiniStop()
				return 0
			endif

		endif
		open /P=path1/F=".bin" refnum as saveName+".bin"
	else	
		// save to default file
		open /P=default_path/F=".bin" refnum as s_defaultName+".bin"		//create file
	endif

	writeHeader()

	// If running from MEA_display, the data will be stored in a different file, create it
	if (stringmatch(Display_name, "MEA_display"))
		// Create a file for FIFO's data, use same path and name as for header file but with _FIFO
		if (saveFile)
			open /P=path1 FIFO_refnum as saveName+"_FIFO"
		else
			open /P=default_path FIFO_refnum as s_defaultName+"_FIFO"
		endif
	endif
		
	SetDataFolder root:
	
	//If you are injecting current this inilializes the waveform generator
	if(cInject && stringmatch(cwave,"")==0 && WaveExists($cWave))
		DAQmx_WaveformGen /DEV=NIDAQdevice /TRIG={"/"+NIDAQdevice+"/ai/StartTrigger"} cWave+",0"
	endif

	makeFIFO()
		
	string FIFOchans=getChannelInfo()
	
	CtrlNamedBackground WriteToWave,proc=WriteToWaveAndFile		//Makes the recording procedure a background task named WriteToWave
	
	runningTime=0
	CtrlFIFO $FIFOname,start
	
	doDigitalPulse()
	
	if(cInject)
		DAQmx_Scan /DEV=NIDAQdevice /TRIG={NIDAQdevice+"/ai0",2,0,PhotodiodeLevel}  FIFO=FIFOname+FIFOchans		//Triggers off of the photodiode
	else
		DAQmx_Scan /DEV=NIDAQdevice FIFO=FIFOname+FIFOchans		//Starts immediately
	endif
	transferFIFO=0
	CtrlNamedBackground WriteToWave,start
	if(oAnalysis)
		CtrlNamedBackground OnAnalysis,start
	endif
	
	return 1
end

// Prompts user to either overwrite a preexisting file or quit record
function fileExists(stringName)
	string stringName

	variable /g doOverwrite
	variable well
	newPanel /k=2 /N=ToOverwriteOrNot
	TitleBox tb1 win=ToOVerWriteOrNot,fsize=14,frame=0,title="File already exists"
	Button b1 win=ToOVerWriteOrNot,title="Overwrite?",pos={10,20},size={60,20},proc=overwriteFile
	Button b2 win=ToOVerWriteOrNot,title="Quit?",size={60,20},proc=quitRun
	PauseForUser ToOVerWriteOrNot

	well=doOverwrite
	killVariables doOverwrite
	variable refnum
	if(well) //overwrite preexisitng file
		return 0
	else //quit recording
		return 1
	endif
end

function overwriteFile(name)
	string name
	NVAR doOverwrite
	
	doOverwrite=1
	KillWindow ToOVerWriteOrNot
end

function quitRun(name)
	string name
	NVAR doOverwrite
	
	doOverwrite=0
	KillWindow ToOVerWriteOrNot
end

function writeHeader([FIFO_header_size_flag])
	variable FIFO_header_size_flag
	
	NVAR refnum = $recDF+"refnum"
	
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
	
	variable dummy_size = 200		// real header size will be computed after writing the header

	// Remember pointer's position into the file before moving it to the beginning
	Fstatus refnum
	variable next_byte_position = v_filepos
	print v_filepos
	
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
	
	// figure out header's size
	if (!paramisdefault(FIFO_header_size_flag))
		// use as size Igor's FIFO header size
		headerSize = FIFO_HEADER_SIZE1 + numpnts(whichChan) * FIFO_HEADER_SIZE2 
	else
		// use current position in file
		Fstatus refnum
		headerSize=v_filePos
	endif

	fsetPOS refnum,0
	FBinWrite /b=2/f=3/u refnum,headerSize
	
	// if using David's system, the header is written at the beginning. The file will have 0 size and next_byte_position will be 0
	// if using a FIFO directly into the file, the header is written at the end and next_byte_position will be a number equal to the 
	// FIFO's header size + all the data
	if (next_byte_position < headerSize)
		// writing header at beginning, keep the header and set pointer right after header
		fsetPos refnum,headerSize
	else
		// writing header at end of experiment, keep the data
		fsetpos refnum, next_byte_position
	endif
end

function fixHeader()
	NVAR cnt=$recDF+"cnt"
	NVAR reps=$recDF+"reps"
	NVAR blockSize=$recDF+"blockSize"
	NVAR nscansPos=$recDF+"nscansPos"
	NVAR saveFile = $recDF+"saveFile"
	NVAR refnum = $recDF + "refnum"
	
	SVAR saveName=$recDF+"saveName"
	SVAR display_name = $recDF + "display_name"
	
//	if (stringmatch(display_name, "Record_MEA"))
		// fix the header if we stop before recording was done
		
		// 		Is it needed to open the file? isn't it arlready open?
//		if (saveFile)
//			open /A/P=path1/F=".bin" refnum as saveName+".bin"
//		else
//			open /A/P=default_path/F=".bin" refnum as s_defaultName+".bin"
//		endif
		
		
	// Remember pointer's position into the file before moving it to nscansPos
	Fstatus refnum
	variable next_byte_position = v_filepos
	print v_filepos

	variable nscans=cnt*blockSize
	Fstatus refnum
	fsetpos refnum,nscansPos
	FBinWrite /b=2 /f=3 /u refnum,nscans
	
	fsetpos refnum, next_byte_position
//		close refnum 
//	endif
end

function makeFIFO()

	NVAR FIFOsize=$recDF+"FIFOsize"
	NVAR FIFOrange=$recDF+"FIFOrange"
	NVAR FIFO_refnum = $recDF + "FIFO_refnum"
	NVAR blockSize = $recDF + "blockSize"
	
	SVAR FIFOname=$recDF+"FIFOname"
	SVAR display_name=$recDF+"display_name"
	
	wave /t chanName=$recDF+"chanName"
	wave whichChan=$recDF+"whichChan"
	wave /SDFR=$recDF params = FIFOchan_params
	
	NewFIFO $FIFOname

	variable i
	for(i=0;i<numpnts(whichChan);i+=1)
		NewFIFOChan /W $FIFOname,$chanName[whichChan[i]],params[i][%v_offset],params[i][%v_gain],params[i][%minusFS],params[i][%plusFS],""
	endfor
	CtrlFIFO $FIFOname,deltaT=delta
	CtrlFIFO $FIFOname,size=FIFOsize

	// Link the FIFO to a file. This is only needed if display_name is MEA_display
	if (stringmatch(display_name, "MEA_display"))
		CtrlFIFO $FIFOname, file=FIFO_refnum, flush
	endif	
end


function /S getChannelInfo()

	NVAR FIFOrange=$recDF+"FIFOrange"

	string channelstring =""
	
	wave whichChan=$recDF+"whichChan"
	
	variable i
	for(i=0;i<numpnts(whichChan);i+=1)
		if(whichChan[i]>3)
			channelstring+=";"+num2str(whichChan[i]+12)+"/"+WiringType+",-"+num2str(FIFOrange)+","+num2str(FIFOrange)+",-1,0"
		elseif(whichChan[i]==0)
//			channelstring+=";"+num2str(whichChan[i])+"/"+WiringType+",-"+num2str(FIFOrange)+","+num2str(FIFOrange)+",-1,0"
			channelstring+=";"+num2str(whichChan[i])+"/"+"RSE"+",-"+num2str(FIFOrange)+","+num2str(FIFOrange)+",-1,0"
		else
//			channelstring+=";"+num2str(whichChan[i])+"/"+WiringType+",-"+num2str(FIFOrange)+","+num2str(FIFOrange)+",1,0"
			channelstring+=";"+num2str(whichChan[i])+"/"+"RSE"+",-"+num2str(FIFOrange)+","+num2str(FIFOrange)+",1,0"
		endif
	endfor
	return channelstring 
end

//Digital pulse used to trigger WaitForRec() on the stimulus computer
function doDigitalPulse()
	
	NVAR numDigitalPulse=$recDF+"numDigitalPulse"
	NVAR lengthDigitalPulse=$recDF+"lengthDigitalPulse"
	NVAR cInject=$recDF+"cInject"
	
	SVAR NIDAQdevice=$recDF+"NIDAQdevice"
	
	variable numTicks=lengthDigitalPulse*60
	
	variable i,j
	
	DAQmx_DIO_Config /DEV=NIDAQdevice /CLK={"/"+NIDAQdevice+"/ctr0internaloutput"} /DIR=1 "/"+NIDAQdevice+"/port0/line0"
	fDAQmx_DIO_Write(NIDAQdevice, V_DAQmx_DIO_TaskNumber, 0)
	
	for(i=0;i<numDigitalPulse;i+=1)
		j=ticks+numTicks
		do
		while(j>ticks)
		
		fDAQmx_DIO_Write(NIDAQdevice, V_DAQmx_DIO_TaskNumber, 1)
		
		j=ticks+numTicks
		do
		while(j>ticks)
		
		fDAQmx_DIO_Write(NIDAQdevice, V_DAQmx_DIO_TaskNumber, 0)
	endfor
	
	fDAQmx_DIO_Finished(NIDAQdevice, V_DAQmx_DIO_TaskNumber)
end

function WriteToWaveAndFile(s)
	STRUCT WMBackgroundStruct &s

	// PJ commented all this function on 150317 and added these lines
	NVAR start_time = $recDF + "start_time"
	NVAR totTime=$recDF+"totTime"
	NVAR blockSize=$recDF+"blockSize"
	
	SVAR timeString=$recDF+"timeString"
	SVAR display_name = $recDF + "display_name"
	
	
	if (stringmatch(display_name, "MEA_display"))
		variable recorded_time = datetime - start_time	
		timeString="Time: "+num2str(recorded_time)
		
		if (recorded_time >= totTime + blockSize*delta)	// record a bit more than requested time. 
													// not sure why but seems to recording less than requested time
			doStop(0)
		endif
	else
		// Display is RecordMEA
	
		NVAR reps=$recDF+"reps"
		NVAR transferFIFO=$recDF+"transferFIFO"
		NVAR cnt=$recDF+"cnt"
		NVAR length=$recDF+"length"
		NVAR saveFile=$recDF+"saveFile"
		NVAR runningTime=$recDF+"runningTime"
		NVAR runTime=$recDF+"runTime"
		NVAR onlineAnalysis=$recDF+"onlineAnalysis"
		NVAR loopTime=$recDF+"loopTime"
		NVAR loopTimer=$recDF+"loopTimer"
		NVAR refnum = $recDF + "refnum"
		
		SVAR timeString=$recDF+"timeString"
		SVAR FIFOname=$recDF+"FIFOname"
		SVAR NIDAQdevice=$recDF+"NIDAQdevice"
		FIFOStatus /q $FIFOname
		
		if(v_FIFOChunks<transferFIFO+blockSize)
			return 0
		endif
		
		variable timer=startMSTimer
		
		onlineAnalysis=0
		
		wave /t chanName=$recDF+"chanName"
		wave whichChan=$recDF+"whichChan"
		
		string chan
		variable i=0

		for(i=0;i<numpnts(whichChan);i+=1)
			wave wv=$recDF+"wv"+num2str(i)
			FIFO2wave /r=[transferFIFO,transferFIFO+blockSize-1] $FIFOname,$chanName[whichChan[i]],wv
			FBinWrite /B=2/F=2 refnum,wv
		endfor
		
		timeString="Time: "+num2str(runningTime)+" - "+num2str(runningTime+length)		//Updating time display
		runningTime+=length			//Updating display time
		transferFIFO+=blockSize
		cnt+=1
		
		if(cnt>=reps)
			doStop(0)
		endif
		
		runTime=stopMSTimer(timer)/1e6
		onlineAnalysis=1
		
	//	loopTime=stopMSTimer(loopTimer)/1e6
	//	print loopTime
	//	loopTimer=startMSTimer
	endif
	
	return 0
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

	NVAR isPathSet=$recDF+"isPathSet"
	
	SetDataFolder recDF
	wave chanSetting
	wave whichChan
	
	duplicate /o chanSetting whichChan
	whichChan=(chanSetting & 0x10)==0x10 ? p : NaN
	sort whichChan,whichChan
	wavestats /q whichChan
	deletepoints v_npnts,v_numNaNs,whichChan
	
	KillWindow Settings
	
	variable deviceOn
	deviceOn=getDeviceName()
	
	if(deviceOn==0)
		changeSettings()
		return 0
	endif
	
	if(!isPathSet)
		// Get default pathway to save data when "Save File" is NOT selected
		string s_default = parseFIlePath(1, specialDirPath("Documents", 0, 0, 0),":", 1, 0) + "Downloads:"
		newPath /q/o default_path, s_default

		// Get pathway to save data when "Save File" is selected
		NewPath /q/o path1 "C:"
		PathInfo /S path1
		
		NewPath /q/o/M="Where would you like to save your files?" path1
		
		isPathSet=1
	endif
	
	SetDataFolder root:
	
	if (stringmatch(name, "b3"))
		showDisplay()
	elseif (stringmatch(name, "b4"))
		execute("MEA_display()")
	endif
End

function getDeviceName()

	SVAR NIDAQdevice=$recDF+"NIDAQdevice"
	
	string list=fDAQmx_DeviceNames()
	
	if(ItemsinList(list,";"))
		NIDAQdevice=StringFromList(0,list,";")
	elseif(ItemsinList(list,";")>1)
		NVAR thatOne
		chooseDevice(list)
		NIDAQdevice=StringFromList(thatOne,list,";")
		KillVariables /z thatOne
	else
		deviceIsOff()
		return 0
	endif
end

function chooseDevice(list)
	string list
	
	variable /g number=ItemsinList(list,";")
	variable /g thatOne
	
	variable which
	
	NewPanel /N=WhichDevice /K=2
	
	TitleBox tb1 win=WhichDevice,Frame=0,fsize=14,Title="Which Device?"
	CheckBox cb0 win=WhichDevice,value=1,mode=1,pos={0,30},title="1",proc=radioControl
	
	string CtrlName
	variable i
	for(i=1;i<number;i+=1)
		CtrlName="cb"+num2str(i)
		CheckBox $CtrlName win=WhichDevice,value=0,mode=1,title=num2str(i+1),proc=radioControl
	endfor
	
	Button b1 win=WhichDevice,title="Done",proc=choseDevice
	
	PauseForUser WhichDevice
end

Function radioControl(name,value)
	String name
	Variable value
	
	NVAR number
	NVAR thatOne
	
	string CtrlName
	
	variable i
	for(i=0;i<number;i+=1)
		CtrlName="cb"+num2str(i)
		CheckBox $CtrlName,value=StringMatch(name,CtrlName)
		if(StringMatch(name,CtrlName))
			thatOne=i
		endif
	endfor
End

function choseDevice(name)
	string name
	NVAR Number
	NVAR thatOne
	
	variable returnNumber=thatOne
	
	KillVariables /z Number
	KillWindow WhichDevice
end

function deviceIsOff()
	
	SVAR NIDAQdevice=$recDF+"NIDAQdevice"
	
	newPanel /N=DeviceOff /K=1
	TitleBox tb1 win=DeviceOff,Frame=0,fsize=14,title="Please turn NIDAQ on, then try again."
	PauseForUser DeviceOff
	return 0
end

function changeSettings() 
	
	NVAR /Z length=$recDF+"length"
	if (!NVAR_Exists(length))	
		setDefaultGlobals()
	endif
	
	if(WaveExists($recDF+"chanName")==0)
		makeListBoxWaves()
	endif
	
	NVAR /Z FIFOrange=$recDF+"FIFOrange"
	
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
	SetVariable setvar0,pos={160,30},size={160,17},title="File Length (s)"
	SetVariable setvar0,font="Helvetica",fSize=14,value= $recDF+"fileLength"
	SetVariable setvar1,pos={160,50},size={160,17},title="Block Length (s)"
	SetVariable setvar1,font="Helvetica",fSize=14,value= $recDF+"length"
	SetVariable setvar2,pos={160,70},size={160,17},title="Stim Trigger"
	SetVariable setvar2,font="Helvetica",fSize=14,value= $recDF+"PhotodiodeLevel"
	variable popStart=whatIsTheRange()
	PopupMenu pm1 fsize=14,mode=popStart,pos={160,150},title="DAQ Range"
	PopupMenu pm1 proc=DAQRange,value="10;5;2;1"
	PopupMenu pm2 fsize=14,mode=1,pos={160,120},title="Display"
	PopupMenu pm2 proc=whichDisplay,value="default;low density;high density LR;high density UD;hexagonal;"

	Button b3,pos={200,420},size={80,20},proc=doneWithSetting,title="Show Fancy"
	Button b4,pos={200,440},size={80,20},proc=doneWithSetting,title="Show Simple"
	
	FIFOButtons()
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
	
	NVAR FIFOrange=$recDF+"FIFOrange"
	NVAR saveFile=$recDF+"saveFile"
	NVAR cInject=$recDF+"cInject"
	NVAR oAnalysis=$recDF+"oAnalysis"
	NVAR displayType=$recDF+"displayType"
	SVAR display_name = $recDF + "display_name"
	
	display_name = "RecordMEA"
	
	variable deviceOn
	deviceOn=getDeviceName()
	
	if(deviceOn==0)
		return 0
	endif
	
	wave whichChan=$recDF+"whichChan"
	
	if(numpnts(whichChan)!=numChans)
		displayType=0
	endif
	
	doWindow RecordMEA
	if(V_flag==1)
		killWindow RecordMEA
	endif
	
	SetDataFolder recDF
	
	variable i
	for(i=0;i<numChans;i+=1)
		killwaves /z $"wv"+num2str(i)
	endfor
	
	make /o/w/n=(blockSize) wv
	setscale /p x,0,delta,wv
	for(i=0;i<numpnts(whichChan);i+=1)
		duplicate /o wv $"wv"+num2str(i)
	endfor
	
	killwaves /z wv
	
	SetDataFolder root:
	
	display /N=RecordMEA ///k=2
	setwindow recordMEA, hook(hSelecteChannels)=GetSelectedChannel
	
	if (waveExists($OA_DF+"w_selected"))
		wave w_selected=$OA_DF+"w_selected"
		w_selected=0
	else
		make /o/n=(numChans) $OA_DF+"w_selected"=0
		wave w_selected=$OA_DF+"w_selected"
	endif
	
	makeDisplay(displayType)
	
	//modifygraph freepos={0,kwfraction}
	modifygraph  rgb=(0,0,0),nticks=2,ZisZ=1,btLen=1.5
	ModifyGraph tick=3,nticks=0,axRGB=(65535,65535,65535)
	ModifyGraph tlblRGB=(65535,65535,65535),alblRGB=(65535,65535,65535)
//	movewindow 2,2,2,2

	controlbar 30	
	button bstart, fcolor=(3,52428,1),pos={10,5},fsize=14,title="Start",proc=StartStopButton
	SetVariable setvar0,size={140,5},pos={70,5},title="Time (s)"
	SetVariable setvar0,fSize=14,value= $recDF+"totTime"
	PopupMenu pm1 fsize=14,mode=1,pos={550,5},title="Scale"
	PopupMenu pm1 proc=displayRange,value=doPopUpMenu()
	Slider s1, vert=0,value=length,pos={40,880},size={250,0},fsize=5
	variable numTicks=length/.25/2
	Slider s1 live=0,limits={.25,length,.25},proc=timeRescale,ticks=numTicks
	displayRange("pm1",1,"10")
	saveFileButtons(saveFile)
	cInjectButtons()
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
			// Changed by PJ on 2014/5/16 to incorporate 180 rotation between preamplifier and display
			make /o/n=(8,8) displayStructure
			displayStructure[0][0]= {0,27, 29, 32, 35, 38, 40,1}
			displayStructure[0][1]= {24, 25, 28, 33, 34, 39, 42, 43}
			displayStructure[0][2]= {22, 23, 26, 31, 36, 41, 44, 45}
			displayStructure[0][3]= {19, 20, 21, 30, 37, 46, 47, 48}
			displayStructure[0][4]= {18, 17, 16, 7, 60, 51, 50, 49}
			displayStructure[0][5]= {15,14, 11, 6, 61, 56, 53, 52}
			displayStructure[0][6]= {13, 12, 9, 4, 63, 58, 55, 54}
			displayStructure[0][7]= {2,10, 8, 5, 62, 59, 57,3}
//			displayStructure[0][0]= {0,57,59,62,5,8,10,1}
//			displayStructure[0][1]= {54,55,58,63,4,9,12,13}
//			displayStructure[0][2]= {52,53,56,61,6,11,14,15}
//			displayStructure[0][3]= {49,50,51,60,7,16,17,18}
//			displayStructure[0][4]= {48,47,46,37,30,21,20,19}
//			displayStructure[0][5]= {45,44,41,36,31,26,23,22}
//			displayStructure[0][6]= {43,42,39,34,33,28,25,24}
//			displayStructure[0][7]= {2,40,38,35,32,29,27,3}
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

function saveFileButtons(which)
	variable which
	
	if(which)
		checkbox cb1, mode=0,pos={220,5},fsize=14,value=1,title="Save File",proc=doSave
		SetVariable setvar1,size={180,5},pos={305,5},title="File Name"
		SetVariable setvar1,fSize=14,value= $recDF+"saveName"
		button b2, pos={490,5},fsize=14,title="Path",proc=changePath
	else
		checkbox cb1, mode=0,pos={220,5},fsize=14,title="Save File",proc=doSave
	endif
	
end

function cInjectButtons()

	NVAR cInject=$recDF+"cInject"
	SVAR cWave=$recDF+"cWave"
	

	PopupMenu pm3 fsize=14,mode=2,pos={720,5},title="cInject"
	PopupMenu pm3 proc=getCurWave,value=GetInjectList()

	// set popup menu to Start Immediately by default, have cInject and cWave be the corresponding values (see getInjectList() below)
	PopupMenu pm3 popMatch="S*"
	cInject=0
	cWave=""
	
end

Function /t getInjectList()
	string list="Start Immediately;"+"---;"+WaveList("*_cur",";","")
		
	return list
end

Function getCurWave(ctrlName,popNum,popStr) : PopupMenuControl
	String ctrlName
	Variable popNum
	String popStr
	
	NVAR cInject=$recDF+"cInject"
	SVAR cWave=$recDF+"cWave"
	
	if(popNum==1)
		cInject=0
		cWave=""
	elseif(popNum==2)
		cInject=1
		cWave=""
	else
		cInject=1
		cWave=popStr
	endif
end

function analyzeButtons()
	
	string list=FunctionList("*_OA",";","")
	
	if(ItemsInList(list,";")>1)
		PopupMenu pm2 fsize=14,mode=1,pos={1020,5},title=""
		PopupMenu pm2 proc=getOAfunc,value=GetOAlist()
		checkbox cb3, mode=0,pos={950,7},fsize=14,title="Analyze",proc=setAnalysis
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
	
	NVAR saveFile=$recDF+"saveFile"
	NVAR cInject=$recDF+"cInject"
	NVAR oAnalysis=$recDF+"oAnalysis"
	
	SVAR timeString=$recDF+"timeString"
	SVAR saveName=$recDF+"saveName"
	SVAR cWave=$recDF+"cWave"
	SVAR analysisFunction=$recDF+"analysisFunction"
	SVAR display_name = $recDF + "display_name"
	
	// PJ on 150317
	if  (stringmatch("RecordMEA", display_name))
		KillControl  pm3
	endif
	Button bStart fcolor=(65535,0,0),title="Stop",rename=bstop
	killControl  setvar0
	KillControl  setvar1
	KillControl  cb1
	KillControl  b2
	titlebox tb1 fsize=14,pos={100,5},variable=timeString
	//	
	if(saveFile)
		titlebox tb2, fsize=14,pos={300,5},frame=0,title="Saved to "+saveName
	else		// else added by PJ on 111913
		titlebox tb2, fsize=14,pos={300,5},frame=0,title="Saved to Default"
	endif
	
	if(cInject && stringMatch(cWave,"")==0)
		titlebox tb3, fsize=14,pos={700,5},frame=0,title="Injecting "+cWave
	endif
	
	Record()
	
End

Function doStop(early)
	variable early
	
	NVAR saveFile=$recDF+"saveFile"
	NVAR cInject=$recDF+"cInject"
	NVAR cnt=$recDF+"cnt"
	NVAR runningTime=$recDF+"runningTime"
	NVAR running=$recDF+"running"
	NVAR refnum=$recDF+"refnum"
	NVAR refnum=$recDF+"FIFO_refnum"
	
	SVAR timeString=$recDF+"timeString"
	SVAR FIFOname=$recDF+"FIFOname"
	SVAR NIDAQdevice=$recDF+"NIDAQdevice"
	SVAR display_name=$recDF+"display_name"
	SVAR saveName=$recDF+"saveName"

	variable i
	
	CtrlNamedBackground _all_,stop=1
	CtrlNamedBackground WriteToWave, kill
	
	if(cInject)
		fDAQmx_WaveformStop(NIDAQdevice)
		make /o/n=100 rezero
		setscale /p x,0,delta,rezero
		DAQmx_WaveformGen /DEV=NIDAQdevice /NPRD=1 "rezero,0;"
	endif
	
	fDAQmx_ScanStop(NIDAQdevice)
	CtrlFIFO $FIFOname,stop

	// killFIFO closes the file associated wtih it
	KillFIFO $FIFOname
		
	if(early)
		fixHeader()
	endif

	

	// modified by PJ on 111913.
	// close all files
	close /A

	cnt=0
	runningTime=0
	running=0
	timeString="Time: "
	
	doMiniStop()
	
	if (stringmatch("MEA_display", display_name))
		// convert files from FIFO to our own format only if SaveFlag is set. If Default flag, you are going to have to do this manually
		
		// get string to output path
		if (saveFile)
			pathinfo path1
			s_path = replacestring(":", s_path, "\\\\")
			s_path = replacestring("C\\\\", s_path, "C:\\\\")
			
			//TODO fix the path below
			string cmd = "cmd.exe /K \"C:\\Users\\Baccus^ Lab\\My^ Documents\\GitHub\\igor\\recording\\convert.bat " + s_path + " " + saveName+ "\""
			print cmd
			ExecuteScriptText cmd
		endif
		
		// (*) Kill MEA_Display and start it again. There is a bug in the way traces are display if we restart the recording
		//	without killing the display. I don't understand why this happens but killing and restarting bypasses the problem
		KillWindow MEA_display
		execute("MEA_display()")
	endif
End

Function doMiniStop()
	NVAR saveFile=$recDF+"saveFile"
	NVAR oAnalysis=$recDF+"oAnalysis"
	

	// PJ on 150317
	//KillControl tb3
	Button bStop fcolor=(3,52428,1),title="Start",rename=bStart
	KillControl tb1
	KillControl tb2
	SetVariable setvar0,size={140,5},pos={70,5},title="Time (s)"
	SetVariable setvar0,fSize=14,value= $recDF+"totTime"
	saveFileButtons(saveFile)
	cInjectButtons()
End

Function doSave(ctrlName,checked) : CheckBoxControl
	String ctrlName
	Variable checked
	
	NVAR saveFile=$recDF+"saveFile"
	
	if(Checked)
		saveFile=1
		saveFileButtons(saveFile)
	else
		saveFile=0
		KillControl setvar1
		KillControl b2
	endif
End

Function changePath(name)
	String name
	
	NewPath /q/o/M="Where would you like to save your files?" path1
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
			titlebox tb4, fsize=14,pos={1050,5},frame=0,title="running "+analysisFunction
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
			PopupMenu pm2, fsize=14,mode=1,pos={1020,5},title=""
			PopupMenu pm2 proc=getOAfunc,value=getOAlist()
			analysisFunction="---"
		endif
	endif
End

Function displayRange(ctrlName,popNum,popStr) : PopupMenuControl
	String ctrlName
	Variable popNum
	String popStr
	
	wave whichChan=$recDF+"whichChan"
	
	string axes=axisList("")
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

Function DAQRange(ctrlName,popNum,popStr) : PopupMenuControl
	String ctrlName
	Variable popNum
	String popStr
	
	NVAR FIFOrange=$recDF+"FIFOrange"
	
	switch(popNum)
		case 1:
			FIFOrange=10
			break
		case 2:
			FIFOrange=5	
			break
		case 3:
			FIFOrange=2
			break
		case 4:
			FIFOrange=1
			break
	endswitch
end

Function whichDisplay(ctrlName,popNum,popStr) : PopupMenuControl
	String ctrlName
	Variable popNum
	String popStr
	
	NVAR displayType=$recDF+"displayType"
	
	displayType=popNum-1
end

Function timeRescale(name, value, event) : SliderControl
	String name
	Variable value
	Variable event
	
	wave displayStructure=$recDF+"displayStructure"
	wave whichChan=$recDF+"whichChan"
	NVAR displayType=$recDF+"displayType"
	
	variable howMany
	
	if(displayType==0)
		howMany=ceil(numpnts(whichChan)/16)
	else
		howMany=dimsize(displayStructure,0)
	endif	
				
	variable i
	for(i=0;i<howMany;i+=1)
		SetAxis $"b"+num2str(i) 0,value
	endfor	
					
	return 0
End

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

function /S getDate()

	String expr="([[:alpha:]]+), ([[:alpha:]]+) ([[:digit:]]+), ([[:digit:]]+)"
	String dayOfWeek, monthName, dayNumStr, yearStr
	SplitString/E=(expr) date(), dayOfWeek, monthName, dayNumStr, yearStr
	
	string year=yearStr[2,3]
	
	variable month
	
	make/o/t/n=12 monthConvert
	monthConvert[0]="Jan"
	monthConvert[1]="Feb"
	monthConvert[2]="Mar"
	monthConvert[3]="Apr"
	monthConvert[4]="May"
	monthConvert[5]="Jun"
	monthConvert[6]="Jul"
	monthConvert[7]="Aug"
	monthConvert[8]="Sep"
	monthConvert[9]="Oct"
	monthConvert[10]="Nov"
	monthConvert[11]="Dec"
	
	string s1
	string monthStr
	variable i
	for(i=0;i<numpnts(monthConvert);i+=1)
		s1=monthConvert[i]
		if(StringMatch(monthName,s1))
			month=i+1
		endif
	endfor
	if(month<10)
		monthStr="0"+num2str(month)
	else
		monthStr=num2str(month)
	endif
	
	// Changed on 050614 by PJ, from now on, default date format is YYMMDD to be chronologically order
	string dateStr=year+monthStr+dayNumStr
	return dateStr
end

function whatIsTheRange()
	NVAR FIFOrange=$recDF+"FIFOrange"
	
	variable range
	switch(FIFOrange)
		case 10:
			range=1
			break
		case 5:
			range=2	
			break
		case 2:
			range=3
			break
		case 1:
			range=4
			break
	endswitch
	
	return range
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
			string axisL0range =  stringByKey("axisEnab(x)", axisinfo("", "l0"), "=")
			variable v1, v2
			sscanf axisL0range, "{%f, %f}", v1, v2
			variable axisDistance = v2-v1	// in window units. I need it in pixels
			getWindow kwTopWin wsize	// sets v_top, v_bottom
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
			
			// print s_trace, selectedCh
			if (w_selected[selectedCh])
				// Deselect item. Remove item from list and change color to balck
				w_selected[selectedCH] = 0
				modifygraph/z rgb($"wv"+num2str(selectedCH))=(0,0,0)
			else
				// Select item. Remove item from list and change color to red
				w_selected[selectedCH] = 1
				modifygraph/z rgb($"wv"+num2str(selectedCH))=(65535,0,0)
			endif
			
			AddChLabel("recordMEA", "wv", yPos = 1)
			AddChannelInfo(selectedCh)
	EndSwitch
end

function AddChLabel(gname, tracePrefix, [yPos])
	string gname, tracePrefix
	variable yPos
		
	wave w_selected = :OA:w_selected
	
	if (paramIsDefault(yPos))
		yPos = 1
	endif
	
	variable i
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

//			string s_axisEnab = listMatch(axisInfo(gname, leftAxis), "axisEnab*")
//			variable xVal, yVal, v0, v1
//			sscanf s_axisEnab, "axisEnab(x)={%g,%g}%*s", v0, v1
//			SetDrawEnv /w=$gname xcoord=$bottomAxis
//			DrawText /w=$gname 0, yPos*(v0-v1)+v0, num2str(i)

		endif
	endfor
	SetDrawEnv /w=$gname gstop
end

function /wave loadMapping()
	variable refnum		// this is a local one, will point to a file with electrode configuration
							// has nothing to do with output recording file
	
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
			
			print colRow, newColRow, ch, block, dist
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

// Added by PJ on 150317
Window MEA_display() : Panel
	// generate display, 
	//	Everything is embeded inside a panel, the panel has a controlbar with buttons and 4 charts.
	//	Each chart can accomodate traces vertically but not horizontally, that's why I have 4 (one per column)
	if (wintype("MEA_display"))
		killwindow MEA_display
	endif
	
	PauseUpdate; Silent 1		// building window...
	
	populate_mea(4, 6)		// Window can't take loops, that's why everything was shipped to a function

EndMacro

function populate_mea(columns, rows)
	variable columns, rows
	variable i, col
	string str_name

	SVAR FIFOname= $recDF+"FIFOname"
	SVAR display_name = $recDF + "display_name"
	
	display_name = "MEA_display"

	// (*) get the screen resolution and make a panel that uses the full screen
	string str_info = StringByKey("SCREEN1", IgorInfo(0))
	variable last_comma = strsearch(str_info, ",", inf, 1) 
	string str_height = str_info[last_comma+1,inf]
	string str_width = str_info[strsearch(str_info, ",", last_comma-1, 1)+1, last_comma-1]
	variable var_height = str2num(str_height)
	variable var_width = str2num(str_width)
	
	NewPanel /W=(0,0, var_width, var_height)/k=1
	button bstart , fcolor=(3,52428,1),pos={10,5},fsize=14,title="Start",proc=StartStopButton
	SetVariable setvar0,size={140,5},pos={70,5},title="Time (s)"
	SetVariable setvar0,fSize=14,value= $recDF+"totTime"
	saveFileButtons(0)
	FIFObuttons()
	//cInjectButtons()

	// (*) make as many charts as "columns" inside the pannel. Charts are one next to the other horizontally
	// spanning the full monitor width
	string str_chans
	for (col=0; col<columns; col+=1)
		// Create the chart (one chart per column)
		str_name = "chart"+num2str(col)
		Chart $str_name,pos={col*var_width/columns,50},size={var_width/columns-50, var_height-50},title=str_name,fSize=9, ppStrip=100
		switch (col)
			case 0:
				Chart $str_name, fifo=$FIFOname,chans= {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15}, umode=0
				break
			case 1:
				Chart $str_name, fifo=$FIFOname,chans= {16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31}, umode=0
				break
			case 2:
				Chart $str_name, fifo=$FIFOname,chans= {32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47}, umode=0
				break
			case 3:
				Chart $str_name, fifo=$FIFOname,chans= {48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63}, umode=0
				break
		endswitch				
		// offset traces on a given column vertically
		for (i=0; i<6; i+=1)
			Chart $str_name, lineMode(i)=1
		endfor
	endfor
end

function 	FIFObuttons()
	if (wintype("Settings"))	
		// handle to wave, generate if needed
		SVAR FIFOname = $recDF+"FIFOname"
		wave /SDFR=$recDF FIFOchan_params
		if (!waveExists(FIFOchan_params))
			make /n=(64,4) $recDF+"FIFOchan_params"
			wave /SDFR=$recDF FIFOchan_params
			setdimlabel 1, 0, gain, FIFOchan_params
			setdimlabel 1, 1, offset, FIFOchan_params
			setdimlabel 1, 2, minusFS, FIFOchan_params
			setdimlabel 1, 3, plusFS, FIFOchan_params
			
			// some default parameters
			FIFOchan_params[][%gain]=1
			FIFOchan_params[][%plusFS]=2500
		endif

		newPanel /ext=0/host=Settings/W=(0,0,160,230)/N=FIFO_settings
		titlebox titlebox1 title="set \"chan\" to:\r\t-1\tall channels\r\t0-63, one channel", fsize=16, fstyle=1
		setvariable fifo_chan, 		title="chan", 		value=_NUM:0, 						proc=setFIFO_chan_params, size={90,10}, pos = {35,80}
		setvariable fifo_gain, 		title="gain", 		value=FIFOchan_params[0][%gain], 	proc=setFIFO_chan_params, size={90,10}, pos = {35,110}
		setvariable fifo_offset, 		title="offset", 	value=FIFOchan_params[0][%offset], 	proc=setFIFO_chan_params, size={90,10}, pos = {35,140}
		setvariable fifo_minusFS, 	title="minusFS", 	value=FIFOchan_params[0][%minusFS],proc=setFIFO_chan_params, size={90,10}, pos = {35,170}
		setvariable fifo_plusFS, 	title="plusFS", 	value=FIFOchan_params[0][%plusFS], 	proc=setFIFO_chan_params, size={90,10}, pos = {35,200}
	endif
end

Function setFIFO_chan_params(SV_Struct) : SetVariableControl
	STRUCT WMSetVariableAction &SV_Struct

	wave /SDFR=$recDF FIFOchan_params

	// Grab values for all 5 needed variables from setvariable controls in display	
	controlinfo fifo_chan
	variable chan = v_value

	if (chan<0)
		controlinfo fifo_gain
		FIFOchan_params[][%gain] = v_value
	
		controlinfo fifo_offset
		FIFOchan_params[][%offset] = v_value
	
		controlinfo fifo_plusFS
		FIFOchan_params[][%plusFS] = v_value
	
		controlinfo fifo_minusFS
		FIFOchan_params[][%minusFS] = v_value
	else
		controlinfo fifo_gain
		FIFOchan_params[chan][%gain] = v_value
	
		controlinfo fifo_offset
		FIFOchan_params[chan][%offset] = v_value
	
		controlinfo fifo_plusFS
		FIFOchan_params[chan][%plusFS] = v_value
	
		controlinfo fifo_minusFS
		FIFOchan_params[chan][%minusFS] = v_value
	endif	
//	ctrlFIFO $FIFOname, stop
	
//	ctrlFIFO $FIFOname, 
End