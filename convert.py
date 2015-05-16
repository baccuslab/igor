"""
Script for converting interleaved FIFO files (output of Igor recording script)
to chunked binary files (input for spike sorting system)

(c) Baccus Lab 2015
15 May 2015 - Initial version (based off of Pablo's script)

"""

import sys
import numpy as np
from shutil import copyfile


def interleaved_to_chunk(header, fifofile, outputfile):

    # some constants
    FIFO_HEADER_FIX_BYTES = 304
    FIFO_HEADER_BYTES_PER_CHANNEL = 76
    BYTES_PER_SAMPLE = 2                # data is recorded as int16
    fmt_string = 'int16'             # anything that is 2 bytes will work

    # read existing Igor .bin header to extract some needed variables
    hdr = readheader(header)

    # number of blocks
    nblocks = int(np.ceil(hdr['nscans'] / hdr['samples_per_channel']))

    # number of blocks per file

    # total number of bytes in one block taking all channels into account
    block_size = hdr['samples_per_channel'] * hdr['nchan'] * BYTES_PER_SAMPLE

    # read blocks from FIFO and skip header
    with open(fifofile, 'rb') as fifo:

        # jump past the header
        fifo.seek(FIFO_HEADER_FIX_BYTES + header.numberOfChannels * FIFO_HEADER_BYTES_PER_CHANNEL)

        # copy header to file_out
        copyfile(header, outputfile)

        # open output file, header is already written, so use 'append' mode
        with open(outputfile, 'ab') as output:

            for i in range(nblocks):

                # load data for this block
                data_one_block = fifo.read(block_size)

                # make sure 'data_one_block' has the right number of points before reshaping it
                if (len(data_one_block) != block_size):

                    # last read from file, not enough sample to fill a
                    # blockSize, write as much data as possible such that all
                    # channels get the same amount of data
                    samples_per_channel = len(data_one_block) // hdr['nchan'] // BYTES_PER_SAMPLE
                    last_block_size = samples_per_channel * hdr['nchan'] * BYTES_PER_SAMPLE
                    data_one_block = data_one_block[:last_block_size]

                # write data_one_block to output file but after reshaping it
                data_reshaped = np.fromstring(data_one_block, dtype=fmt_string).reshape(hdr['nchan'], samples_per_channel, order='F')

                # write the data to the output file!
                data_reshaped.tofile(output)


def readheader(filename):

    # store header information in a dictionary
    hdr = dict()

    # read the binary file
    with open(filename, 'rb') as f:

        # parser helper function
        parse = lambda d: np.fromfile(f, dtype=d, count=1)[0]

        # the size of the header (32 bit unsigned integer)
        hdr['size'] = parse('>I')
        hdr['type'] = parse('>h')
        hdr['version'] = parse('>h')

        # number of scans
        nscans = parse('>I')
        if nscans == 0:
            print("Warning: the value of nscans is 0. Using a large value (1e12) instead.")
            nscans = 1e12
        hdr['nscans'] = nscans

        # number of channels
        hdr['nchan'] = parse('>I')

        # whichChan is a list of recorded channels. It has as many items as
        # recorded channels. Each channel is a 2 byte signed integer
        hdr['whichChan'] = np.array([parse('>i2') for i in range(hdr['nchan'])])

        # big endian, 32 bit floating point
        hdr['scanrate'] = parse('>f')

        # more header info
        hdr['samples_per_channel'] = parse('>I')
        hdr['scaleMult'] = parse('>f')
        hdr['scaleOff'] = parse('>f')
        hdr['dateSize'] = parse('>i')   # big endian, 32 bit signed integer
        hdr['dateStr'] = parse('a'+str(hdr['dateSize']))
        hdr['timeSize'] = parse('>i', 1)
        hdr['timeStr'] = parse('a'+str(hdr['timeSize']), 1)    # string
        hdr['userSize'] = parse('>i', 1)
        hdr['userStr'] = parse('a'+str(hdr['userSize']), 1)

    return hdr


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

    interleaved_to_chunk(header, fifo, output)
