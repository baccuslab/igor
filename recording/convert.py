"""
Script for converting interleaved FIFO files (output of Igor recording script)
to chunked binary files (input for spike sorting system)

(c) Baccus Lab 2015
15 May 2015 - Initial version (based off of Pablo's script)

"""

import sys
import re
import os
import numpy as np
from shutil import copyfile
from binary import readbinhdr


def interleaved_to_chunk(headerfile, fifofile, outputfilebase):

    # some constants
    FIFO_HEADER_FIX_BYTES = 304
    FIFO_HEADER_BYTES_PER_CHANNEL = 76
    BYTES_PER_SAMPLE = 2                # data is recorded as int16
    SECONDS_PER_FILE = 1000             # how big each file should be
    fmt_string = '<h'                   # either '<h' (signed int 16) or '<H' (unsigned int 16)
    letters = list("abcdefghijklmnopqrstuvwxyz")

    # read existing Igor .bin header to extract some needed variables
    hdr = readbinhdr(headerfile)

    # overwrite the header number of samples value

    # the correct nsamples value
    nsamples = hdr['fs'] * SECONDS_PER_FILE

    # overwrite
    print('Overwriting the header nsamples value of 0 with %i (%i seconds per file)' % (nsamples, SECONDS_PER_FILE))
    overwrite_nsamples(headerfile, nsamples)

    # reload header
    hdr = readbinhdr(headerfile)
    if hdr['nsamples'] != nsamples:
        # if we reach this error, that means that we didn't properly overwrite the correct bits in the existing header file
        raise IOError('Error in header bin file! I made some sort of mistake trying to overwrite the nsamples value in the header.')

    # number of blocks per file
    nblocks_per_file = int(np.ceil(hdr['nsamples'] / hdr['blksize']))
    end_of_file = False

    # total number of bytes in one block taking all channels into account
    block_size = hdr['blksize'] * hdr['nchannels'] * BYTES_PER_SAMPLE

    samples_per_channel = hdr['blksize']

    # read blocks from FIFO and skip header
    with open(fifofile, 'rb') as fifo:

        # jump past the header of the FIFO file
        fifo.seek(FIFO_HEADER_FIX_BYTES + hdr['nchannels'] * FIFO_HEADER_BYTES_PER_CHANNEL)

        # for each file
        fidx = 0
        while not end_of_file:

            # create a new output file
            outputfile = outputfilebase + letters[fidx] + '.bin'
            print('Created file: ' + outputfile)
            fidx += 1

            # copy header to file_out
            copyfile(headerfile, outputfile)

            # open output file, header is already written, so use 'append' mode
            with open(outputfile, 'ab') as output:

                # write data
                for block_idx in range(nblocks_per_file):

                    # load data for this block
                    data_one_block = fifo.read(block_size)

                    # make sure 'data_one_block' has the right number of points before reshaping it
                    if (len(data_one_block) != block_size):

                        # last read from file, not enough sample to fill a
                        # blockSize, write as much data as possible such that all
                        # channels get the same amount of data
                        samples_per_channel = len(data_one_block) // hdr['nchannels'] // BYTES_PER_SAMPLE
                        last_block_size = samples_per_channel * hdr['nchannels'] * BYTES_PER_SAMPLE
                        data_one_block = data_one_block[:last_block_size]

                        print('End of FIFO file!')
                        end_of_file = True
                        break

                    else:
                        # reformat and reshape the data
                        data_reshaped = np.fromstring(data_one_block, dtype=fmt_string).reshape(hdr['nchannels'], samples_per_channel, order='F')

                        # write the data to the output file, swapping the byte
                        # order (little -> big endian)
                        data_reshaped.byteswap().tofile(output)

            # if the last file is shorter than the rest, write the appropriate
            # nsamples value in the header
            if end_of_file:
                nsamples = hdr['blksize'] * block_idx
                print('Warning: overwriting the header nsamples value of 0 with %i (%i seconds in the last file)' % (nsamples, nsamples / hdr['fs']))
                overwrite_nsamples(outputfile, samples_per_channel * hdr['nchannels'])

    print('Done!')


def overwrite_nsamples(headerfile, value):
    """
    Overwrites the 'nsamples' (also known as 'nscans') field in a binary header

    See binary.readbinhdr for more info

    Parameters
    ----------
    headerfile : string
        the name of the file

    value : int
        the correct value for nsamples to overwrite in the file
    """

    # convert to a byte string
    bytestr = np.array([value], dtype='>I').tostring(order='F')

    # write to the file
    with open(headerfile, 'r+b') as hfile:
        hfile.seek(8, 0)
        hfile.write(bytestr)


def output_files_exist(file):
    regexp = re.compile(file + "[a-z].bin")
    return any(list(map(lambda x: re.match(regexp, x), os.listdir())))


if __name__ == '__main__':

    if len(sys.argv) == 0 or len(sys.argv) > 3:
        error_string = """
        This function takes either one argument (prefix) and assumes the
        filenames are prefix.bin and prefix_FIFO or it can take two positional
        arguments: header and FIFO, which are the filenames for the header and
        FIFO files, respectively.

        Usage:
            python convert_from_FIFO.py prefix
            OR
            python convert_from_FIFO.py header_file FIFO_file
        """
        raise ValueError(error_string)

    if len(sys.argv) == 2:
        header = sys.argv[1] + '.bin'
        fifo = sys.argv[1] + '_FIFO'
        output = sys.argv[1]

    else:
        header = sys.argv[1]
        fifo = sys.argv[2]
        output = sys.argv[1].rstrip('.bin')

    # Check that none of the output files exist
    if output_files_exist(output):
        raise ValueError("Would overwrite output files." +
            "Remove them or specify a different output file name")

    interleaved_to_chunk(header, fifo, output)
