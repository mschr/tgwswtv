####################################################################
# SetupCygXWsl.ps1
# Script to assist in installing Cygwin-X server and WSL2
# You may switch with argument -uninstall to uninstall
# or switch with argument -GWSL to install GWSL instead of cygwin
#
# Using Cygwin-X implies starting DbusSession and PulseAudio services
# along with xinit (XWin), starting up as client on logon.
# Firewall rules are implemented, opening XWin to listen on TCP 
# in public networking to link it to the WSL switching layer.
#
# Add the following to your WSL .bashrc to link from inside WSL
#
#   export HOST_IP="$(ip route |awk '/^default/{print $3}')"
#   export PULSE_SERVER="tcp:$HOST_IP"
#   export DISPLAY="$HOST_IP:0.0"
#
# Using GWSL, X server runs with vcxsrv instead and must 
# be started manually. GWSL on the other hand, includes scripts to
# assist in setting up mentioned .bashrc export's
####################################################################
param (
    [string]$CygwinRoot = "c:\cygwin64",
    #[Parameter(Mandatory=$false)]
    [string]$Distro = "Debian",
    [string]$DownloadDir='c:\Users\'+$Env:USERNAME+'\Downloads',
    [string]$CygwinMirror='https://mirrors.dotsrc.org/cygwin/',
    [switch]$help=$false,
    [switch]$GWSL=$false,
    [switch]$debug=$false,
    [switch]$uninstall=$false
 )
 ## Set the script execution policy for this process
Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch {}
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
        $CommandLine = "-File `"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments
        Start-Process -FilePath PowerShell.exe -Verb Runas -Wait -ArgumentList $CommandLine
        Exit
    }
}
$CYGWIN_APTCYG_URL='https://raw.githubusercontent.com/transcode-open/apt-cyg/master/apt-cyg'
$WSL_KERNELUPG_URL='https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi'
$mktime_t=""
$mktime_sz=""

# for default downloaddir, check exists and probe for OneDrive folder downloaddir
if(($DownloadDir -eq 'c:\Users\'+$Env:USERNAME+'\Downloads') -and (-not (Test-Path $DownloadDir)))
{
    if(Test-Path 'c:\Users\'+$Env:USERNAME+'\OneDrive\Downloads') 
    {
        $DownloadDir = 'c:\Users\'+$Env:USERNAME+'\OneDrive\Downloads'
    } else
    {
        mkdir $DownloadDir
    }
}

# must be absolute with drive as well
function winpathToCygpath {
	param(
		[Parameter(Mandatory=$true)]
        [string]$Path
    )
	$Path = $Path.Replace("\", "/")
	$fragments = $Path -split ('/')
	$fragments[0] = ($fragments[0].ToLower()) -replace '^([a-z]):', '/cygdrive/$1'
	$Path = $fragments -join '/'
	return $Path
}
function verboselog {
    param(
        [Parameter(Mandatory=$true)]
        [string] $message
    )
    if($Debug) {
        Write-Host $message
    }
}
function runCygwin {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command
    )
	$root = winpathToCygPath -Path $CygwinRoot 
    $ENV_PATH="export PATH='${root}/bin:${root}/usr/bin:${root}/usr/local/bin:"+$Env::PATH+"'"
    $szexe = "$CygwinRoot\bin\bash.exe"
    $szargs= ' --init-file /etc/profile -c "' + $ENV_PATH+'; ' + $Command + ' "'
	if($Debug) {
        Write-Host $szexe + $szargs
    }
    "$szexe $szargs" | Invoke-Expression
    # return $?
}

function installWSL {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Distribution
    )
    verboselog "Checking feature installation"
    dism.exe /online /get-featureinfo /featurename:Microsoft-Windows-Subsystem-Linux >$null
    if($? -eq $false)
    {
        verboselog "Enabling feature: Microsoft-Windows-Subsystem-Linux"
        dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
    } else {
        verboselog "Feature: Microsoft-Windows-Subsystem-Linux already installed"
    }
    dism.exe /online /get-featureinfo /featurename:VirtualMachinePlatform >$null
    if($? -eq $false)
    {
        verboselog "Enabling feature: VirtualMachinePlatform"
        dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
    } else {
        verboselog "Feature: VirtualMachinePlatform already installed"
    }
    verboselog "Asserting Kernel upgrade"
    if(-Not (Test-Path "$DownloadDir\wsl_update_x64.msi")) {
        verboselog "Downloading wsl_update_x64.msi"
        Invoke-WebRequest $WSL_KERNELUPG_URL -OutFile $DownloadDir\wsl_update_x64.msi
    }
    "$DownloadDir\wsl_update_x64.msi /q" | Invoke-Expression
    verboselog "Setting default wsl version 2"
    $void = wsl.exe --set-default-version 2
    $check = wsl.exe --list | Where {$_.Replace("`0","") -match "^$Distribution"}
    if($null -eq $check) {
        verboselog "Installing $Distribution"
        wsl.exe --install -d $Distribution
        wsl.exe --set-version $Distribution 2
    } else {
        verboselog "Distro $Distribution already installed"
    }

    $check = wsl.exe --list | Where {$_.Replace("`0","") -match "^$Distribution \(Default\)"}
    if($null -eq $check) {
        verboselog "Setting default distro to $Distribution"
        wsl.exe --set-default $Distribution
    } else {
        verboselog "Default distro is already $Distribution"
    }
}
function installGWSL {
    param(
        [switch]$Remove
    )
    if($Remove) {
        "winget uninstall GWSL" | Invoke-Expression
    } else {
        $check = winget.exe list | Select-String -Pattern 'GWSL'
        if($null -eq $check) {
            "winget install GWSL" | Invoke-Expression
        }
    }
}
function installWsltty {
    param(
        [switch]$Remove
    )
    if($Remove) {
        "winget uninstall wsltty" | Invoke-Expression
    } else {
        if(-not (Test-Path "C:\Users\morte\AppData\Local\wsltty\bin\dash.exe")) {
            "winget install wsltty" | Invoke-Expression
        }
    }
}

function setupCygwin {
	param(
        [Parameter(Mandatory=$true)]
        [string]$Packages,
        [switch]$Remove
    )
	if(-Not (Test-Path $DownloadDir\setup-x86_64.exe)) {
		Invoke-WebRequest -Uri "http://www.cygwin.org/setup-x86_64.exe" -OutFile "$DownloadDir\setup-x86_64.exe"
	}
	$szargs = " -W -q -f -R $CygwinRoot -l $DownloadDir -s $CygwinMirror"
    if($Remove) {
        $szargs += " -x $Packages"
    } else {
        $szargs += " -P $Packages"
    }
    if($Debug) {
        Write-Host powershell.exe -Command "Start-Process Powershell -Wait '$DownloadDir\setup-x86_64.exe $szargs'"
    }
    powershell.exe -Command "Start-Process Powershell -Wait '$DownloadDir\setup-x86_64.exe $szargs'"
	return $?
}

function installPulseaudio {
    param(
        [switch]$Remove
    )
    if($Remove)
    {
        $service = Get-Service -Name CYGWIN-PulseAudio -ErrorAction SilentlyContinue
        if($service.Length -ne 0) {
            runCygwin "cygrunsrv -S CYGWIN-PulseAudio"
            runCygwin "cygrunsrv -R CYGWIN-PulseAudio"
        }
        if((Get-NetFirewallrule -DisplayName "PulseAudio Allow local" -ErrorAction 'silentlycontinue')) {
            Remove-NetFirewallRule -DisplayName "PulseAudio Allow local"
            Remove-NetFirewallRule -DisplayName "PulseAudio Block domain"
            Remove-NetFirewallRule -DisplayName "PulseAudio Block public"
        }
        $setup = setupCygwin -Remove -Packages "pulseaudio,pulseaudio-esound-compat,pulseaudio-utils"
        runCygwin "rm -fr /etc/pulse"
    } else 
    {
        $setup = setupCygwin -Packages "cygrunsrv,pulseaudio,pulseaudio-esound-compat,pulseaudio-utils"
        runCygwin "printf 'load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1;192.168.0.0/16;172.16.0.0/12\n' > /etc/pulse/default.pa.original"
        runCygwin "printf 'load-module module-esound-protocol-tcp auth-ip-acl=127.0.0.1;172.16.0.0/12\n' >> /etc/pulse/default.pa.original"
        runCygwin "printf 'load-module module-waveout sink_name=output source_name=input record=0\n' >> /etc/pulse/default.pa.original"
        runCygwin "cp /etc/pulse/default.pa.original /etc/pulse/default.pa"
        runCygwin "sed 's@; exit-idle-time = 20@exit-idle-time = -1@' -i /etc/pulse/daemon.conf"

        $service = Get-Service -Name CYGWIN-PulseAudio -ErrorAction SilentlyContinue
        if($service.Length -eq 0) {
            runCygwin "cygrunsrv -I CYGWIN-PulseAudio -p /usr/bin/pulseaudio.exe -a '--exit-idle-time=9999999999999 --realtime --disallow-exit --daemonize=no --no-cpu-limit'"
        }
        startSvc -Name "CYGWIN-PulseAudio"
        if(-not (Get-NetFirewallrule -DisplayName "PulseAudio Allow local" -ErrorAction 'silentlycontinue')) {
            New-NetFirewallRule -DisplayName "PulseAudio Allow local" -Profile @("Public") -Direction Inbound -Action Allow -Protocol TCP -LocalPort @("4713") -RemoteAddress @("10.0.0.0/16","172.16.0.0/12","192.168.0.0/16") -Program "$CygwinRoot\bin\pulseaudio.exe"
            New-NetFirewallRule -DisplayName "PulseAudio Block domain" -Profile @("Domain") -Direction Inbound -Action Block -Program "$CygwinRoot\bin\pulseaudio.exe"
            New-NetFirewallRule -DisplayName "PulseAudio Block public" -Profile @("Public") -Direction Inbound -Action Block -Program "$CygwinRoot\bin\pulseaudio.exe"
        }
    }
}

function installDbus {
    param(
        [switch]$Remove
    )
    if($Remove)
    {
        runCygwin "cygrunsrv -S CYGWIN-DbusSession"
        runCygwin "cygrunsrv -R CYGWIN-DbusSession"
        $setup = setupCygwin -Remove -Packages "dbus"
        
    } else
    {
        $setup = setupCygwin -Packages "cygrunsrv,dbus"
        $service = Get-Service -Name CYGWIN-DbusSession -ErrorAction SilentlyContinue
        if($service.Length -eq 0) {
            runCygwin "cygrunsrv -I CYGWIN-DbusSession -p /usr/bin/pulseaudio.exe -a '--exit-idle-time=9999999999999 --realtime --disallow-exit --daemonize=no --no-cpu-limit'"
        }
        startSvc -Name "CYGWIN-DbusSession"
    }
}

function installCygwinX {
    param(
        [switch]$Remove
    )
    if($Remove)
    {
        $setup = setupCygwin -Remove -Packages "xinit"
        if(-not (Get-NetFirewallrule -DisplayName "CygwinX Allow local tcp" -ErrorAction 'silentlycontinue'))
        {
            Remove-NetFirewallRule -DisplayName "CygwinX Allow local tcp"
            Remove-NetFirewallRule -DisplayName "CygwinX Allow local udp"
        }
        $service = Get-Service -Name "CYGWIN cygserver" -ErrorAction SilentlyContinue
        if($service.Length -ne 0)
        {
            sc.exe delete "CYGWIN cygserver"
        }
    } else {
        $setup = setupCygwin -Packages "xinit"
        if(-not (Get-NetFirewallrule -DisplayName "CygwinX Allow local tcp" -ErrorAction 'silentlycontinue')) {
            New-NetFirewallRule -DisplayName "CygwinX Allow local tcp" -Profile @("Public") -Direction Inbound -Action Allow -Protocol TCP -RemoteAddress @("10.0.0.0/16","172.16.0.0/12","192.168.0.0/16") -Program "$CygwinRoot\bin\XWin.exe"
            New-NetFirewallRule -DisplayName "CygwinX Allow local udp" -Profile @("Public") -Direction Inbound -Action Allow -Protocol UDP -RemoteAddress @("10.0.0.0/16","172.16.0.0/12","192.168.0.0/16") -Program "$CygwinRoot\bin\XWin.exe"
        }
        $service = Get-Service -Name "CYGWIN cygserver" -ErrorAction SilentlyContinue
        if($service.Length -eq 0) {
            runCygwin "cygserver-config --yes"
            startSvc -Name "CYGWIN cygserver"
        }
        startupShortcut -Remove -Name "X-Server"
        startupShortcut -Name "X-Server" -Target "C:\cygwin64\bin\run.exe" -Arguments "--quote /usr/bin/bash.exe -l -c 'cd; exec /usr/bin/XWin :0 -multiwindow -ac -listen tcp'" -Icon "$CygwinRoot\bin\xwin-xdg-menu.exe,0"
    }

}
function startSvc {
    param(
        [Parameter(Mandatory=$true)]
        [string] $Name
    )
    $void = sc.exe start $Name
}
function startupShortcut {
    param(
        [Parameter(Mandatory=$true)]
        [string] $Name,
        [Parameter(Mandatory=$false)]
        [string] $Target,
        [string] $Arguments = '',
        [string] $Icon = '',
        [switch] $Remove
    )
    if($Remove) {
        if(Test-Path -Path "c:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\$Name.lnk") {
            Remove-Item -Force -Path "c:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\$Name.lnk"
        }
        return
    }
    $strAllUsersProfile = [io.path]::GetFullPath($env:AllUsersProfile)
    $objShell = New-Object -com "Wscript.Shell"

    $objShortcut = $objShell.CreateShortcut("c:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\$Name.lnk")

    $objShortcut.TargetPath = $Target
    if($Arguments -ne '') {
        $objShortcut.Arguments = $Arguments
    }
    if($Icon -ne '') {
        $objShortcut.IconLocation = $Icon
    }
    $objShortcut.Save()
    $null = [System.Runtime.Interopservices.Marshal]::ReleaseComObject($objShortcut)
    $null = [System.Runtime.Interopservices.Marshal]::ReleaseComObject($objShell)
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}

if($uninstall) {
    if($GWSL) {
        installGWSL -Remove
    } else {
        installPulseaudio -Remove
        installDbus -Remove
        installCygwinX -Remove
    }
    installWsltty -Remove
    
} else {
    installWSL -Distribution $Distro
    installWsltty
    if($GWSL) {
        installGWSL 
    }else {
        installPulseaudio
        installDbus
        installCygwinX
    }
}
#$service = Get-Service -Name "CYGWIN-XWin" -ErrorAction SilentlyContinue
#if($service.Length -eq 0) {
#    runCygwin "cygrunsrv -I CYGWIN-XWin -p /usr/bin/XWin -a '127.0.0.1:0 -multiwindow -ac -listen tcp'"
#}
exit