#pragma rtGlobals=1	 // Use modern global access method.



//
//
//	 COMMENTS
//
//

//	All one has to do is:
//	 1) In Igor, go under "Windows" to "New->", where you select "Procedures" to make a new procdure window
//	 2) cut and past all this stuff into that new procdure window
//	 3) close the window, by selecting the upper left box and choosing "Hide"
//
//
//	NOTE:FIRST YOU MUST RUN MAKE_GLOBALS_FILE_TRANSFER (Steve 5/00)
//	At this point, the macros are all ready to go. Now you:
//	 1) go under "Macros" and select "LoadCellFile"
//
//	A dialog window will come up. You should select the following options:
//	 1) "Use the dialog to select the file name?" toggle to YES
//	 2) "Use the dialog to select the path name?" toggle to NO
//	 3) "Choose the naming suffix:" you should input some descriptive string
//
//	 Igor will name your waves with the following scheme for cell #1:
//	 name of spike time wave = "cell1" + suffix (MODIFIED (STEVE 5/00))
//	 name of record index wave = "c1" + suffix + "_recs"
//	 and so on, for cell #n ...
//	 The spike time wave is a list of all the spike times for the cell
//	 The record index wave is a pointer to the location in the spike time wave corresponding to the spike that begins each record
//
//	 4) "How do you want to measure spike times?" toggle to ABSOLUTE TIME IN EXPERIMENT
//	 5) "Choose the record list wave:" toggle INCLUDE ALL
//
//	 If you want to select some of the records, you must modify the wave "rec_include"
//	 It has a value of "1" if a given record is to be included, "0" otherwise
//
//	 6) "Choose the cell list wave:" toggle INCLUDE ALL
//
//	 If you want to select some fo the cells, you must modify the wave "cell_list"
//	 It is a list of cell numbers (they do not need to be consecutive or in numerical order)
//	 The list is ended by either a value of "0" or by the end of the wave
//
//





Menu "Macros"
"MakeGlobals_FileTransfer"
End

Menu "Load Data"
"LoadCellFile /-"
end


Macro MakeGlobals_FileTransfer ()

//
//	these are widely used string, that are included here for completeness
//
if ( exists("g_cell_str") != 2 )
String/G g_cell_str = "c"
endif
if ( exists("g_spks_str") != 2 )
String/G g_spks_str = ""
endif
if ( exists("g_recs_str") != 2 )
String/G g_recs_str = "_recs"
endif
if ( exists("g_folder_str") != 2 )
String /G g_folder_str = "root:"
endif
String/G g1_suffix1

//
//	for 'LoadCellFile'
//
Variable/G g_wrap_option
String/G g_file_name , g_path_cells, g_suffix , g_rec_include , g_cell_list

//
//	for 'LoadFilms'
//
Variable/G g_cell_num
String/G g_base_name , g_path_films , g_film_suffix , g_film_str , g_list_wv
EndMacro


Macro MakeWaves_LoadCellFile ()

String wave_name
wave_name = "header_txt_cellfile"
if ( !WaveExists($wave_name) )
Make/T/N=11 $wave_name = {"Format" , "FileIndex" , "BoxIndex" , "RecIndex" , "StatIndex" , "NFiles" , "NBoxes" , "NRecords" , "NCells" , "NEvents" , "NSpikes"}
endif
wave_name = "header_info_cellfile"
if ( !WaveExists($wave_name) )
Make/N=11 $wave_name
endif
DoWindow/F Cell_Header_Info
if ( V_Flag == 0 )
Cell_Header_Info ()
endif
wave_name = "RecordIndex"
if ( !WaveExists($wave_name) )
Make $wave_name
endif
wave_name = "StartClock"
if ( !WaveExists($wave_name) )
Make $wave_name
endif
wave_name = "EndClock"
if ( !WaveExists($wave_name) )
Make $wave_name
endif
wave_name = "ShiftTime"
if ( !WaveExists($wave_name) )
Make $wave_name
endif
wave_name = "EventsInRecord"
if ( !WaveExists($wave_name) )
Make $wave_name
endif
wave_name = "SpikesInRecord"
if ( !WaveExists($wave_name) )
Make $wave_name
endif
DoWindow/F Cell_Record_Info
if ( V_Flag == 0 )
Cell_Record_Info ()
endif
wave_name = "rec_include"
if ( !WaveExists($wave_name) )
Make $wave_name
endif
wave_name = "cell_list"
if ( !WaveExists($wave_name) )
Make $wave_name
endif
EndMacro


Macro MakeWaves_LoadFilmFile ()

String wave_name
wave_name = "header_txt_filmfile"
if ( !WaveExists($wave_name) )
Make/T/N=24 $wave_name
$wave_name[0] = "Format"
$wave_name[1] = "TriggerOffset"
$wave_name[2] = "TriggerSize"
$wave_name[3] = "StimulusOffset"
$wave_name[4] = "StimulusSize"
$wave_name[5] = "HistoryOffset"
$wave_name[6] = "HistorySize"
$wave_name[7] = "ParameterOffset"
$wave_name[8] = "ParameterSize"
$wave_name[9] = "FilmOffset"
$wave_name[10] = "FilmSize"
$wave_name[11] = "NeventSpikes"
$wave_name[12] = "StimLowTime"
$wave_name[13] = "StimHighTime"
$wave_name[14] = "StimBinTime"
$wave_name[15] = "StixelWidth"
$wave_name[16] = "StixelHeight"
$wave_name[17] = "FieldWidth"
$wave_name[18] = "FieldHeight"
$wave_name[19] = "NRegions"
$wave_name[20] = "NBins"
$wave_name[21] = "Nguns"
$wave_name[22] = "GunOffset[0]"
$wave_name[23] = "GunScale[0]"
endif
wave_name = "header_info_filmfile"
if ( !WaveExists($wave_name) )
Make/N=24 $wave_name
endif
DoWindow/F Header_Film_File
if ( V_Flag == 0 )
Header_Film_File ()
endif
wave_name = "rec_include"
if ( !WaveExists($wave_name) )
Make $wave_name
endif
wave_name = "cell_list"
if ( !WaveExists($wave_name) )
Make $wave_name
endif
EndMacro



Macro LoadCellFile (file_name , path_name , newfile_option , newpath_option , suffix , wrap_option , record_include_wv , cell_list_wv)
String file_name = g_file_name , path_name = g_path_cells , suffix = g_suffix
String record_include_wv = g_rec_include , cell_list_wv = g_cell_list
Variable wrap_option = g_wrap_option , newfile_option = 1 , newpath_option = 2
Prompt file_name, "Choose the cell file name:"
Prompt path_name, "Choose the path name:"
Prompt newfile_option, "Use the dialog to select the file name?" , popup , "yes;no"
Prompt newpath_option, "Use the dialog to select the path name?" , popup , "yes;no"
Prompt suffix, "Choose the naming suffix:"
Prompt wrap_option, "How do you want to measure spike times?" , popup , "absolute time in experiment;relative to beginning of record"
Prompt record_include_wv, "Choose the record list wave:" , popup , "include all;" + Wavelist("*rec*inc*" , ";" , "")
Prompt cell_list_wv, "Choose the cell list wave:" , popup , "include all;" + Wavelist("*list*" , ";" , "")
PauseUpdate ; Silent 1
g_file_name = file_name ; g_path_cells = path_name ; g_suffix = suffix ; g1_suffix1 = suffix
g_rec_include = record_include_wv ; g_cell_list = cell_list_wv
g_wrap_option = wrap_option
Variable time_elapsed
Variable Format , FileIndex , BoxIndex , RecIndex , StatIndex
Variable NFiles , NBoxes , NRecords , NCells , NEvents , NSpikes
String file_designator
Variable file_refnum , old_colon , new_colon

//	This creates necessary waves and global variables, if they do not already exist

MakeGlobals_FileTransfer ()
MakeWaves_LoadCellFile ()
//	Use the dialog to select the path name, if necessary

if ( ((newpath_option == 1) + (strlen(g_path_cells) == 0)) * (old_colon == 0) )

NewPath/Q/O/M="Select the folder for the cell file(s)" CellFile_Folder

PathInfo CellFile_Folder
Print "The path now is " , S_Path
g_path_cells = S_Path
path_name = S_Path
else
NewPath/Q/O CellFile_Folder g_path_cells
endif

//	This checks if the file exists. If not, it calls a dialog

PathInfo CellFile_Folder
if ( !V_Flag )
NewPath/Q/C/Z CellFile_Folder ""
endif
Open/Z/R/T="celsTEXT"/P=CellFile_Folder file_refnum file_name
print V_Flag
if ( (V_Flag == 0) + (newfile_option == 1) )
//	if ( (V_Flag == -1) + (newfile_option == 1) )
Open/D/R/T="celsTEXT"/P=CellFile_Folder/M="Choose a valid cell file" file_refnum
old_colon = 0
do
new_colon = strsearch(S_fileName , ":" , old_colon)
if ( new_colon == -1 )
break
else
old_colon = new_colon + 1
endif
while (1)
file_name = S_fileName[old_colon , strlen(S_fileName)-1]
g_file_name = file_name
path_name = S_fileName[0 , old_colon-1]
g_path_cells = path_name
else
Close file_refnum
endif
file_designator = path_name + file_name
// replace here
time_elapsed = ticks


//	load the pointers first; there are 5 long int's

Print "Loading header information from cell file" , file_name
Print "	The folder is" , path_name
GBLoadWave/Q/O/N=temp_load/T={32,2}/S=0/W=1/U=5 file_designator
Format = temp_load0[0]
FileIndex = temp_load0[1]
BoxIndex = temp_load0[2]
RecIndex = temp_load0[3]
StatIndex = temp_load0[4]
if ( WaveExists(header_info_cellfile) )
header_info_cellfile[0,4] = temp_load0[p]
endif
if (( Format != 2 ) %& (Format !=3))
Abort "This file format is not supported!!!"
endif
//	load some number variables; there are 4 int's and 2 long int's

GBLoadWave/Q/O/N=temp_load/T={16,2}/S=64/W=1/U=4 file_designator
NFiles = temp_load0[0]
NBoxes = temp_load0[1]
NRecords = temp_load0[2]
NCells = temp_load0[3]
if ( WaveExists(header_info_cellfile) )
header_info_cellfile[5,8] = temp_load0[p-5]
endif
GBLoadWave/Q/O/N=temp_load/T={32,2}/S=72/W=1/U=2 file_designator
NEvents = temp_load0[0]
NSpikes = temp_load0[1]
if ( WaveExists(header_info_cellfile) )
header_info_cellfile[9,10] = temp_load0[p-9]
endif
//	now use the previous information to load the pointers to each record

Make/O/I/N=(NRecords) RecordIndex
GBLoadWave/Q/O/N=temp_load/T={32,2}/S=(RecIndex)/W=1/U=(NRecords) file_designator
RecordIndex = temp_load0
//	Set up waves to chose which records and cells to include (if not all)

Variable cell_index , list_continue

if ( cmpstr(record_include_wv , "include all") == 0 )
Make/O/N=(NRecords) temp_rec_include = 1
else
Duplicate/O $record_include_wv temp_rec_include
endif
if ( cmpstr(cell_list_wv , "include all") == 0 )
Make/O/N=(NCells+1) temp_cell_include = 1
else
Make/O/N=(NCells+1) temp_cell_include = 0
temp_cell_include[1] = 1
cell_index = 0
do
temp_cell_include[$cell_list_wv[cell_index]] = 1
cell_index += 1
list_continue = (cell_index < numpnts($cell_list_wv)) * ($cell_list_wv[cell_index] != 0)
while ( list_continue )
endif

//	load all of the spike data in one fell swoop into a mega-wave of long's
//	then loop through the records to assign appropriate waves

Print "Loading all of the spike data"
Variable skip_bytes , num_long_integers
skip_bytes = RecordIndex[0]
num_long_integers = (StatIndex - RecordIndex[0]) / 4
Redimension/I/N=(num_long_integers) temp_load0
GBLoadWave/Q/O/N=temp_load/T={96,96}/S=(skip_bytes)/W=1/U=(num_long_integers) file_designator


//
//	Finally, loop over all the cells and make the appropriate '_spks' and '_recs' waves
//

Variable wrapTime = 128 * (16^4) , rec_index , total_records , total_cells
String spks_wv , recs_wv
rec_index = 0
do
if ( temp_rec_include[rec_index] )
total_records += 1
endif
rec_index += 1
while ( rec_index < NRecords )
cell_index = 0
do
if ( temp_cell_include[cell_index] )
total_cells += 1
endif
cell_index += 1
while ( cell_index < NCells )

Print "Getting spike times for" , total_cells, "cells over" , total_records , "records"
cell_index = 1
do
if ( temp_cell_include[cell_index] )
spks_wv = g_cell_str+ num2str(cell_index) + suffix + g_spks_str
recs_wv = g_cell_str + num2str(cell_index) + suffix + g_recs_str
Make/O/N=(0) $spks_wv
Make/O/N=(total_records+1) $recs_wv = 0
endif
cell_index += 1
while ( cell_index <= NCells )
GetSpikes (temp_load0 , RecordIndex , NRecords , NCells , wrap_option , wrapTime , temp_rec_include , temp_cell_include , suffix)
cell_index = 1
do
if ( temp_cell_include[cell_index] )
spks_wv =g_cell_str + num2str(cell_index) + suffix + g_spks_str
recs_wv = g_cell_str + num2str(cell_index) + suffix + g_recs_str
if ( numpnts($spks_wv) == 0 )
$recs_wv = 0
else
$spks_wv *= 5e-5
movewave $spks_wv,$g_folder_str
endif
endif
cell_index += 1
while ( cell_index <= NCells )
KillWaves/Z temp_load0 , temp_rec_include , temp_cell_include
time_elapsed = ticks - time_elapsed
Print "Cell file" , file_name , "was loaded in" , round((time_elapsed / 60) * 100) / 100 , "sec"

EndMacro



Function GetSpikes (data_wv , RecordIndex , NRecords , NCells , wrap_option , wrapTime , rec_include_wv , cell_include_wv , suffix)
Wave data_wv , RecordIndex , rec_include_wv , cell_include_wv
Variable NRecords , NCells , wrap_option , wrapTime
String suffix
SVAR g_cell_str = g_cell_str
SVAR g_spks_str = g_spks_str
SVAR g_recs_str = g_recs_str
SVAR g_folder_str = g_folder_str

Variable rec_index , data_location , shift , first_spike , last_spike , cell_index , rec_count , num_spikes , endTime = 0
String spks_name , recs_name

Make/O/I/N=(NRecords) StartClock = 0 , EndClock = 0 , ShiftTime = 0
Make/O/I/N=(NRecords) EventsInRecord = 0 , SpikesInRecord = 0
Make/O/I/N=(NRecords , NCells) N = 0

rec_index = 0
do
//	 get the starting and ending clock values for this record; store in waves
//	 the trick here is that StartClock and EndClock are both /U/W rather than /U/I,
//	 so one single /I value must be decomposed into the upper 2 bytes (for StartClock) and lower 2 bytes (for EndClock)

data_location = (RecordIndex[rec_index] - RecordIndex[0]) / 4
if ( (data_location - trunc(data_location)) != 0 )
Print "Problem in indexing record #" , rec_index
endif
StartClock[rec_index] = trunc (data_wv[data_location] / 65536) * 128
EndClock[rec_index] = mod (data_wv[data_location] , 65536) * 128
//	 get the number of event and spikes in this record; store in waves
data_location += 1
EventsInRecord[rec_index] = data_wv[data_location]
SpikesInRecord[rec_index] = data_wv[data_location+1]
//	 get the number of spikes in each cell in this record

data_location += 2
N[rec_index][] = data_wv[data_location+q]
//	 Finally, load all the spike times

if ( rec_include_wv[rec_index] )
data_location += (NCells + 2 * EventsInRecord[rec_index])
cell_index = 1
do
num_spikes = N [rec_index][cell_index-1]
if ( cell_include_wv[cell_index] )
spks_name = g_cell_str + num2str(cell_index) + suffix + g_spks_str
recs_name = g_cell_str + num2str(cell_index) + suffix + g_recs_str
Wave spks_wv = $spks_name
Wave recs_wv = $recs_name
recs_wv[rec_count+1] = recs_wv[rec_count] + num_spikes
if ( num_spikes )
Redimension/N=(recs_wv[rec_count+1]) spks_wv
first_spike = recs_wv[rec_count]
last_spike = recs_wv[rec_count+1]-1
spks_wv[ first_spike , last_spike ] = data_wv[p + data_location - first_spike] + ShiftTime[rec_index]
if ( wrap_option == 2 )
spks_wv[ first_spike , last_spike ] -= StartClock[rec_index]
endif
endif
endif
data_location += num_spikes
cell_index += 1
while ( cell_index <= NCells )
rec_count += 1
endif

//	 this section corrects for the wrap-around
shift = trunc(endTime / wrapTime) * wrapTime
if (StartClock [rec_index] + shift < endTime)
shift += wrapTime
endif

//	 Set the ending time of the record to be the last recorded spike
first_spike = (RecordIndex[rec_index] - RecordIndex[0]) / 4 + 3 + NCells + 2 * EventsInRecord[rec_index]
last_spike = first_spike + SpikesInRecord[rec_index] - 1
if ( wrap_option == 1 )
StartClock[rec_index] += shift
ShiftTime[rec_index] = shift
endif
Wavestats/Q/R=[first_spike , last_spike] data_wv
endTime = V_max + shift

//	 Update 'EndClock' to fix the wrap-around of the clock
if ( wrap_option == 1 )
EndClock[rec_index] += trunc(endTime / wrapTime) * wrapTime
if ( EndClock[rec_index] < endTime )
EndClock[rec_index] += wrapTime
endif
endif
rec_index += 1
while ( rec_index < NRecords )
return (rec_count)
End
Window Cell_Header_Info() : Table
PauseUpdate; Silent 1	 // building window...
Edit/W=(5,42,364,303) header_txt_cellfile,header_info_cellfile as "Cell Header Info"
ModifyTable size(header_txt_cellfile)=9,alignment(header_txt_cellfile)=1,width(header_txt_cellfile)=132
ModifyTable size(header_info_cellfile)=9,alignment(header_info_cellfile)=1,width(header_info_cellfile)=112
EndMacro
Window Cell_Record_Info() : Table
PauseUpdate; Silent 1	 // building window...
Edit/W=(5,42,613,207) RecordIndex,StartClock,EndClock,ShiftTime,EventsInRecord,SpikesInRecord as "Cell Record Info"
ModifyTable size(RecordIndex)=9,alignment(RecordIndex)=1,sigDigits(RecordIndex)=9
ModifyTable size(StartClock)=9,alignment(StartClock)=1,sigDigits(StartClock)=9,size(EndClock)=9
ModifyTable alignment(EndClock)=1,sigDigits(EndClock)=9,size(ShiftTime)=9,alignment(ShiftTime)=1
ModifyTable sigDigits(ShiftTime)=9,size(EventsInRecord)=9,alignment(EventsInRecord)=1
ModifyTable sigDigits(EventsInRecord)=9,size(SpikesInRecord)=9,alignment(SpikesInRecord)=1
ModifyTable sigDigits(SpikesInRecord)=9
EndMacro
