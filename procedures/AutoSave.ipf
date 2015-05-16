#pragma rtGlobals=1		// Use modern global access method.
// autosave V1
// author: Junis Rindermann
// these functions are used for the auto save functionality
//
// description: put this code in a separate procedure file into the "Igor Procedures folder". It will then generate a Menu item under "Misc"
// where an autosave feature can be enabled. If enabled, the autosave background task saves a copy of the current experiment "frequencyDrift.pxp"
// under "_autosave_frequencyDrift.pxp" in the same folder, and subsequently overwrite this copy every 10 minutes. The background task can be
// disabled from the same menu. The user receives a warning if he disabled autosave, or deletes the root:Package:autosave datafolder. Autosave resumes
// when an experiment is opened where autosave was enabled the last time it was open. It is ON PURPOSE that the background task DOES NOT save the
// open experiment. In this way the user keeps the responsibility about his data.
 
//
// notes:
// the autosave interval is set to 10 min by default. by changing the global variable root:Packages:Autosave:saveintervalmin to another value (in minutes)
// this can be changed at any time
 
 
#pragma IndependentModule=Autosave
 
Function UpdateAutosaveMenu()
	NVAR AutoSaveON=root:Packages:AutoSave:AutoSaveON
//	SVAR menustr = root:Packages:AutoSave:AutosaveMenu
	if (AutoSaveON==1)
		String/G root:Packages:AutoSave:AutosaveMenu = "Turn auto save OFF"
	else
		String/G root:Packages:AutoSave:AutosaveMenu = "Turn auto save ON"	
	endif
	BuildMenu "Misc"
End
 
Function ToggleAutoSave()
	if (datafolderexists("root:Packages:AutoSave:"))  // it is set up
		NVAR AutoSaveON = root:Packages:AutoSave:Autosaveon
		NVAR saveIntervalMin = root:Packages:AutoSave:saveIntervalMin
		variable numTicks
		if (Autosaveon == 1)  // we switch it OFF
				CtrlNamedBackground AutosaveBgrTsk, stop
 
				Autosaveon = 0
				print "Auto save was turned OFF."
				AutoSaveWarning()
		else					// we switch if ON
 
				numTicks = 60 * 60 *    saveintervalmin  // every 10 minutes
				CtrlNamedBackground AutosaveBgrTsk, period = numticks, proc = SaveBackUpNow
				CtrlNamedBackground AutosaveBgrTsk, start
				Autosaveon = 1
				print "Auto save was turned ON. A copy of your experiment file is saved every 10 min under the name "+"_autosave_"+IgorInfo(1)+".pxp"
		endif
	else					//   it is not set up yet, we will set it up now
		if (datafolderexists("root:Packages")) 
			NewDatafolder/O root:Packages:AutoSave
		else
			NewDatafolder/O root:Packages
			NewDatafolder/O root:Packages:AutoSave
		endif
		Variable/G root:Packages:AutoSave:AutoSaveON=1
		Variable/G root:Packages:AutoSave:saveIntervalMin =  10
		NVAR saveintervalmin = root:Packages:AutoSave:saveIntervalMin
		UpdateAutosaveMenu()
		//saveexperiment
		numTicks = 60 * 60 *    saveintervalmin  // every saveintervalmin minutes
		CtrlNamedBackground AutosaveBgrTsk, period = numticks, proc = SaveBackUpNow
		CtrlNamedBackground AutosaveBgrTsk, start
//		String 
		print "Auto save was turned ON. A copy of your experiment file is saved every 10 min under the name "+"_autosave_"+IgorInfo(1)+".pxp"
		AutosaveON=1
 
	Endif
	UpdateAutosaveMenu()
	BuildMenu "Misc"
End
 
Menu "Misc"
	StrVarOrDefault("root:Packages:AutoSave:AutoSaveMenu","Initialize and start autosave"), /Q, ToggleAutoSave()
End
 
 
Function SaveBackUpNow(s)
	STRUCT WMBackgroundStruct &s
//	Printf "Task %s called, ticks=%d\r", s.name, s.curRunTicks
	if (exists("root:Packages:AutoSave:AutoSaveOn") == 2)
		// do nothing
		NVAR autosaveon = root:Packages:AutoSave:AutoSaveOn
		// if desired the date of the saved version can be added to the file name. this greatly increases the space wasted by the autosaved file copies.
		// use this only with great care!! and find a way to remove the oldest autosaved file copies.
		//string datestr = time()+" "+date()
		//datestr=replacestring(":", datestr, "-")
		//datestr=replacestring(",", datestr, "-")
		//datestr=replacestring(".", datestr, "-")
		String filename = "_autosave_"+IgorInfo(1)+".pxp"
 
		if (HomePathdefined() == 0)
			DoAlert/T="Igor asks you..." 0, "This experiment was NOT saved yet. It needs to be saved for AUTO SAVE to work."
		Endif
		SaveExperiment/C/P=home as filename
 
		if (HomePathdefined() == 0) // clicked cancel
			autosaveon = 0
			UpdateAutosaveMenu()
			BuildMenu "Misc"
			CtrlNamedBackground AutosaveBgrTsk, stop
			print "This experiment was NOT saved yet. AUTO SAVE cannot work."
			DoAlert/T="Detected Cancel:" 0, "The experiment was NOT saved. AUTO SAVE is OFF."
			return 0
		else
			PathInfo home
			print "A copy of the experiment file was automatically saved as "+S_path+filename+" on "+time()+" "+date()
		endif
 
	//	else
			// do nothing, wait until auto save is turned ON
	//	endif
	else // stops itself if package folders have been deleted 
		AutoSaveWarning()
	endif
	return 0	// Continue background task
End
 
Function HomePathdefined()
	variable HomePathDefined=0
	PathInfo home
	if (stringmatch(S_path, "")) // home path not defined
		HomePathDefined=0
	else
		HomePathDefined=1
	endif
	return HomePathDefined
End
 
Function AutoSaveWarning()
	DoAlert/T="Igor asks you..." 1, "It seems you want to turn OFF autosave. Do you want to CONTINUE AUTO SAVE??"
	if (v_flag == 1) // YES
		ToggleAutoSave()
	else // NO
		CtrlNamedBackground AutosaveBgrTsk, stop
	endif
End
 
 
//#pragma rtGlobals=1        // Use modern global access method.
//#pragma moduleName=startup    // traditional for static functions
//
Static Function AfterFileOpenHook(refNum, fileNameStr, pathNameStr, fileTypeStr, fileCreatorStr, fileKind )
	variable refnum
	string filenamestr,pathnamestr,filetypestr, filecreatorstr
	variable filekind
	if (filekind == 1 || filekind == 2)
		if (exists("root:Packages:AutoSave:AutoSaveOn") == 2)
			NVAR AutoSaveON = root:Packages:AutoSave:Autosaveon
			NVAR saveIntervalMin = root:Packages:AutoSave:saveIntervalMin
			variable numTicks
			if (Autosaveon == 1)  // we resume auto save
				numTicks = 60 * 60 *    saveintervalmin  // every 10 minutes
				CtrlNamedBackground AutosaveBgrTsk, period = numticks, proc = SaveBackUpNow
				CtrlNamedBackground AutosaveBgrTsk, start
				Print "Opened file "+igorinfo(1)+".pxp"+" with active auto save. Auto save is resumed."// Do Stuff
			endif
 
		else
			//print "Auto save is OFF."
		endif
	endif
End