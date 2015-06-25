from recording import binary
import numpy as np
import re
from os import listdir, path
import subprocess
import pdb

class PD(object):
    def __init__(self, regex_string):
        '''
        Load the photodiode for all bin files that match the given regular expression 
        'regex_string'
        '''
        
        #pdb.set_trace()
        dirname = path.dirname(regex_string)
        basename= path.basename(regex_string)
        regex = re.compile(basename)

        # make a list with all binFiles in current folder
        self.binFiles = [path.join(dirname, f) for f in listdir(dirname) if regex.match(f)]

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

        # assuming that stim_waitframes > 1, 
        # circCorr should have the maximum at 0 and decrease at a fairly constant
        # pace until waitframes. then it should level off. I'm going to compute the 
        # derivative and check if at some point decreases drastically.
        slope = np.diff(circCorr)
        self.stim_waitframes = (slope > slope[0]/2).argmax()
        

    def read_stim_code(self, approx_start_t, delta_t):
        '''
        When a stimulus starts, photodiode goes white on 1st frame (stays white
        for waitframes) and then the stim_code is present (20 binary frames, most
        significant bit first)
        
        identify white frames in between (approx_start_t - delta_t, approx_start_t + delta_t)
        
        read the following 20 digit binary code

        input:
        -----
            approx_start_t:     in seconds, possition of expected white frames

            delta_t:            in seconds, how much time before and after approx_start_t
                                to use in the computation
        '''
        
        pdb.set_trace()
        raw_pd = binary.readbin(self.binFiles[0], [0]).flatten()

        # limit recording to (approx_start_t - delta_t, approx_start_t + delta_t)
        start_pnt = max((approx_start_t - delta_t) * self.header['fs'], 0)
        end_pnt = (approx_start_t + delta_t) * self.header['fs']

        raw_pd[:15000]=-5
        # find the peak of the recording
        peak_x = raw_pd[start_pnt:end_pnt].argmax()
        peak_y = raw_pd[peak_x]

        # First I want to identify the last white frame. The peak just identified could
        # be any one of self.stim_waitframes
        frame_period_in_samples = self.header['fs']/self.monitor_framerate

        for i in range(self.stim_waitframes - 1):
            new_peak = raw_pd[peak_x + i * frame_period_in_samples]
            print(new_peak, new_peak < 0.8 * peak_y)
            if new_peak < 0.8 * peak_y:
                break

        # extract 20 * waitframes peak values
        peaks = np.array([raw_pd[peak_x + j * frame_period_in_samples] for j in range(i, i+20*self.stim_waitframes)])

        # now average across stim_waitframes
        peaks = peaks.reshape(-1, self.stim_waitframes).mean(axis=1)
        terms = [peaks[i]*2**2(0-i) for i in range(20)]

