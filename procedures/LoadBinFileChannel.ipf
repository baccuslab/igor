#pragma rtGlobals=1		// Use modern global access method.

function getChannel(chan,length, [refnum])
	variable chan,length, refnum

	if (paramisdefault(refnum))
		open /R/F=".bin" refnum
	else
		FStatus refnum
		if (v_Flag==0)
			Abort "getChannel got a non valid refnum to a file"
		endif
	endif
	
	readHeader(refnum)
	wave /t header
	variable headerSize=str2num(header[0][1])
	variable nscans=str2Num(header[3][1])
	variable numChans=str2Num(header[4][1])
	variable blockSize=str2num(header[6][1])
	variable scanRate=str2num(header[5][1])
	variable blockTime=blockSize/scanRate
	variable numBlocks=ceil(length/blockTime)
	variable totTime=nscans/scanRate
	numBlocks=min(ceil(totTime/blockTime),numBlocks)
	
	variable scaleMult=str2num(header[7][1])
	variable scaleOff=str2num(header[8][1])
	
	make /o/n=0 output
	make /o/n=(blockSize) block
	
	variable i
	for(i=0;i<numBlocks;i+=1)
		FsetPos refnum,0
		FsetPos refnum,headerSize+i*blockSize*numChans*2+chan*blockSIze*2
		FBinRead /b=2 /f=2 refnum,block
		concatenate /NP=0 "block;",output
	endfor
	
	setScale /p x,0,1/scanRate,output
	
	output+=scaleOff
	output*=scaleMult
	
	if (paramisdefault(refnum))
		close refnum
	endif
end

function readHeader(refnum)
	variable refnum
	
	variable headerSize,type,version,nscans,numberOfChannels
	variable scanRate,blockSize,scaleMult,scaleOff,dateSize,timeSize,userSize
	String dateStr="",timeStr="",userStr=""

	// Position yourself at the start of the file	
	FStatus refnum
	variable oldFilePos = v_filePos
	FSetPos refnum, 0
	
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
	
	FsetPos refnum, oldFilePos
end

function writeHeader(refnum)
	variable refnum
	wave /T header
	
	variable headerSize=200		// dummy number with 3 digits
	variable nscans=str2num(header[3][1])
	variable type=2
	variable version=1
	variable numberOfChannels=str2num(header[4][1])
	variable scanRate=str2num(header[5][1])
	variable blockSize=str2num(header[6][1])
	variable scaleMult= str2num(header[7][1])
	variable scaleOff=str2num(header[8][1])
	String dateStr=header[9][1]
	variable dateSize=strlen(header[9][1])
	String timeStr=header[10][1]
	variable timeSize=strlen(timeStr)
	String userStr="Not in use"				// "David"
	variable userSize=strlen(userStr)		// "david"
	wave whichChan

	fSetPos refnum,0
	FBinWrite /b=2 /f=3 /u refnum,headerSize
	FBinWrite /b=2 /f=2 refnum,type
	FBinWrite /b=2 /f=2 refnum,version
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

	// (*) write the correct header size, but first figure out how long it is
	FStatus refnum
	headerSize = V_filePos
	FsetPos refnum, 0		// write the correct headerSize at position 0
	FBinWrite /b=2/f=3/u refnum, headerSize
	FsetPos refnum, v_filePos	// go back to the end of the file
end


function splitBinFile(startT, endT)
	//this just generates one file with all data in between startT, endT
	//		NOTE, for simplicity startT and endT get rounded when converting to blocks
	//		output file will have the whole block that contains startT and endT
	variable startT, endT

	variable fileIn		
	open /D/R/F=".bin" fileIn		// sets s_fileName
	open /R fileIn as s_fileName
	
	FStatus fileIn
	if (V_flag==0)
		abort "File not open"
	endif
	readHeader(fileIn)

	// (*) some info from input file
	wave /t header
	variable numChans=str2Num(header[4][1])
	variable blockSize=str2num(header[6][1])
	variable scanRate=str2num(header[5][1])
	variable blockTime=blockSize/scanRate  //2 sec

	make /o/n=(blockSize) block
	
	// (*) open a file to store the data. 
	variable fileOut
	open /D fileOut
	open fileOut as s_fileName+".bin"
	FStatus fileOut			// sets several variables
	if (V_flag==0)
		abort "splitBinFile could not open the output file"
	endif
	
	// (*) Modify header before writing it.
	//	Only two parameters from header have to be modified, namely headerSize (will be changed automatically when we write it) and nscans
	variable startBlock = floor(startT/blockTime)
	variable endBlock = ceil(endT/blockTime)
	header[3][1] = num2str((endBlock-startBlock+1)*blockSize)
	writeHeader(fileOut)
	
	// (*) start writing data from channels
	FStatus fileOut			// sets several variables, including filePos
	variable headerSize = str2num(header[0][1])
	FsetPos fileOut,headerSize
	
	variable chan,nblock
	for(nblock=startBlock;nblock<=endBlock; nblock+=1)
		for(chan=0;chan<64;chan+=1)
			FsetPos fileIn,headerSize+blockSize*numChans*2+chan*blockSIze*2
			FBinRead /b=2 /f=2 fileIn,block

			FBinWrite /B=2/F=2  fileOut, block
		endfor
	endfor
	
	close /A

end
	