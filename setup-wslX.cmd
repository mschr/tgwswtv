@echo off 2>1 > NUL
if not defined DISTRO (set DISTRO=Debian)
if not defined DOWNLOAD_DIR (set DOWNLOAD_DIR=C:\Users\%USERNAME%\Downloads)
set WSL_KERNELUPG_URL=https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi
set WSLTTY_INSTALLER=https://github.com/mintty/wsltty/releases/download/3.5.1/wsltty-3.5.1-i686-install.exe
rem ------------------------------------------------------------------ begin main
set SCRIPT_PATH=%~0
set argv=
set cmd=
set PIDFILE=
set INSTALL=1
set UNINSTALL=
set carryover=0
set DEBUG=0
set "ENV_PATH=export PATH='/cygdrive/c/cygwin64/bin:/cygdrive/c/cygwin64/usr/bin:/cygdrive/c/cygwin64/usr/local/bin:$PATH';"

:parse_args
setlocal ENABLEDELAYEDEXPANSION

:: -root has setter and will shift twice (
::       sets CYGWIN_ROOT
:: -pidfile has setter and will shift twice
::       sets PIDFILE, means we are in an enforced elevated process and the parent will monitor this file
:: -install is a flag and will only shift once
::       enables INSTALL mode, which then lets modules follow .install pattern
:: -uninstall is a flag and will only shift once
::       enables UNINSTALL mode, which then lets modules follow .uninstall pattern
::       using this mode will essentially uninstall the given module

set "options=-root:"%CYGWIN_ROOT%" -help: -pidfile:"" -uninstall: -install: -wsl:0 -debug: -procname:"" -process-name:"" -join: -nowait: -noexit: -runas:"
:: Call :verboselog parse args [%*] permits: %options%
set "argv="

:: running through permitted options in string-for-loop 
:: then look at whats after ':' 
:: and then set the %-arg% with whichever default it has
:: NB: Variables should use double-quote for multiword default values (and so should cli)
:: NNB: Defaults that has a blank default value are defined in empty quote as such: -arg:""
:: NNNB: Defaults with a defined value requires a 'setter' argument and consumes two 'words' from each loop
for %%O in (%options%) do for /f "tokens=1,* delims=:" %%A in ("%%O") do set "%%A=%%~B"
:loop
:: first, grab currently shifted arg 1
set "cur=%~1"
:: then, allow for double-dash option identifiers (both -opt and --opt works)
:: setting will 'recorded' as the single-dash variant (!-opt! to output)
setlocal DISABLEDELAYEDEXPANSION
if "%cur:~0,2%" EQU "--" (
	ENDLOCAL & set "cur=%cur:~1%" 
) else ENDLOCAL

:: then look at current %1 and identify eof (effectively break loop)
if "%cur%"=="" Goto :endArgs
:: ---
setlocal ENABLEDELAYEDEXPANSION
set "test=!options:*%cur%:=! "
:: echo "PARSE !options:*%cur%:=!"
if "!test!"=="!options! " (
:: concat to argv as leftover
	set "argv=!argv! %cur%"
) else if "!test:~0,1!"==" " (
:: set flag true
	set "%cur%=1"
) else (

:: retreive argument, whilst excaping ^ and ! chars
	setlocal DISABLEDELAYEDEXPANSION
	set "val=%~2"
	Call :escapeVal
	setlocal ENABLEDELAYEDEXPANSION
	for /f delims^=^ eol^= %%A in ("!val!") do ENDLOCAL & ENDLOCAL & set "%cur%=%%A" !
	shift
)
:: ---
shift
Goto :loop
:: subroutine that targets 'var' and removes chars that will affect a commandline
:escapeVal
:: escape any hat-chars
set "val=%val:^=^^%"
:: escape any exclaimation-chars
set "val=%val:!=^!%"
rem set "val=%val:"=""%"
exit /b
:endArgs
if "!-wsl!" NEQ "1" (
	set "-cygwin=1"
)

set -  2>1 > NUL

if "%CYGWIN_ROOT%" EQU "" (set "CYGWIN_ROOT=!-root!")
if "!pidfile!" NEQ "" (set "PIDFILE=!-pidfile!")

if "!-uninstall!" EQU "1" (
	set "UNINSTALL=1"
	set "INSTALL="
) else (
	set "UNINSTALL="
	set "INSTALL=1"
)

:: finalize by recocknizing only arg0 as cmd (the :do-<cmd> goto)
:: but only do so, if no callback has been set
if not defined CB_GOTO for /f "tokens=1* delims= " %%a in ("%argv%") do (set "argv=%%b" & set "cmd=%%a")
if "%CB_GOTO%" EQU "" for /f "tokens=1* delims= " %%a in ("%argv%") do (set "argv=%%b" & set "cmd=%%a")
if "%cmd%" NEQ "" Call :verboselog splitting command as first from argv

:: -- begin PS parse_args

set cb_ps_noexit=0
if "!-noexit!" EQU "1" (
	set cb_ps_noexit=1
)
set cb_ps_join=1
if "!-join!" EQU "1" (
	if "!-nowait!" EQU "1" (
		set cb_ps_join=0
		set cb_ps_nowait=1
	) else (
		set cb_ps_join=1
	)
)
set cb_ps_runas=0
if "!-runas!" EQU "1" (
	set cb_ps_runas=1
)
set cb_ps_procname=
if "!-procname!" NEQ "" (
	set cb_ps_join=0
	set cb_ps_procname=!-procname!
)
if "!-process-name!" NEQ "" (
	set cb_ps_join=1
	set cb_ps_procname=!-process-name!
)

:: -- end parse_args
:: -----------------------------------------------------------------
:: setup debug levels
if "!-debug!" EQU "1" (
	set DEBUG=1
)
:: check for help argument or invalid commands
set matched=
if "%cmd%" EQU "" (
	set errmsg=Please invoke with a command
	set matched=1
	Goto :endChecks 
)
if "!-help!" EQU "1" ( 
    set errmsg=Thank you, for inquiering about my very particular set of skills, It! Follows
    set matched=1
    Goto :endChecks
  )
)
:endChecks
if defined CB_GOTO (
	Goto :%CB_GOTO%
)

echo %errorlevel%
powershell -Command "Add-Type -AssemblyName PresentationFramework; $ans=[System.Windows.MessageBox]::Show('Wish to install WSL tty (enhanced terminal)', 'Would u want to...?', 'YesNo'); switch($ans){'Yes' {exit 0} 'No' {exit 1} 'Cancel'{exit 2} }"
if "%errorlevel%" EQU "0" (
    Call :wsltty.install
)
powershell -Command "Add-Type -AssemblyName PresentationFramework; $ans=[System.Windows.MessageBox]::Show('Wish to install WSL 2?', 'Would u want to...', 'YesNo'); switch($ans){'Yes' {exit 0} 'No' {exit 1} 'Cancel'{exit 2} }"
if "%errorlevel%" EQU "0" (
    Call :wslv2.install
)
powershell -Command "Add-Type -AssemblyName PresentationFramework; $ans=[System.Windows.MessageBox]::Show('Wish to install GWSL?', 'Manage X-server as well?!', 'YesNo'); switch($ans){'Yes' {exit 0} 'No' {exit 1} 'Cancel'{exit 2} }"
if "%errorlevel%" EQU "0" (
    Call :gwsl.install
)
powershell -Command "Add-Type -AssemblyName PresentationFramework; $ans=[System.Windows.MessageBox]::Show('Wish to install systemd-genie in WSL?', 'Ask the genie!!!', 'YesNo'); switch($ans){'Yes' {exit 0} 'No' {exit 1} 'Cancel'{exit 2} }"
if "%errorlevel%" EQU "0" (
    Call :systemd.install
)

:: Call :systemd.install
goto :eof


:verboselog
if "%DEBUG%" EQU "1" (
	echo %*
)
Goto :eof





:wsltty.install
if not exist %DOWNLOAD_DIR%\wsltty-3.5.1-i686-install.exe (
	Call :ps Invoke-WebRequest %WSLTTY_INSTALLER% -OutFile %DOWNLOAD_DIR%\wsltty-3.5.1-i686-install.exe
)
Call :ps --runas "%DOWNLOAD_DIR%\wsltty-3.5.1-i686-install.exe"
start explorer %APPDATA%\Microsoft\Windows\Start Menu\Programs\WSLtty
Goto :eof





:wslv2.install
Call :ps -runas dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
Call :ps  -runas dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
if not exist "%DOWNLOAD_DIR%\wsl_update_x64.msi" (
	Call :ps Invoke-WebRequest %WSL_KERNELUPG_URL% -OutFile %DOWNLOAD_DIR%\wsl_update_x64.msi
)
Call :ps -runas C:\Users\morte\Downloads\wsl_update_x64.msi
wsl --set-default-version 2
wsl --set-version %DISTRO% 2
Goto :eof




:systemd.install
:: transdebian repo
powershell -Command "Add-Type -AssemblyName PresentationFramework; $ans=[System.Windows.MessageBox]::Show('SUDO incoming - Keep an eye out in terminal', 'Enter password', 'OK');"
for %%F in (%SCRIPT_PATH%) do set sourcedirname=%%~dpF
Call :ps -runas cp %sourcedirname%\dotnet-genie.sh c:\
wsl cp /mnt/c/dotnet-genie.sh ~/
wsl chmod +x ~/dotnet-genie.sh
wsl sudo ~/dotnet-genie.sh
Call :ps -runas del c:\dotnet-genie.sh
Goto :eof




:gwsl.install
winget list | findstr GWSL || winget install GWSL
Goto :eof



:: -----------------------------------------------------------------
:: PS functionality - primarily to elevate as admin if user has not
:: -----------------------------------------------------------------


:ps
Call :verboselog --call-PS-- %argv%
SETLOCAL ENABLEDELAYEDEXPANSION
rem default setting is 
rem to await job completion
;;set join=1
rem and to close the window after executing command
;;set noexit=0
rem never elevate, unless doing the Call to :check-isadministrator
rem elevating prompt will not be possible to join upon without accessing tasklist
;;set elevated=0
rem if set, wait for a process by this name
;;set proc_name=

:: hooks up with regular argument parsing
if not defined CB_GOTO (
	set CB_GOTO=ps
	Goto :parse_args
)
set CB_GOTO=

:: forms a command line for powershell.exe
set szelevate=
set szwait=
set szwaitname=
set sznoexit=
set argv=%argv:_'_=,%
rem construct the parts of command requested via toggle parameters
if "%cb_ps_runas%" EQU "1" (
	echo need to elevate process
	set "szelevate=-Verb RunAs"
)
if "%cb_ps_join%" EQU "1" (
	echo will await child process exit
	set "szwait= -Wait" 
)
if "%cb_ps_procname%" NEQ "" (
	if "%cb_ps_join%" NEQ "0" (
		set szwait=
	)
	rem inserted sleep to allow eventual elevation
	set "szwaitname= ; Sleep 5 ; Wait-Process -Name %cb_ps_procname%"
)
rem default is keep terminal open if command fails
set "sznoexit= ; if(-not $?) { Write-Host "Errornious Return Code while running following command: %argv%" ; pause  }"
if "%cb_ps_noexit%" EQU "1" (
	echo will hold child process window open
	set "sznoexit= ; pause" 
)
Call :verboselog "[noexit %cb_ps_noexit%] => %sznoexit%"
Call :verboselog "[nowait %cb_ps_nowait%] [join %cb_ps_join%] => %szwait%"
Call :verboselog "[runas %cb_ps_runas%] => %szelevate%"
Call :verboselog "proc_name %cb_ps_procname% => %szwaitname%"
Call :verboselog "argv: %argv% original cmd: %cmd%"

:: Call :DeQuote %psargv%
echo 'PS %szwait% %argv% %sznoexit%' %szwaitname%"
powershell.exe -Command "$proc = Start-Process Powershell%szwait% -PassThru %szelevate% '%argv% %sznoexit%' %szwaitname%"
exit /B %errorlevel%
ENDLOCAL