# Igor utilities

for dealing with Igor files in experiments

## Installation

Run `python setup.py install` (for permanent install) or `python setup.py develop` (for development installation).

## Usage

For example, let's say you did an experiment on May 13, 2015. Then you might run something like:
```python
from convert import interleaved_to_chunk
interleaved_to_chunk("150513.bin", "150513_FIFO", "150513")
```
to convert the FIFO file to a series of binary files, "150513a.bin", "150513b.bin", and so on, where each file contains 1000 seconds of the experiment.

The `interleaved_to_chunk` function in `convert.py` requires the following arguments: `headerfile` - the sample header `.bin` file, `fifofile` - contains the experiment data as a FIFO file (output from the recording system),and `outputfilebase` - the desired base filename for the output files (a letter is appended to denote each of the 1000 second segments).

## Requires

- Numpy
