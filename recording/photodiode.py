'''
this class holds together all necessary functionality to analyse a photodiode.

A word of caution
The monitor fliping rate is a finite number and therefore each flipping takes some time.
Defining the stimulus start time requires an arbitrary decission, matching a concrete event
with a single time within the monitor flipping time. I'm matching the start time to the peak
of the PD recording

'''
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

        # extract some variables that are general and don't depend on the particular bin file
        self.header = binary.readbinhdr(self.binFiles[0])
        self.regex = regex


    def get_raw(self, start_t, end_t):
        '''
        Return PD between start_t and end_t
        
        start_t/end_t are both in absolute time since the start of recording
        as is wait4rec_start_t. wait4rec_start_t is probably in the order of 3-5
        seconds and represents the time of the 1st white frame of the 1st stimulus
        '''

        """
        # each bin file holds the same amount of data 'self.header['nsamples'] (may be except for the last one that
        # is probably shorter). Figure out which ones need to be open to extract PD
        start_file = start_t * self.header['fs'] // self.header['nsamples']
        end_file = end_t * self.header['fs'] // self.header['nsamples'] + 1 # +1 because I want ts include file with this data in the for loop
        
        # start_t is most likely such that we have to start reading the PD somewhere in the middle
        # middle of a binFile.
        start_sample = np.mod(start_t * self.header['fs'], self.header['fs'])

        """
        map_object = map(lambda x: binary.readbin(x, [0]).flatten(), self.binFiles)
        raw = np.concatenate(list(map_object))

        raw -= raw.min()
        
        self.raw = raw
        return raw[start_t*self.header['fs']:end_t*self.header['fs']]


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


    def get_stim_waitframes(self):
        '''
        From a PD recording, compute the number of monitor frames a given stimulus is
        shown for, this is the minimum number of frames any image is on the monitor and is
        a parameter of the stimulus
        
        Output:
        -------
            self.stim_waitframes:      average monitor flips per second
        
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
        

    def get_peaks(self, raw, start_t, end_t=None):
        '''
        given a photodiode 'raw' recording, find the maxima of each frame.

        There are two tricks in the implementation:
        1.  I'm computing possition of minima knowing that one frame lasts on average
            self.samples_per_frame. It doesn't matter if I don't get the position of the 
            minima exactly right, I'm just using them to extract the maxima in between.
        2.  I'm using map to compute the maxima in between consecutive minima.
            Once I have an estimated position for the minima I compute the maxima in between
            consecutive pairs of minima.

        inputs:
        ------
            raw:        raw pd recording

            start_t:    time at which start looking for peaks. Hopefully close to a minima
                        and not close to a peak.

            end_t:      time at which to stop looking for peaks.
                        if None defaults to end of raw recording
        '''

        # locate first minimum
        #start_sample = start_t * self.header['fs']
        #first_min = raw[start_sample:start_sample + self.samples_per_frame].argmin() + start_sample

        #pdb.set_trace()
        # assuming samples_per_frame, estimate position on following minimum
        if end_t is None:
            end_t = len(raw)/self.header['fs']

        framesN = int(np.round((end_t - start_t)*self.header['fs']/self.samples_per_frame))
        minima = [int(start_t + i*self.samples_per_frame) for i in range(framesN+1)]

        # This are the actual maxima
        peaks = list(map(lambda x0,x1: raw[x0:x1].max(), minima[:-1], minima[1:]))
        
        # this is where the maxima take place
        samples = list(map(lambda x0,x1: raw[x0:x1].argmax()+x0, minima[:-1], minima[1:]))
        
        return peaks, samples


    def get_wait4rec_start_t(self):
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
        self.get_monitor_framerate()
        self.get_stim_waitframes()
        
        raw = self.get_raw(0, 50)

        peaks, samples = self.get_peaks(raw, 0)
        darker_values_samples = np.where(peaks < max(peaks)/2)[0]
        
        # the 4th darker value of the PD corresponds to the last black frame just before
        # stim starts. I'm defining  stimulus start time as roughly the timing of the next peak
        self.wait4rec_start_sample = int(samples[darker_values_samples[3]] + self.samples_per_frame)
        self.wait4rec_start_t = self.wait4rec_start_sample / self.header['fs']

    def read_stim_code(self, raw, start_t, delta_t=None):
        '''
        When a stimulus starts, photodiode goes white on 1st frame (stays white
        for waitframes) and then the stim_code is present (20 binary frames, most
        significant bit first)
        
        read the following 20 digit binary code

        input:
        -----
            raw:                pd recording

            start_t:     in seconds, possition of expected white frames

            delta_t:            in seconds, time before and after start_t
                                to look for white frames preceding binary code.
                                Default to None, in which caste start_t is assume
                                to be precisse.

        output:
        ------
            stim ID:            decoded stimulus number.
        '''
        
        pdb.set_trace()

        # starting at start_t - delta_t and ending at start_t + delta_t
        # find the position of the maxima
        if delta_t is not None:
            assert(start_t >0)
            start_sample = (start_t - delta_t)*self.header['fs']
            end_sample = (start_t + delta_t)*self.header['fs']

            white_time = raw[start_sample:end_sample].argmax() / self.samples_per_frame
        else:
            white_time = start_t

        # make sure we are at the end of the white frames, right before the stim code
        # starts coming in.
        peaks, samples = self.get_peaks(raw, white_time - 1/self.monitor_framerate)

        white_threshold = 0.85
        for i, peak in enumerate(peaks):
            if peak < peaks[0]*white_threshold:
                first_non_white_sample = samples[i]
                print("First non white frame was found @ {0}".format(first_non_white_sample))
                break


        # read the next 20 * waitframes peak PD values
        pdb.set_trace()
        code_start_t = (first_non_white_sample - 0.5*self.samples_per_frame)/self.header['fs']
        code_end_t = code_start_t + (self.stim_waitframes * 20 + 0.5) / self.monitor_framerate
        #code_end_t = code_start_t + 1 / self.monitor_framerate
        peaks, _ = self.get_peaks(raw, code_start_t, code_end_t)

        # average 'waitframes' 
        peaks = np.array(peaks)
        peaks = peaks.reshape(-1, self.stim_waitframes).mean(axis=1)

        print(peaks)
        powers_of_2 = np.array([2*(19-i) for i in range(20)])

        return (powers_of_2*peaks).sum()
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

