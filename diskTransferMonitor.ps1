# Configuration
$logDirectory = "C:\Users\wez04\Desktop\start\Scripts"
$logFile = "$logDirectory\DiskSpeedsLog.txt"
$statusFile = "$logDirectory\DiskTransferStatus.txt"
$emailFrom = "wez0421@gmail.com"
$emailTo = "wez0421@gmail.com"
$smtpServer = "smtp.gmail.com"
$smtpPort = 587 # Adjust if needed
$smtpUsername = "wez0421@gmail.com"
$smtpPassword = "foew uvcw nsoo bmau" # Plain text password
$intervalMinutes = 5 # Set the interval in minutes

# Ensure directories exist
if (-not (Test-Path -Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory -Force
}

# Function to get disk read and write speeds
function Get-DiskReadWriteSpeeds {
    $diskSpeeds = @()

    $perfCounters = @(
        '\PhysicalDisk(*)\Disk Read Bytes/sec',
        '\PhysicalDisk(*)\Disk Write Bytes/sec'
    )

    $readCounters = Get-Counter -Counter $perfCounters[0] -ErrorAction SilentlyContinue
    $writeCounters = Get-Counter -Counter $perfCounters[1] -ErrorAction SilentlyContinue

    for ($i = 0; $i -lt $readCounters.CounterSamples.Count; $i++) {
        $diskName = $readCounters.CounterSamples[$i].InstanceName
        $readSpeed = $readCounters.CounterSamples[$i].CookedValue
        $writeSpeed = $writeCounters.CounterSamples[$i].CookedValue

        $diskSpeed = [PSCustomObject]@{
            Disk       = $diskName
            ReadSpeed  = $readSpeed / 1MB
            WriteSpeed = $writeSpeed / 1MB
        }

        $diskSpeeds += $diskSpeed
    }

    return $diskSpeeds
}

# Function to send email
function Send-Email {
    param (
        [string]$subject,
        [string]$body
    )
    try {
        $smtpCredential = New-Object System.Management.Automation.PSCredential ($smtpUsername, (ConvertTo-SecureString $smtpPassword -AsPlainText -Force))
        Send-MailMessage -From $emailFrom -To $emailTo -Subject $subject -Body $body -SmtpServer $smtpServer -Port $smtpPort -Credential $smtpCredential -UseSsl
        Write-Output "Email sent successfully: $subject"
        return $true
    } catch {
        Write-Output "Failed to send email: $_"
        return $false
    }
}

# Function to display and log disk read and write speeds
function Display-AndLog-DiskReadWriteSpeeds {
    $speeds = Get-DiskReadWriteSpeeds
    $output = "Disk Read and Write Speeds at $(Get-Date):`n"
    $output += "---------------------------------------`n"
    $highSpeedDetected = $false
    $highSpeedDisks = @()

    foreach ($speed in $speeds) {
        $output += ("Disk: {0}, Read Speed: {1:N2} MB/s, Write Speed: {2:N2} MB/s" -f $speed.Disk, $speed.ReadSpeed, $speed.WriteSpeed) + "`n"
        
        # Check if read or write speed exceeds 10 MB/s
        if ($speed.ReadSpeed -gt 10 -or $speed.WriteSpeed -gt 10) {
            $highSpeedDetected = $true
            $highSpeedDisks += $speed
        }
    }

    $output | Out-File -Append -FilePath $logFile

    return @{Detected=$highSpeedDetected; Disks=$highSpeedDisks}
}

# Main script logic
while ($true) {
    $result = Display-AndLog-DiskReadWriteSpeeds
    $highSpeedDetected = $result.Detected
    $highSpeedDisks = $result.Disks

    # Read previous status
    if (Test-Path $statusFile) {
        $previousStatus = [int](Get-Content $statusFile -Raw)
    } else {
        $previousStatus = 0
    }

    # Ensure previousStatus is trimmed and treated as a string
    

    # Log the current and previous status
    Write-Output "Previous Status: '$previousStatus'"
    Write-Output "High Speed Detected: $highSpeedDetected"

    # Update status and send email if needed
    if ($highSpeedDetected) {
        Write-Output "High speed detected on disks: $($highSpeedDisks.Disk -join ', ')"
        Write-Output "Previous Status: '$previousStatus'"
        if ($previousStatus -eq "0") {
            $body = "A disk transfer exceeding 10 MB/s has been detected on the following disks:`n"
            foreach ($disk in $highSpeedDisks) {
                $body += "Disk: $($disk.Disk), Read Speed: $([math]::Round($disk.ReadSpeed, 2)) MB/s, Write Speed: $([math]::Round($disk.WriteSpeed, 2)) MB/s`n"
            }
            Write-Output "Sending '[CIH4Q2I ALERT] Disk Transfer Started' email."
            Send-Email -Subject "[CIH4Q2I ALERT] Disk Transfer Started on $($highSpeedDisks.Disk -join ', ')" -Body $body
        }
        Set-Content -Path $statusFile -Value "1"
    } else {
        Write-Output "No high speed detected."
        if ($previousStatus -eq "1") {
            Write-Output "Setting status to 2 (first cycle of low speed)."
            Set-Content -Path $statusFile -Value "2"
        } elseif ($previousStatus -eq "2") {
            Write-Output "Sending '[CIH4Q2I ALERT] Disk Transfer Completed' email."
            if (Send-Email -Subject "[CIH4Q2I ALERT] Disk Transfer Completed" -Body "Disk transfer speeds have been below 10 MB/s for two consecutive cycles. Transfer is complete.") {
                Write-Output "Email '[CIH4Q2I ALERT] Disk Transfer Completed' sent."
            } else {
                Write-Output "Email '[CIH4Q2I ALERT] Disk Transfer Completed' failed to send."
            }
            Set-Content -Path $statusFile -Value "0"
        } else {
            Write-Output "Setting status to 0 (no transfer activity)."
            Set-Content -Path $statusFile -Value "0"
        }
    }

    # Log the new status
    Write-Output "Current Status: $(Get-Content $statusFile -Raw)"

    # Calculate and print the next run time
    if ($previousStatus -eq "2" -or $previousStatus -eq "0") {
        $nextRunTime = (Get-Date).AddMinutes(1)
        Write-Output "Next message will be printed at: $nextRunTime (1 minute due to status $previousStatus)"
        Start-Sleep -Seconds 60
    } else {
        $nextRunTime = (Get-Date).AddMinutes($intervalMinutes)
        Write-Output "Next message will be printed at: $nextRunTime"
        Start-Sleep -Seconds ($intervalMinutes * 60)
    }
}
