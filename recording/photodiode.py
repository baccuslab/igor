import binary
import numpy as np
import re
from os import listdir
import subprocess
import pdb

class PD(object):
    def __init__(self, regex_string):
        '''
        Load the photodiode for all bin files that match the given regular expression 
        'regex_string'
        '''
        
        regex = re.compile(regex_string)

        # make a list with all binFiles in current folder
        self.binFiles = [f for f in listdir('.') if regex.match(f)]

        """
        # init the PD to be an empty numpy array
        self.raw=np.array([])

        # keep track of total experimental time
        self.totalT = 0
        
        # loop through the files and exctract the photodiode for each one of them
        for binFile in self.binFiles:
            print('working on file', binFile)

            # create the MEA object for current binFile
            rec = meaRecording.MEA(binFile)
            # extract pd from binBile
            self.raw = np.concatenate((self.raw, rec.getChannel(0, rec.nscans/rec.scanRate)), axis=0) 
            # update totalT
            self.totalT += rec.nscans/rec.scanRate
        """

        # extract some variables that are general and don't depend on the particular bin file
        self.header = binary.readbinhdr(self.binFiles[0])
        self.regex = regex

    def analysePD(self, stimDeltaT, whiteThresholdFactor=.8):
        '''
        Load and analyse the photodiode associated with all files that match wildcard in current folder
        
        Parameters:
        -----------
        stimDeltaT:             amount of time in between stimuli to force a change in white frame periods, Typically 0.2s
        whiteThresholdFactor:     a number between 0 and 1, although the code is not checking for it and code will not crash with numbers outside this range.
                                white frames are defined as any crossing of threshold where threshold is whiteTrheshold*maxValueInRecording

        Output:
        -------
        startT:            numpy array with times where a stimulus started
        endT:            numpy array with times where a stimulus ended
        period:            distance in between white frames for a given stimulus
        frameperiod:     float with average distance between monitor flips
        '''

        self.__DetectWhiteFrames__(whiteThresholdFactor)
        print('Finished detecting white frames')
        print('Looking for startT and endT')
        self.__GetStartTEndT__(stimDeltaT)
        print('Finished with startT and endT')
        print('Looking for period')
        self.__GetPeriod__()
        print('Finished with period')
        print('Looking for frameperiod')
        self.GetScansPerFrame()
        #self.frameperiod=0
        print('Finished with frameperiod')
        print('done with everything')
        return self.startT, self.endT, self.period, self.waitframes, self.frameperiod

    def get_monitor_framerate(self):
        '''
        compute the monitor's framerate from a PD recording.
        
        Output:
        -------
            self.framerate:      average monitor flips per second
        
        '''
        import scipy
        import scipy.fftpack
        import sys

        # load the photodiode, 100s is enough
        length = 100    # in seconds
        pd = binary.readbin(self.binFiles[0], [0]).flatten()
        pd = pd[:length * self.header['fs']]     # header['fs'] is the sampling rate (samples per second)

        # FFT the signal
        pdFFT = scipy.fftpack.rfft(pd)
        pdFreqs = scipy.fftpack.rfftfreq(pd.size, 1./self.header['fs'])
        
        # get the freq with max FFT power
        self.monitor_framerate = pdFreqs[pdFFT.argmax()]

        '''
        # I only want the maximum location of pdFFT in between 'left' and 'right'
        subarray = pdFFT[left:right]

        fftmaxarg = subarray.argmax()
        freq = pdFreqs[left+fftmaxarg]

        self.monitorRate=freq
        self.frameperiod = 1/freq
        self.scansPerFrame = self.frameperiod*self.scanRate
        raise ValueError('debugging')
        self.frameperiod = round(self.period/self.monitorNominalRate)
        '''

    def get_stim_waitframes(self):
        '''
        compute the number of monitor frames a given stimulus is shown for
        from a PD recording.
        
        Output:
        -------
            self.:      average monitor flips per second
        
        '''

        # 100 seconds should be good enough
        length = 100        # in seconds
        pd = binary.readbin(self.binFiles[0], [0]).flatten()
        pd = pd[:length * self.header['fs']]

        # I will downsample pd since 
        # pd is measured at header['fs'] but I care about framerate
        #   first make it 2d with dim 1 being number of recorded samples per frame
        #   then average dim 1
        pd = pd.reshape(-1, int(self.header['fs'] / self.monitor_framerate))
        pd = pd.mean(axis=1)

        # now compute circular correlation
        circCorr = np.correlate(pd, np.hstack((pd[1:], pd)), mode='valid')  

        # circCorr should ahve the maximum at 0 and then decreases with each point
        # at the point corresonding to waitframes the signal should be almost at the
        # minimum. This is the number I want to extract. I'm going to compute where 
        # should the mean be inserted to keep the sorting at the beginning of the array
        # Since searchsorted works for arrays sorted only in ascending order I fist
        # multiply by -1 to make (the first points) sorted in that way.
        circCorr *= -1

        self.stim_waitframes = circCorr.searchsorted(circCorr.mean())

    def __DetectWhiteFrames__(self, whiteThresholdFactor):
        '''
        Extract all scans for which white frames are detected.
        A detection means that "whiteThresholdFactor"*v_max has been crossed, where v_max is the maximum value in self.raw
        self.raw is the photodiode raw recording

        Parameters:
        -----------
        whiteThresholdFactor:    a number between 0 and 1, although the code is not checking for it and any number will work
        
        Output:
        -------
        whiteFrameScans:     ndarray with the scans corresponding to the white frames
        scansperframe:         estimated number of scans per frame
        scanRate:            from the file's header, how many samples per second are we recording.
        '''
        
        # init the ndarray to hold all white frames detected across all files.
        allWhiteScans = np.array([])
        accumulatedScans = 0
        
        # detect the maximum value in pd_array
        pd_max = np.max(self.raw)
                
        # define threshold that has to be crossed to define a white pd.
        whiteThreshold = pd_max*whiteThresholdFactor
                
        # detect crossings of threshold
        # all crossings are detected, if stimulus is updating every n frames, each white frame will be detected n times
        initialList = [i for i in range(1, len(self.raw)) if self.raw[i]>whiteThreshold and self.raw[i-1]<whiteThreshold] 

        self.__DetectWaitframes__(initialList)

        # start a list of whiteFrames, make it float
        whiteFrames=[initialList[0]*1.0]
        for nextScan in initialList:
            if nextScan-whiteFrames[-1]>(self.waitframes + .5) * self.monitorNominalRate:
                whiteFrames.append(nextScan*1.0)

        # convert whiteFrames to array, make it an attribute, and change it from scans to seconds    
        self.whiteFrames = np.array(whiteFrames)
        self.whiteFrames /= self.scanRate

    def __DetectWaitframes__(self, whiteFrames):
        '''
        From all white frames detected, figure out how often is the monitor updated.
        Compute a distance between consecutive white frames. If each frame is presented N times then there should be N-1
        gaps between white frames of almost equal length
        '''
        distance = whiteFrames[1]-whiteFrames[0]
        self.waitframes = 2.0
        for i in range(2, len(whiteFrames)):
            if whiteFrames[i]-whiteFrames[i-1] < distance/2:
                self.waitframes+=1
            else:
                return

    def __GetStartTEndT__(self, stimDeltaT):
        '''
        From all detected white frames identify which ones correspond to a stimulus start, stimulus ends or skipped frames.
        '''
        # initialize both startT, endT
        self.startT=[self.whiteFrames[0]]
        self.endT=[]

        # when there is a change in whiteFrames distance it can be due to skipping frames, normal termination of stimulus or premature termination of stimulus. After a normal termination of stimulus, there is a delay without any white frames signaling the end of the stimulus (the last period in the stimulus is just a little longer than all the others. But what follows is almost certainly also different, so a normal termination of the stimulus has 2 consecutive whiteframe distance changes. Since the logic becomes somewhat complex I'm defining a variable to keep track of normal stimulus termination and simplify logic
        regularStimulusEnd=0
        
        # loop through every white frame, and figure out if the distance to the previous one has changed. The formula is: d1 - d2 = (w[i]-w[i-1]) - (w[i-1]-w(i-2))
        for i in range(2, len(self.whiteFrames)):
            if regularStimulusEnd:
                # it doesn't matter what the distance is because this is the 1st computed distance after a regular switch between stimulus
                #print('reseting flag')
                regularStimulusEnd=0
                continue
            
            # compute the difference between the current whiteframe distance and the previous one
            delta = self.whiteFrames[i]+self.whiteFrames[i-2]-2*self.whiteFrames[i-1]     # this is a difference of differences, distance[i] - distance[i-1]
                                                # == 0 means no difference in period
                                                # == stimDeltaT probably means normal switch between experiments
                                                # Any other difference could be due to a recent switch in experiment or skipping frames
            
            # now compare delta with a single monitor frame period (actually half) to decide whether the two white frame distances are the same or not
            if delta < 1./self.monitorNominalRate/2:
                # regular distance between white frames whithin a stimulus, do nothing
                continue
            elif delta - stimDeltaT < 1.0/self.monitorNominalRate/2:
                # the distance between white frames increased by almost exactly stimDeltaT, this is a regular stimulus end and a new one has just started.
                self.startT.append(self.whiteFrames[i])
                self.endT.append(2*self.whiteFrames[i-1]-self.whiteFrames[i-2])    # it finished one period after self.whiteFrames[i-1]
                regularStimulusEnd=1
            else:
                # this is a strange case, either a frame was dropped, I quit the stimulus before it was done or I forgot to add a delay in between different stimuli
                # skipping a frame
                self.startT.append(self.whiteFrames[i])
                self.endT.append(self.whiteFrames[i])

            # if it executes this is because it detected a change in PD period. We are starting a new stimulus

        # append last endT
        lastEndT = min(self.totalT, 2*self.whiteFrames[-1]-self.whiteFrames[-2])
        self.endT.append(lastEndT)
    
    def __GetPeriod__(self):
        '''
        For each startT/endT pair, compute the average time in between whiteframes

        '''


        # init output list
        self.period=[]

        for i in range(len(self.startT)):
            # what are the indices of the current startT and endT in self.whiteFrames?
            startIndex = self.whiteFrames.searchsorted(self.startT[i])
            endIndex = self.whiteFrames.searchsorted(self.endT[i])         # endT[i] is most likely not in whiteFrames, that's why I'm using searchsorted
            
            # extract all those white frames in between startIndex and endIndex
            #tempArray = whiteFrameArray[startIndex + 1:endIndex] - whiteFrameArray[startIndex:endIndex-1]
            
            self.period.append( 1.0*(self.endT[i]-self.startT[i])/(endIndex-startIndex) )


