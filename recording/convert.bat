REM store original directory
REM set old_cd=%cd%

REM switch to directory passed as 1st argument
cd

cd %~f1

cd 

REM Execute convert_from_FIFO with 2nd argument
"C:\Users\Baccus Lab\Anaconda3\python.exe" "C:\Users\Baccus Lab\Documents\GitHub\igor\recording\convert.py" %2