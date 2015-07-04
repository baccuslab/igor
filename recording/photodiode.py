'''
this class holds together all necessary functionality to analyse a photodiode.

There are several quantities that
A word of caution
The monitor fliping rate is a finite number and therefore each flipping takes some time.
Defining the stimulus start time requires an arbitrary decission, matching the first monitor
flip with a single time within the monitor flipping time. I'm matching the start time to the peak
of the PD recording

'''
from . import binary
from Experimental_DB import experimental_db
import numpy as np
import re
from os import listdir, path
import subprocess
from matplotlib import pyplot
import pymysql.cursors
import pdb
import dateutil

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

        self.__monitor_framerate__()
        self.__waitframes__()
        self.__wait4rec_start_t__()
        self.stim_id = [self.read_stim_code(self.raw, self.start_t)]

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
        #pdb.set_trace()
        map_object = map(lambda x: binary.readbin(x, [0]).flatten(), self.binFiles)
        raw = np.concatenate(list(map_object))

        raw -= raw.min()
        
        self.raw = raw
        return raw[start_t*self.header['fs']:end_t*self.header['fs']]


    def __monitor_framerate__(self):
        '''
        compute the monitor's framerate from a PD recording.
        
        Output:
        -------
            adds two key/value paires to self.header
            
            framerate:             average monitor flips per second
            
            samples_per_frame:      average samples per frame
        '''
        import scipy
        import scipy.fftpack
        import sys

        # load the photodiode, 100s is enough
        #pdb.set_trace()
        length = min(100, self.header['nsamples']/self.header['bytes_per_sample']/self.header['fs'])    # in seconds
        raw = binary.readbin(self.binFiles[0], [0]).flatten()
        raw = raw[:length * self.header['fs']]     # header['fs'] is the sampling rate (samples per second)

        # FFT the signal
        rawFFT = scipy.fftpack.rfft(raw)
        rawFFT[0] = 0
        rawFreqs = scipy.fftpack.rfftfreq(raw.size, 1./self.header['fs'])
        
        # get the freq with max FFT power
        self.header['monitor_framerate'] = rawFreqs[np.abs(rawFFT).argmax()]
        self.header['samples_per_frame'] = self.header['fs']/self.header['monitor_framerate']

        return raw, rawFFT, rawFreqs

    def __waitframes__(self):
        '''
        Compute waitframes from the PD recording.
        
        waitframes:     is the minimum number of frames any image is on the monitor and is
        a parameter of the stimulus
        
        Output:
        -------
            self.header['waitframes']:      integer number, usually 30ms / self.header['fs']
        
        '''

        # 100 seconds should be good enough
        length = 100        # in seconds
        samples = min(length * self.header['fs'], self.header['nsamples']/self.header['bytes_per_sample'])

        # For each monitor frame, compute the average luminance
        #pdb.set_trace()
        raw = binary.readbin(self.binFiles[0], [0]).flatten()
        values, _ = self.get_frame_values(np.mean, raw, 0, end_t=None)
        values = np.array(values)
        values -= values.mean()
        
        if not 'monitor_framerate' in self.header:
            self.__monitor_framerate__()

        # now compute circular correlation
        circCorr = np.correlate(values, np.hstack((values[1:], values)), mode='valid')  

        # assuming that waitframes > 1, 
        # circCorr should have the maximum at 0 and decrease at a fairly constant
        # pace until waitframes. then it should level off. I'm going to compute the 
        # derivative and check if at some point decreases drastically.
        slope = np.diff(circCorr)
        self.header['waitframes'] = (slope > slope[0]/2).argmax()
        

    def get_frame_values(self, func, raw, start_t, end_t=None):
        '''
        given a photodiode 'raw' recording, find some statistic of each frame.

        by statistic I mean 'func' which should be something like: min, max, mean, etc.

        There are two tricks in the implementation:
        1.  I'm computing possition of minima knowing that one frame lasts on average
            self.header['samples_per_frame']. It doesn't matter if I don't get the position of the 
            minima exactly right, I'm just using them to extract the maxima in between.
        2.  I'm using map to compute the maxima in between consecutive minima.
            Once I have an estimated position for the minima I compute the maxima in between
            consecutive pairs of minima.

        inputs:
        ------
            func:       function to apply in between two consecutive pd valleys

            raw:        raw pd recording

            start_t:    time at which start looking for peaks. Hopefully close to a minima
                        and not close to a peak.

            end_t:      time at which to stop looking for peaks.
                        if None defaults to end of raw recording
        '''

        # locate first minimum
        #start_sample = start_t * self.header['fs']
        #first_min = raw[start_sample:start_sample + self.header['samples_per_frame']].argmin() + start_sample

        #pdb.set_trace()
        # assuming samples_per_frame, estimate position on following minimum
        if end_t is None:
            end_t = len(raw)/self.header['fs']

        framesN = int(np.round((end_t - start_t)*self.header['fs']/self.header['samples_per_frame']))
        minima = [int(start_t*self.header['fs'] + i*self.header['samples_per_frame'])
                for i in range(framesN+1)]

        # This are the actual values after applying func
        peaks = list(map(lambda f,x0,x1: f(raw[x0:x1]), [func]*(len(minima)-1), minima[:-1], minima[1:]))
        
        # this is where the maxima take place, TODO change it such that the computation depends on func?
        samples = list(map(lambda x0,x1: raw[x0:x1].argmax()+x0, minima[:-1], minima[1:]))
        
        return peaks, samples


    def __wait4rec_start_t__(self):
        '''
        if using the triggering system to start stimulus automatically with recording, 
        the photodiode will be:
            gray for some time
            black or 'waitframes' frames
            stimulus starts right after with white 'waitframes' frames.

        output:
        ------
            self.start_time:    peak time of first stimulus frame
        '''
        #pdb.set_trace()
        raw = self.get_raw(0, 5)

        peaks, samples = self.get_frame_values(np.mean, raw, 0)
        # define as start time the peak time of the 1st white frame.
        # I'm defining as white anyting above 1.5* first peak intensity
        white_values_samples = np.where(peaks > peaks[0]*1.5)[0][0]
        
        self.start_sample = int(samples[white_values_samples])
        self.start_t = self.start_sample / self.header['fs']

    def read_stim_code(self, raw, start_t):
        '''
        When a stimulus starts, photodiode goes white on 1st frame (stays white
        for waitframes) and then the stim_code is present (20 binary frames, most
        significant bit first)
        
        read the following 20-digit binary code

        input:
        -----
            raw:         pd recording

            start_t:     in seconds, possition of first white frames (there are 'waitframes' before
                        the first binary code frame.

            delta_t:            in seconds, time before and after start_t
                                to look for white frames preceding binary code.
                                Default to None, in which caste start_t is assume
                                to be precisse.

        output:
        ------
            stim_ID:            decoded stimulus number.
        '''
        
        #pdb.set_trace()


        # start_t is the peak of the 1st white frame. I'm going to back up 
        # half a frame period to be roughly in the valley before the first
        # white frame and then extract the values of the next 21*'waitframes'
        # frames
        read_start_t = start_t - 1/(self.header['monitor_framerate']*2)
        read_end_t = read_start_t + 21*self.header['waitframes']/self.header['monitor_framerate']
        values, _ = self.get_frame_values(np.mean, raw, read_start_t, read_end_t)

        # average over consecutive 'waitframes' frames
        values = np.array(values)
        values = values.reshape(-1, self.header['waitframes']).mean(axis=1)[1:]
        values = values>values.max()*.8
        
        print(values)
        powers_of_2 = np.array([2**(19-i) for i in range(20)])

        return (powers_of_2*values).sum()
        # find the peak of the recording
        peak_x = raw_pd[start_pnt:end_pnt].argmax()
        peak_y = raw_pd[peak_x]

        # First I want to identify the last white frame. The peak just identified could
        # be any one of self.header['waitframes']
        frame_period_in_samples = self.header['fs']/self.header['monitor_framerate']

        for i in range(self.header['waitframes'] - 1):
            new_peak = raw_pd[peak_x + i * frame_period_in_samples]
            print(new_peak, new_peak < 0.8 * peak_y)
            if new_peak < 0.8 * peak_y:
                break

        # extract 20 * waitframes peak values
        values = np.array([raw_pd[peak_x + j * frame_period_in_samples] for j in range(i, i+20*self.header['waitframes'])])

        # now average across waitframes
        values = values.reshape(-1, self.header['waitframes']).mean(axis=1)
        terms = [values[i]*2**2(0-i) for i in range(20)]
