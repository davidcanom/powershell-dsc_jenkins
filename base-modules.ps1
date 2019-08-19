# PowerShell installation of DSC resources
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module cChoco -f
Install-Module xNetworking -f