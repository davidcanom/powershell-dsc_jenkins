# Jenkins (master) DSC script
Configuration JENKINS_CI
{
    param (
        [string] $JenkinsPort = 8080,
        $JenkinsPlugins = @{},
        [string] $JenkinsUsername = "",
        [string] $JenkinsPassword = "",
        $JenkinsXmx = 1024,
        $JenkinsMaxPermSize = 128,
        [string] $InstallConfDirectory = "./",
        [string] $JenkinsInitScriptPath = "",
        [string] $JenkinsUsernameTemplate = "_jenkinsusername_",
        [string] $JenkinsPasswordTemplate = "_jenkinspassword_"
    )
    
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'cChoco'
    Import-DscResource -ModuleName 'xNetworking'
    
    Node $AllNodes.NodeName {
        
        # Install .NET 3.5
        WindowsFeature NetFrameworkCore 
        {
            Ensure    = "Present" 
            Name      = "NET-Framework-Core"
        }

        # Install Chocolatey
        cChocoInstaller installChoco
        {
            InstallDir = "c:\choco"
            DependsOn = "[WindowsFeature]NetFrameworkCore"
        }

        # Install JDK11
        cChocoPackageInstaller installJdk11
        {
            Name = "openjdk11"
            DependsOn = "[cChocoInstaller]installChoco"
        }
        
        # Install Firefox
        cChocoPackageInstaller installFirefox
        {
            Name = "firefox"
            DependsOn = "[cChocoInstaller]installChoco"
        }
        
        # Install Git
        cChocoPackageInstaller installGit
        {
            Name = "git.install"
            DependsOn = "[cChocoInstaller]installChoco"
        }
        
        # Set Java to path
        Script SetJavaToPath 
        {
            GetScript = {
                return @{ Result = $ENV:Path }
            }
            SetScript = {
                # Try to find Java bin path and force the result to string 
                [string]$javaBinPath = gci "${Env:ProgramFiles}\OpenJDK" -r -filter java.exe | Select Directory | Select-Object -first 1 | % { $_.Directory.FullName }
                # Adds javaBinPath to path variable 
                $newPathValue = $ENV:Path + ";"+$javaBinPath
                # You might need to reset your console after this 
                [Environment]::SetEnvironmentVariable("Path", $newPathValue, [EnvironmentVariableTarget]::Machine)
                # Add also path to current session
                $ENV:Path = $newPathValue
            }
            TestScript = {
                # Try to find Java bin path and force the result to string 
                [string]$javaBinPath = gci "${Env:ProgramFiles}\OpenJDK" -r -filter java.exe | Select Directory | Select-Object -first 1 | % { $_.Directory.FullName }
                if(-not $ENV:Path.Contains($javaBinPath))
                {
                    # Do update
                    Return $False
                }
                # Don't update
                Return $True
            }
            DependsOn = "[cChocoPackageInstaller]installJdk11"
        }
        
        # Install Jenkins
        cChocoPackageInstaller installJenkins
        {
            Name = "Jenkins"
            DependsOn = "[cChocoInstaller]installChoco"
        }

        # Set JENKINS_HOME Environment Variable
        Environment JENKINS_HOME 
        {
            Ensure = "Present"
            Name = "JENKINS_HOME"
            Value = (Join-Path ${ENV:ProgramFiles(x86)} "Jenkins")
            DependsOn = "[cChocoPackageInstaller]installJenkins"
        }

        Script SetJenkinsServiceArguments
        {
            SetScript = {
                $argString = "-Xrs -Xmx"+$Using:JenkinsXmx+"m -XX:MaxPermSize="+$Using:JenkinsMaxPermSize+"m -Djenkins.install.runSetupWizard=false -Dhudson.lifecycle=hudson.lifecycle.WindowsServiceLifecycle -jar `"%BASE%\jenkins.war`" --httpPort="+$Using:JenkinsPort+" --webroot=`"%BASE%\war`""
                Write-Verbose -Verbose "Setting jenkins service arguments to $argString"
                
                $Config = Get-Content `
                    -Path "${ENV:ProgramFiles(x86)}\Jenkins\Jenkins.xml"
                $NewConfig = $Config `
                    -replace '<arguments>[\s\S]*?<\/arguments>',"<arguments>${argString}</arguments>"
                Set-Content `
                    -Path "${ENV:ProgramFiles(x86)}\Jenkins\Jenkins.xml" `
                    -Value $NewConfig `
                    -Force
                Write-Verbose -Verbose "Restarting Jenkins"
            }
            GetScript = {
                $Config = Get-Content `
                    -Path "${ENV:ProgramFiles(x86)}\Jenkins\Jenkins.xml"
                $Matches = @([regex]::matches($Config, "<arguments>[\s\S]*?<\/arguments>", 'IgnoreCase'))
                $currentMatch = $Matches.Groups[1].Value
                Return @{
                    'Result' = $currentMatch
                }
            }
            TestScript = { 
                $Config = Get-Content `
                    -Path "${ENV:ProgramFiles(x86)}\Jenkins\Jenkins.xml"
                $Matches = @([regex]::matches($Config, "<arguments>[\s\S]*?<\/arguments>", 'IgnoreCase'))
                $argString = "-Xrs -Xmx"+$Using:JenkinsXmx+"m -XX:MaxPermSize="+$Using:JenkinsMaxPermSize+"m -Djenkins.install.runSetupWizard=false -Dhudson.lifecycle=hudson.lifecycle.WindowsServiceLifecycle -jar `"%BASE%\jenkins.war`" --httpPort="+$Using:JenkinsPort+" --httpListenAddress=127.0.0.1 --webroot=`"%BASE%\war`""
                $currentMatch = $Matches.Groups[1].Value
                
                Write-Verbose "Current service arguments: $currentMatch"
                Write-Verbose "Should be service arguments: $argString"
                
                If ($argString -ne $currentMatch) {
                    # Jenkins port must be changed
                    Return $False
                }
                # Jenkins is already on correct port
                Return $True
            }
            DependsOn = "[cChocoPackageInstaller]installJenkins"
        }

        File JenkinsAuthenticationSetup
        {
            DestinationPath = $JenkinsInitScriptPath
            SourcePath = (Join-Path $InstallConfDirectory "jenkins_security_realm.groovy")
            Ensure = "Present"
            Type = "File"
            Checksum = "modifiedDate"
            Force = $true
            MatchSource = $true
            DependsOn = "[cChocoPackageInstaller]installJenkins"
        }

        Script SetJenkinsAuthenticationUsername
        {
            GetScript = {
                $isReplaceable = (get-content $Using:JenkinsInitScriptPath) | % {$_ -match $Using:JenkinsUsernameTemplate } | ? { $_ -contains $true }
                $aResult = $isReplaceable -eq $True
                Return @{
                    'Result' = $aResult
                }
            }
            SetScript = {
                $username = $Using:JenkinsUsername
                (Get-Content $Using:JenkinsInitScriptPath).Replace($Using:JenkinsUsernameTemplate,$username) | Set-Content $Using:JenkinsInitScriptPath
            }
            TestScript = {
                $isReplaceable = (get-content $Using:JenkinsInitScriptPath) | % {$_ -match $Using:JenkinsUsernameTemplate } | ? { $_ -contains $true }
                if($isReplaceable -eq $True)
                {
                    # needs configuration
                    Return $False
                }
                Return $True
            }
        }

        Script SetJenkinsAuthenticationPassword
        {
            GetScript = {
                $isReplaceable = (get-content $Using:JenkinsInitScriptPath) | % {$_ -match $Using:JenkinsPasswordTemplate } | ? { $_ -contains $true }
                $aResult = $isReplaceable -eq $True
                Return @{
                    'Result' = $aResult
                }
            }
            SetScript = {
                $password = $Using:JenkinsPassword
                (Get-Content $Using:JenkinsInitScriptPath).Replace($Using:JenkinsPasswordTemplate,$password) | Set-Content $Using:JenkinsInitScriptPath 
            }
            TestScript = {
                $isReplaceable = (get-content $Using:JenkinsInitScriptPath) | % {$_ -match $Using:JenkinsPasswordTemplate } | ? { $_ -contains $true }
                if($isReplaceable -eq $True)
                {
                    # needs configuration
                    Return $False
                }
                Return $True
            }
        }

        Service JenkinsService
        {
            Name        = "Jenkins"
            StartupType = "Automatic"
            State       = "Running"
            DependsOn = "[cChocoPackageInstaller]installJenkins","[Script]SetJenkinsServiceArguments","[File]JenkinsAuthenticationSetup","[Script]SetJenkinsAuthenticationUsername","[Script]SetJenkinsAuthenticationPassword"
        }

        File JenkinsPluginsFile
        {
            DestinationPath = (Join-Path ${ENV:JENKINS_HOME} "jenkins_plugins.txt")
            SourcePath = (Join-Path $InstallConfDirectory "jenkins_plugins.txt")
            Ensure = "Present"
            Type = "File"
            Checksum = "modifiedDate"
            Force = $true
            MatchSource = $true
            DependsOn = "[cChocoPackageInstaller]installJenkins"
        }

        Script InstallJenkinsPlugins
        {
            GetScript = {
                Return @{ Result = Get-ChildItem "${ENV:ProgramFiles(x86)}\Jenkins\plugins" | Select Name }
            }
            SetScript = {
                $plugins = $Using:JenkinsPlugins
                $port = $Using:JenkinsPort
                $password = $Using:JenkinsPassword
                $username = $Using:JenkinsUsername
                
                # Make sure that Jenkins is in the configurated state
                Restart-Service -Name Jenkins
                Start-Sleep -s 15
                
                # Wait a bit for Jenkins to get online 
                $request = [system.Net.WebRequest]::Create("http://localhost:${port}")
                for ($i = 1; $i -le 10; $i++) {
                    try {
                           $result = $request.GetResponse()
                    } catch [System.Net.WebException] {
                           $result = $_.Exception.Response
                    }
                    
                    if ($result -is "System.Net.HttpWebResponse" -and $result.StatusCode -ne "") {
                        $done = "Got status"
                        break
                    }
                    
                    Write-Host "Get status attempt number $($i) failed. Retrying..."
                    Start-Sleep -s 5
                }
                
                # Install plugins
                
                foreach ($jplug in $plugins) {
                    Write-Verbose "installing $jplug"
                    java -jar ${ENV:ProgramFiles(x86)}\Jenkins\war\WEB-INF\jenkins-cli.jar  -s "http://localhost:${port}" -auth "${username}:${password}" install-plugin $jplug
                    # Wait a bit, Jenkins is kind of slow 
                    Start-Sleep -s 5
                }
                Write-Verbose -Verbose "Restarting Jenkins"
                Restart-Service `
                    -Name Jenkins
            }
            TestScript = {
                # Sanity check to bypass weird folder does not exist problem
                if(!(Test-Path "${ENV:ProgramFiles(x86)}\Jenkins\plugins"))
                {
                    Return $False
                }
                # Check if there are plugins
                $directoryInfo = Get-ChildItem "${ENV:ProgramFiles(x86)}\Jenkins\plugins" | Measure-Object
                # Directory is empty, do the update
                if ($directoryInfo.Count -eq 0) {
                    Return $False
                }
                # Do not make update 
                Return $True
            }
            DependsOn = "[cChocoPackageInstaller]installJenkins","[Script]SetJenkinsServiceArguments","[File]JenkinsAuthenticationSetup","[Service]JenkinsService","[Script]SetJenkinsAuthenticationUsername","[Script]SetJenkinsAuthenticationPassword"
        }
    }
}

$ConfigData = @{
    AllNodes = 
    @(
        @{
            NodeName = "LocalHost"
            PSDscAllowPlainTextPassword = $true
        }
    )
}

# Set WSMan envelope size bigger
Set-WSManInstance -ValueSet @{MaxEnvelopeSizekb = "2000"} -ResourceURI winrm/config

$currentPath = (split-path -parent $MyInvocation.MyCommand.Definition)
$jenkinsusername = Read-Host "Give username for jenkins_user"
$securepwd = Read-Host -AsSecureString "Give password for jenkins_user"
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securepwd)
$jenkinspassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
$jenkinsInitScript = "${ENV:ProgramFiles(x86)}\Jenkins\init.groovy.d\jenkins_security_realm.groovy"
# Start the actual jenkins configuration
$jenkinsPlugins = Get-Content .\jenkins_plugins.txt

JENKINS_CI `
    -InstallConfDirectory $currentPath `
    -ConfigurationData $ConfigData `
    -JenkinsPort 8080 `
    -JenkinsPlugins $jenkinsPlugins `
    -JenkinsUsername $jenkinsusername `
    -JenkinsPassword $jenkinspassword `
    -JenkinsInitScriptPath $jenkinsInitScript

Start-DscConfiguration -Path .\JENKINS_CI -Wait -Verbose -Force