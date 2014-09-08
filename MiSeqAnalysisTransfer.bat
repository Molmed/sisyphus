@echo off

REM Windows batch script to copy a MiSeq analysis folder from e.g. the MiSeq control computer to the mounted network drive and path specified within the script.
REM File copy is initiated by drag-and-dropping the folder onto the script. 

REM Predefined variables:
set contact=medsci-molmed-bioinfo@lists.uu.se
set biotankdrive=U:\
set biotankdir=MiSeq\Runfolders\MiSeqAnalysis\
set miseqdrive=D:\
set miseqanalysisfolder=Illumina\MiSeqAnalysis\

REM Parse the supplied argument:
set miseqfolder=%~f1
set rundrive=%~d1
set rundir=%~p1
set runname=%~n1

REM Check that the supplied folder's parent is the expected path
if not %miseqdrive%%miseqanalysisfolder% == %rundrive%%rundir% (
echo The supplied folder, "%miseqfolder%", is not in the expected location, "%miseqdrive%%miseqanalysisfolder%". Please verify that the correct folder was supplied and press Ctrl+C if you want to abort.
pause
)

REM Transfer the files using robocopy
REM /e - Copy (possibly empty) subdirectories
REM /z - Use restart mode
echo About to start copying the folder "%miseqfolder%" to "%biotankdrive%%biotankdir%"
pause

REM Assert that the file indicating finished analysis is present, wait for user to confirm that analysis has finished and loop until this can be verified
:complete
if not exist %miseqfolder%\CompletedJobInfo.xml (
echo A file, "Completedjobinfo.xml", indicating that secondary analysis has finished is not present in %miseqfolder%. Please wait until analysis has finished and once it is done, press any key to continue.
pause 
goto complete
)
robocopy "%miseqfolder%" "%biotankdrive%%biotankdir%%runname%" * /e /z
if errorlevel 4 (goto error) else (goto ok)

:ok
echo -----
echo All files transferred successfully!
set timestamp=
for /f "usebackq tokens=*" %%a in (`date /t`) do set timestamp=%timestamp%%%a
for /f "usebackq tokens=*" %%a in (`time /t`) do set timestamp=%timestamp%%%a
echo %timestamp% > "%biotankdrive%%biotankdir%%runname%\TransferComplete.txt"
echo %timestamp% > "%miseqfolder%\TransferComplete.txt"
pause
exit 0

:error
echo -----
echo There was an error transferring the MiSeq analysis in %miseqfolder% to %biotankdrive%%biotankdir%. You should check connectivity to the mounted biotank drive (%biotankdrive%) and then retry the file copy. If the problem persists, please contact %contact%
pause
exit 1 
