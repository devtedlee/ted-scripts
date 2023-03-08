#!/bin/bash

# !! this code is not tested, please use this before code fix !!
# execute example:
# chmod +x backup-retention.sh
# ./backup-retention.sh --retentionDays 7 --backupExpiredYears 2 --backupRootDir /backups --gitRepoUrls https://github.com/username1/repo1 https://github.com/username2/repo2

# Define default values
retentionDays=30
backupExpiredYears=1
backupRootDir=/backups

# Parse named command line arguments
while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        -r|--retentionDays)
        retentionDays="$2"
        shift
        shift
        ;;
        -b|--backupExpiredYears)
        backupExpiredYears="$2"
        shift
        shift
        ;;
        -d|--backupRootDir)
        backupRootDir="$2"
        shift
        shift
        ;;
        -g|--gitRepoUrls)
        shift
        gitRepoUrls=("$@")
        break
        ;;
        *)
        echo "Unknown argument: $1"
        exit 1
        ;;
    esac
done

# Validate required command line arguments
if [ -z "${gitRepoUrls}" ]; then
    echo "Please provide at least one Git repository URL with -g or --gitRepoUrls."
    exit 1
fi

if [ -z "${retentionDays}" ]; then
    echo "Please provide a retention period in days with -r or --retentionDays."
    exit 1
fi

if [ -z "${backupExpiredYears}" ]; then
    echo "Please provide a backup expired period in years with -b or --backupExpiredYears."
    exit 1
fi

function create_directory_if_not_exists {
    directoryName=$1

    if [ ! -d "${directoryName}" ]; then
        echo "Creating directory: ${directoryName}"
        mkdir -p "${directoryName}"
    fi
}

# Create backups root directory if it doesn't exist
create_directory_if_not_exists "${backupRootDir}"

# Move to backup directory
cd "${backupRootDir}" || exit

# Function to clean up old backup files
function clean_up_files {

    # Move to backup directory
    cd "${backupRootDir}" || exit

    # Create a new directory with today's date
    backupDir=$(date +%Y-%m-%d)
    mkdir "${backupDir}"

    # Move all tar.gz files to the new directory
    mv *.tar.gz "${backupDir}"

    # Remove directories older than backupExpiredYears
    find . -type d -name "20*" -mtime +$((365*backupExpiredYears)) -exec rm -rf {} \;
}

# Clone each Git repository URL and create a backup archive
for gitRepoUrl in "${gitRepoUrls[@]}"
do
    # Clone the repository
    git clone --depth 1 "${gitRepoUrl}"

    # Get the name of the repository
    repoName=$(echo "${gitRepoUrl}" | awk -F'/' '{print $NF}' | sed 's/\.git$//')

    create_directory_if_not_exists "./${repoName}"

    # Tar and gzip the repository folder
    tar -zcvf "${repoName}.tar.gz" "${repoName}"

    # Remove the cloned repository folder
    rm -rf "${repoName}"
done

# Clean up old backup files
clean_up_files

# Create cron job for backup-retention.sh
if ! crontab -l | grep -q "${backupRootDir}/backup-retention.sh"; then
  (crontab -l 2>/dev/null; echo "0 0 */${retentionDays} * * $(which bash) $(pwd)/backup-retention.sh -g ${gitRepoUrls[*]} -r '${retentionDays}' -b '${backupExpiredYears}' -d '${backupRootDir}'") | sort -u | crontab -
  echo "Cron job created or updated successfully."
fi
