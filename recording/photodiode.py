from recording import binary
import numpy as np
import re
from os import listdir, path
import subprocess
from matplotlib import pyplot
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

    def process(self):
        self.get_monitor_framerate()
        self.get_stim_waitframes()
        self.get_raw(self.binFiles[0], 0, 50)
        self.get_start_time()

    def get_raw(self, file, start_t, end_t):
        raw = binary.readbin(file, [0]).flatten()
        raw -= raw.min()
        self.raw = raw[start_t*self.header['fs']:end_t*self.header['fs']]

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
        self.samples_per_frame = self.header['fs']/self.monitor_framerate

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
        
    def down_sample(self, raw):
        '''
        Take a raw recording and sample it down by averaging the luminance over each
        monitor flip

        It is important to average from minimum to minimum without contaminating with 
        either the previous or the next luminance value

        I find the first minimum of the raw recording in between 1st sample and
        self.header['fs'] /self.monitor_framerate
        '''

        pdb.set_trace()
        # find position of 1st minimum
        samples_per_frame = int(self.header['fs'] / self.monitor_framerate)
        first_minimum_sample = raw[:samples_per_frame].argmin()

        # TODO decide what to do with raw data up until the first_minimum_sample
        #   for the time being, I'm going to keep the number of samples in raw fixed
        #   and I'm just going to rotate the wave such that first_minimum_sample 
        #   corresponds to either point 0 or point samples_per_frame-1 of raw
        if first_minimum_sample > samples_per_frame/2:
            # make sample corresponding to first_minimum_sample match point
            # samples_per_frame of new raw
            end_point = len(raw) - (samples_per_frame - first_minimum_sample)
            new_raw = np.concatenate((raw[-end_point:], raw[end_point:]))
        else:
            # make sample corresponding to first_minimum_sample match point
            # 0 of new raw
            new_raw = np.concatenate((raw[first_minimum_sample:], raw[:first_minimum_sample:]))

        # reshape raw
        # I need total samples in raw to be an integer number of samples_per_frame
        samples = samples_per_frame * len(raw) // samples_per_frame 
        new_raw = new_raw[:samples]
        new_raw = new_raw.reshape(-1, samples_per_frame)
        return new_raw.mean(axis=1)

    def get_peaks(self):
        '''
        given a photodiode 'raw' recording, find the maxima of each frame.

        I'm assuming that minima in pd recording are spaced every self.samples_per_frame
        even though this is not an integer number.

        Once I have an estimated position for the minima I compute the maxima in between
        consecutive pairs of minima.
        '''

        # locate first minimum
        first_min = self.raw[:self.samples_per_frame].argmin()

        #pdb.set_trace()
        # assuming samples_per_frame, estimate position on following minimum
        framesN = len(self.raw)//self.samples_per_frame - 1
        minima = [int(first_min + i*self.samples_per_frame) for i in range(int(framesN))]

        peaks = list(map(lambda x0,x1: self.raw[x0:x1].max(), minima[:-1], minima[1:]))
        samples = list(map(lambda x0,x1: self.raw[x0:x1].argmax()+x0, minima[:-1], minima[1:]))
        return peaks, samples

    def get_start_time(self):
        '''
        if using the triggering system to start stimulus automatically with recording, 
        the photodiode will be:
            gray for some time
            black for one frame
            white for some time
            black or dark gray for 3 frames
            stimulus starts right after those 3 dark frames.

        output:
        ------
            self.start_time:    peak time of first stimulus frame
        '''
        pdb.set_trace()
        peaks, samples = self.get_peaks()
        darker_values_samples = np.where(peaks < max(peaks)/2)[0]
        
        # find the sample corresponding to the peak of the last black frame just before
        # stim starts
        #last_dark_maxima_sample = samples[darker_values_samples[3]]

        # define stimulus start as a fraction of samples_per_frame after this last_dark_maxima
        self.stim_start_sample = samples[darker_values_samples[3]] + 0.5 * self.samples_per_frame
        self.stim_start_t = self.stim_start_sample / self.header['fs']

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

