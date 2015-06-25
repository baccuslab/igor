from nose.tools import assert_equal, assert_true, assert_raises, assert_almost_equal
from recording import photodiode
from os import path, listdir
import pdb

def setup():
  print("SETUP!")

def teardown():
  print("TEAR DOWN!")

def test_basic():
  print("I RAN!")

def test_monitor_framerate_and_stim_waitframes():
    waitframes = [30, 10, 3, 1, 10, 3, 2]
    i = 0

    files = [f for f in listdir('recording/tests') if f.endswith('.bin') and f.startswith('150625')]
    for f in files:
        f = path.join('recording/tests', f)
    #for f in [f1 for f1 in listdir('.') if f1.endswith('.bin')]:
    #    f = path.join('.', f)
        pd = photodiode.PD(f)
        pd.get_monitor_framerate()
        assert_almost_equal(99.9, pd.monitor_framerate, places=1)
        
        pd.get_stim_waitframes()
        assert_equal(pd.stim_waitframes, waitframes[i])
        i+=1

