#!/bin/bash

# Command execute example
# ./backup-retention.sh --git-repo-urls "https://{username}:{passowrd}@github.com/myusername/myrepo.git" "https://{personal_access_token}@github.com/myusername/myotherrepo.git" --retention-days 30 --backup-expired-years 1

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --git-repo-urls) git_repo_urls=("$2"); shift ;;
        --retention-days) retention_days="$2"; shift ;;
        --backup-expired-years) backup_expired_years="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Validate required command line arguments
if [[ -z "$git_repo_urls" ]]; then
    echo "Please provide at least one Git repository URL with --git-repo-urls."
    exit 1
fi

if [[ -z "$retention_days" ]]; then
    echo "Please provide a retention period in days with --retention-days."
    exit 1
fi

if [[ -z "$backup_expired_years" ]]; then
    echo "Please provide a backup expired period in years with --backup-expired-years."
    exit 1
fi

# Function to clean up old backup files
function clean_up_files {
    # Create a new directory with today's date
    backup_dir=$(date '+%Y-%m-%d')
    mkdir "$backup_dir"

    # Move all tar.gz files to the new directory
    mv *.tar.gz "$backup_dir"

    # Remove directories older than backup_expired_years
    find . -maxdepth 1 -type d -name "20*" -mtime +"$((backup_expired_years*365))" -exec rm -rf {} \;
}

# Clone each Git repository URL and create a backup archive
for git_repo_url in "${git_repo_urls[@]}"; do
    # Clone the repository
    git clone --depth 1 "$git_repo_url" || exit 1

    # Get the name of the repository
    repo_name=$(echo "$git_repo_url" | sed 's/.*\///' | sed 's/\.git//')

    # Zip the repository folder
    tar -czvf "${repo_name}.tar.gz" "$repo_name" || exit 1

    # Remove the unzipped repository folder
    rm -rf "$repo_name" || exit 1
done

# Clean up old backup files
clean_up_files

# Define and start Ubuntu service
systemctl start backup-retention.service

# Set retention date
systemctl --now set-property backup-retention.service 'TimeoutStopSec' "${retention_days}s"
