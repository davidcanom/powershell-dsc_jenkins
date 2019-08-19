$ScriptLocation = "base-modules.ps1"
Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File $ScriptLocation" -NoNewWindow -Wait

$ScriptLocation = "dsc_jenkins-master.ps1"
Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File $ScriptLocation" -NoNewWindow -Wait