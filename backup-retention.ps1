# execute example
# Execute this code at Admin PowerShell
# Set-ExecutionPolicy RemoteSigned
# .\backup-retention.ps1 -gitRepoUrls @("https://github.com/myusername/myrepo.git", "https://github.com/myusername/myotherrepo.git") -retentionDays 30 -backupExpiredYears 1 -backupRootDir "C:\backups"

# Parse command line arguments
param (
    [string[]]$gitRepoUrls,
    [int]$retentionDays,
    [int]$backupExpiredYears,
    [string]$backupRootDir = "C:\backups"
)

# Validate required command line arguments
if (!$gitRepoUrls) {
    Write-Error "Please provide at least one Git repository URL with -gitRepoUrls."
    exit 1
}

if (!$retentionDays) {
    Write-Error "Please provide a retention period in days with -retentionDays."
    exit 1
}

if (!$backupExpiredYears) {
    Write-Error "Please provide a backup expired period in years with -backupExpiredYears."
    exit 1
}


function create_directory_if_not_exists {
    param (
        [string]$directoryName
    )

    if(-not (Test-Path -Path $directoryName -PathType Container)) {
        Write-Output "Creating directory: $directoryName"
        New-Item -ItemType Directory -Force -Path $directoryName | Out-Null
    }
}

# Create backups root directory if it doesn't exist
create_directory_if_not_exists($backupRootDir)

# Move to backup directory
Set-Location $backupRootDir -ErrorAction Stop

# Function to clean up old backup files
function clean_up_files {

    # Move to backup directory
    Set-Location $backupRootDir -ErrorAction Stop

    # Create a new directory with today's date
    $backupDir = Get-Date -Format "yyyy-MM-dd"
    New-Item $backupDir -ItemType Directory | Out-Null

    # Move all zip files to the new directory
    Move-Item *.zip $backupDir

    # Remove directories older than backupExpiredYears
    Get-ChildItem -Path . -Directory -Filter "20*" | Where-Object {$_.LastWriteTime -lt (Get-Date).AddYears(-$backupExpiredYears)} | Remove-Item -Recurse -Force
}

# Clone each Git repository URL and create a backup archive
foreach ($gitRepoUrl in $gitRepoUrls) {
    # Clone the repository
    git clone --depth 1 $gitRepoUrl

    # Get the name of the repository
    $repoName = ($gitRepoUrl -split "/" | Select-Object -Last 1).Replace(".git", "")

    create_directory_if_not_exists("./$repoName")

    # Zip the repository folder
    Compress-Archive -Path $repoName -CompressionLevel Optimal -DestinationPath "$repoName.zip"

    # Remove the cloned repository folder
    Remove-Item -Recurse -Force $repoName
}

# Clean up old backup files
clean_up_files

# Create task scheduler for backup-retention service start
$schedulerName = "BackupRetentionTask"
$schedulerDescription = "Runs the backup retention service"
$schedulerAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$PSScriptRoot\backup-retention.ps1`" -gitRepoUrls $gitRepoUrls -retentionDays $retentionDays -backupExpiredYears $backupExpiredYears -backupRootDir $backupRootDir"
$schedulerTrigger = New-ScheduledTaskTrigger -Daily -DaysInterval $retentionDays -At "00:00"
$schedulerSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$schedulerPrincipal = New-ScheduledTaskPrincipal -UserID "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$schedulerOptions = New-ScheduledTask -Action $schedulerAction -Trigger $schedulerTrigger -Settings $schedulerSettings -Principal $schedulerPrincipal

# Check if scheduler already exists
if (Get-ScheduledTask -TaskName $schedulerName -ErrorAction SilentlyContinue) {
    Write-Output "Task Scheduler '$schedulerName' already exists. Skipping creation."
} else {
    # Create the scheduler
    Register-ScheduledTask -TaskName $schedulerName -Action $schedulerAction -Trigger $schedulerTrigger -Settings $schedulerSettings -Principal $schedulerPrincipal
    Write-Output "Task Scheduler '$schedulerName' created successfully."
}
