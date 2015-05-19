import os
from setuptools import setup

version = '0.0.0'

here = os.path.abspath(os.path.dirname(__file__))
try:
    README = open(os.path.join(here, 'README.md')).read()
except IOError:
    README = ''

setup(name='igor',
      version=version,
      description='Igor utilities for Baccus lab experiments',
      long_description=README,
      author='Niru Maheshwaranathan',
      author_email='nirum@stanford.edu',
      url='https://github.com/baccuslab/proxalgs',
      license='MIT',
      classifiers=[
          'Intended Audience :: Science/Research',
          'Operating System :: MacOS :: MacOS X',
          'Topic :: Scientific/Engineering :: Information Analysis'],
      py_modules=['binary', 'convert'],
      requires=['numpy'],
    )
