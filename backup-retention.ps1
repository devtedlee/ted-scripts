# execute example
# Execute this code at Admin PowerShell
# Set-ExecutionPolicy RemoteSigned
# .\backup-retention.ps1 -gitRepoUrls @("https://github.com/myusername/myrepo.git", "https://github.com/myusername/myotherrepo.git") -retentionDays 30 -backupExpiredYears 1 -awsBucketName {bucketName} -awsAccessKey {accessKey} -awsSecretKey {secretKey} -backupRootDir "C:\backups"

# Parse command line arguments
param (
    [string[]]$gitRepoUrls,
    [int]$retentionDays,
    [int]$backupExpiredYears,
    [string]$awsBucketName, # optional
    [string]$awsAccessKey, # optional
    [string]$awsSecretKey, # optional
    [string]$commandAbsPath = "powershell.exe",
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

# Function to clean up old backup files
function clean_up_files {
    param (
        [string]$rootDir,
        [int]$expiredYears
    )

    # Move to backup directory
    Set-Location $rootDir -ErrorAction Stop

    # Create a new directory with today's date
    $backupFolder = Get-Date -Format "yyyy-MM-dd"
    New-Item $backupFolder -ItemType Directory | Out-Null

    # Move all zip files to the new directory
    Move-Item *.zip $backupFolder

    # Remove directories older than backupExpiredYears
    Get-ChildItem -Path . -Directory -Filter "20*" | Where-Object {$_.LastWriteTime -lt (Get-Date).AddYears(-$expiredYears)} | Remove-Item -Recurse -Force
}

function upload_files_to_s3 {
    param (
        [string]$rootDir,
        [string]$bucketName,
        [string]$accessKey,
        [string]$secretKey
    )

    # Check if the AWSPowerShell module is installed
    if (Get-Module -ListAvailable -Name AWSPowerShell) {
        Write-Output "AWS Tools for PowerShell is already installed."
    } else {
        # Install the AWSPowerShell module
        Install-Module -Name AWSPowerShell -Scope CurrentUser -Force
        Write-Output "AWS Tools for PowerShell installed successfully."
    }

    # Import the AWSPowerShell module
    Import-Module AWSPowerShell

    # Set the AWS credentials
    Set-AWSCredentials -AccessKey $accessKey -SecretKey $secretKey

    # Set the AWS region
    Set-DefaultAWSRegion -Region "ap-northeast-2"

    # Move to backup directory
    Set-Location $rootDir -ErrorAction Stop

    # Get the name of the backup directory
    $backupDir = Get-Date -Format "yyyy-MM-dd"

    # Upload the directory and its contents to S3
    $objects = Get-ChildItem -Path $backupDir -Recurse
    foreach ($object in $objects) {
        Write-S3Object -BucketName $bucketName -Key $object.FullName.Replace($rootDir, "").TrimStart("\") -File $object.FullName  -ErrorAction Stop
    }

    Write-Output "Upload completed successfully."
}

# Create backups root directory if it doesn't exist
create_directory_if_not_exists $backupRootDir

# Move to backup root directory
cd $backupRootDir

# Clone each Git repository URL and create a backup archive
foreach ($gitRepoUrl in $gitRepoUrls) {	
    # Clone the repository
    git.exe clone -v --depth 1 $gitRepoUrl

    # Get the name of the repository
    $repoName = ($gitRepoUrl -split "/" | Select-Object -Last 1).Replace(".git", "")

    create_directory_if_not_exists "./$repoName"

    # Zip the repository folder
    Compress-Archive -Path $repoName -CompressionLevel Optimal -DestinationPath "$repoName.zip"

    # Remove the cloned repository folder
    Remove-Item -Recurse -Force $repoName
}

# Move to backup directory
Set-Location $backupRootDir -ErrorAction Stop

# Clean up old backup files
clean_up_files $backupRootDir $backupExpiredYears

# If AWS credentials are provided, upload the backup files to S3
if ($awsBucketName -and $awsAccessKey -and $awsSecretKey) {
    Write-Output "AWS credentials provided."
    upload_files_to_s3 $backupRootDir $awsBucketName $awsAccessKey $awsSecretKey
}

# Set the name of the scheduler
$schedulerName = "BackupRetentionTask"

# Check if scheduler already exists
if (Get-ScheduledTask -TaskName $schedulerName -ErrorAction SilentlyContinue) {
    Write-Output "Task Scheduler '$schedulerName' already exists. Skipping creation."
} else {
    $gitRepoUrlsArg = @($gitRepoUrls)
    $gitRepoUrlsArg = $gitRepoUrlsArg -join "', '"
    $schedulerActionArguments = "-ExecutionPolicy Bypass -Command `"& $PSScriptRoot\backup-retention.ps1 -gitRepoUrls @('$gitRepoUrlsArg') -retentionDays $retentionDays -backupExpiredYears $backupExpiredYears -backupRootDir '$backupRootDir'"

    if ($awsBucketName -and $awsAccessKey -and $awsSecretKey) {
        $schedulerActionArguments += " -awsBucketName '$awsBucketName' -awsAccessKey '$awsAccessKey' -awsSecretKey '$awsSecretKey'"
    }

    $schedulerAction = New-ScheduledTaskAction -Execute $commandAbsPath -Argument $schedulerActionArguments
    $schedulerTrigger = New-ScheduledTaskTrigger -Daily -DaysInterval $retentionDays -At "00:00"
    $schedulerSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $schedulerPrincipal = New-ScheduledTaskPrincipal -UserID "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $schedulerTask = New-ScheduledTask -Action $schedulerAction -Trigger $schedulerTrigger -Settings $schedulerSettings -Principal $schedulerPrincipal

    Register-ScheduledTask -TaskName $schedulerName -InputObject $schedulerTask -Force
    Write-Output "Task Scheduler '$schedulerName' created successfully."
	
	# set git command at path for SYSTEM account
	$currentPath = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).Path
	$newPath = $currentPath + ";C:\Program Files\Git\bin"
	Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name PATH -Value $newPath
}
