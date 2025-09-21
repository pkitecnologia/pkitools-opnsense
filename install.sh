#!/bin/sh

# PKITools-Monitor Package Manager
# Downloads and manages PKI monitoring scripts from GitHub
# Silent operation - only returns exit codes: 0 = success, 1 = error
# Logs detailed output to /pkitools/downloader.log

# Configuration
PKITOOLS_DIR="/pkitools"
SCRIPTS_DIR="$PKITOOLS_DIR/scripts"
VERSION_FILE="$PKITOOLS_DIR/version.txt"
LOG_FILE="$PKITOOLS_DIR/downloader.log"
LOCK_FILE="$PKITOOLS_DIR/downloader.lock"
LOCK_TIMEOUT=300  # 5 minutes max lock age

# Base URL for GitHub raw content (to be set when script is downloaded)
# This will be set dynamically based on the script's source URL
BASE_URL=""

# Function to log messages with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to exit with proper cleanup
exit_with_code() {
    local code=$1
    log "Exiting with code: $code"
    # Remove lock file if we created it
    if [ -f "$LOCK_FILE" ] && [ "$(cat "$LOCK_FILE" 2>/dev/null)" = "$$" ]; then
        rm -f "$LOCK_FILE" 2>/dev/null
        log "Released lock file"
    fi
    exit $code
}

# Function to acquire execution lock
acquire_lock() {
    local current_time=$(date +%s)
    
    # Check if lock file exists
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        local lock_time=$(stat -f %m "$LOCK_FILE" 2>/dev/null || stat -c %Y "$LOCK_FILE" 2>/dev/null || echo "0")
        
        # Check if lock is stale (older than LOCK_TIMEOUT)
        if [ $((current_time - lock_time)) -gt $LOCK_TIMEOUT ]; then
            log "Removing stale lock file (older than $LOCK_TIMEOUT seconds)"
            rm -f "$LOCK_FILE" 2>/dev/null
        else
            # Check if the process is still running
            if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
                log "ERROR: Another instance is already running (PID: $lock_pid)"
                exit_with_code 1
            else
                log "Removing orphaned lock file (process $lock_pid not running)"
                rm -f "$LOCK_FILE" 2>/dev/null
            fi
        fi
    fi
    
    # Create lock file with our PID
    if echo "$$" > "$LOCK_FILE" 2>/dev/null; then
        log "Acquired execution lock (PID: $$)"
        return 0
    else
        log "ERROR: Failed to create lock file"
        exit_with_code 1
    fi
}

# Function to detect download tool
get_download_tool() {
    if command -v curl >/dev/null 2>&1; then
        echo "curl"
    elif command -v fetch >/dev/null 2>&1; then
        echo "fetch"
    else
        log "ERROR: Neither fetch nor curl found"
        return 1
    fi
}

# Function to download a file with timeouts and retries
download_file() {
    local url="$1"
    local output="$2"
    local tool="$3"
    
    log "Downloading: $url -> $output"
    
    case "$tool" in
        "fetch")
            # FreeBSD fetch with timeout (10s connect, 60s total, 3 retries)
            if fetch -q -T 10 -w 60 -a -o "$output" "$url" >/dev/null 2>&1; then
                log "SUCCESS: Downloaded $url"
                return 0
            else
                log "ERROR: Failed to download $url with fetch"
                return 1
            fi
            ;;
        "curl")
            # curl with comprehensive timeout and retry settings
            if curl -fsSL --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 2 \
                   -o "$output" "$url" >/dev/null 2>&1; then
                log "SUCCESS: Downloaded $url"
                return 0
            else
                log "ERROR: Failed to download $url with curl"
                return 1
            fi
            ;;
        *)
            log "ERROR: Unknown download tool: $tool"
            return 1
            ;;
    esac
}

# Function to determine base URL from script source
determine_base_url() {
    # Set default branch if V is not defined
    if [ -z "$V" ]; then
        V="main"
        log "V variable not set, using default branch: main"
    else
        log "Using branch from V variable: $V"
    fi
    
    # If BASE_URL is already set via environment, use it
    if [ -n "$PKITOOLS_BASE_URL" ]; then
        BASE_URL="$PKITOOLS_BASE_URL"
        log "Using base URL from environment: $BASE_URL"
        return 0
    fi
    
    # Try to extract from the curl command that invoked this script
    # This is a fallback - ideally BASE_URL should be set via environment
    if [ -n "$0" ] && echo "$0" | grep -q "https://"; then
        # Extract base URL from script path and replace branch with V
        BASE_URL=$(echo "$0" | sed "s|/[^/]*$||" | sed "s|/[^/]*$|/$V|")
        log "Extracted base URL from script path: $BASE_URL"
    else
        # Use the default repository with the V branch
        BASE_URL="https://raw.githubusercontent.com/pkitecnologia/pkitools-opnsense/$V"
        log "Using default base URL with branch $V: $BASE_URL"
    fi
}

# Main execution starts here
{
    # Create directories FIRST (before any logging or lock operations)
    if ! mkdir -p "$PKITOOLS_DIR" "$SCRIPTS_DIR" 2>/dev/null; then
        # Can't log yet since directory doesn't exist, just exit with error code
        exit 1
    fi
    
    # NOW initialize log file (directory exists)
    echo "PKITools-Monitor Download Log - $(date)" > "$LOG_FILE"
    log "Starting PKITools-Monitor package manager"
    log "Created directory structure: $PKITOOLS_DIR"
    
    # Acquire execution lock to prevent overlapping runs
    acquire_lock
    
    # Determine base URL
    determine_base_url
    
    # Detect download tool
    DOWNLOAD_TOOL=$(get_download_tool)
    if [ $? -ne 0 ]; then
        exit_with_code 1
    fi
    log "Using download tool: $DOWNLOAD_TOOL"
    
    # Download remote version file
    REMOTE_VERSION_URL="$BASE_URL/version.txt"
    TEMP_VERSION="/tmp/pkitools-remote-version.txt"
    
    log "Fetching remote version from: $REMOTE_VERSION_URL"
    if ! download_file "$REMOTE_VERSION_URL" "$TEMP_VERSION" "$DOWNLOAD_TOOL"; then
        log "ERROR: Failed to download remote version file"
        exit_with_code 1
    fi
    
    # Read remote version
    if [ -r "$TEMP_VERSION" ]; then
        REMOTE_VERSION=$(cat "$TEMP_VERSION" 2>/dev/null | tr -d '\n\r ')
        log "Remote version: '$REMOTE_VERSION'"
    else
        log "ERROR: Cannot read remote version file"
        rm -f "$TEMP_VERSION"
        exit_with_code 1
    fi
    
    # Read local version if exists
    LOCAL_VERSION=""
    if [ -r "$VERSION_FILE" ]; then
        LOCAL_VERSION=$(cat "$VERSION_FILE" 2>/dev/null | tr -d '\n\r ')
        log "Local version: '$LOCAL_VERSION'"
    else
        log "No local version file found"
    fi
    
    # Compare versions
    if [ "$REMOTE_VERSION" = "$LOCAL_VERSION" ] && [ -n "$LOCAL_VERSION" ]; then
        log "Versions match, no update needed"
        rm -f "$TEMP_VERSION"
        exit_with_code 0
    fi
    
    log "Version mismatch or no local version, proceeding with update"
    
    # Download manifest
    MANIFEST_URL="$BASE_URL/manifest.txt"
    TEMP_MANIFEST="/tmp/pkitools-manifest.txt"
    
    log "Downloading manifest from: $MANIFEST_URL"
    if ! download_file "$MANIFEST_URL" "$TEMP_MANIFEST" "$DOWNLOAD_TOOL"; then
        log "ERROR: Failed to download manifest"
        rm -f "$TEMP_VERSION" "$TEMP_MANIFEST"
        exit_with_code 1
    fi
    
    # Process manifest and download scripts
    log "Processing manifest and downloading scripts"
    while IFS=' ' read -r script_filename zabbix_item_name || [ -n "$script_filename" ]; do
        # Skip empty lines and comments
        case "$script_filename" in
            ''|'#'*) continue ;;
        esac
        
        if [ -z "$zabbix_item_name" ]; then
            log "ERROR: Invalid manifest line: '$script_filename' (missing zabbix item name)"
            continue
        fi
        
        # Construct script URL from base URL (security: only download from our repository)
        script_url="$BASE_URL/scripts/$script_filename"
        script_path="$SCRIPTS_DIR/$script_filename"
        
        log "Processing: $script_filename -> $zabbix_item_name"
        
        # Download script
        if download_file "$script_url" "$script_path" "$DOWNLOAD_TOOL"; then
            # Make script executable
            if chmod +x "$script_path" 2>/dev/null; then
                log "SUCCESS: Made $script_filename executable (zabbix item: $zabbix_item_name)"
            else
                log "WARNING: Failed to make $script_filename executable"
            fi
        else
            log "ERROR: Failed to download $script_filename from $script_url"
            rm -f "$TEMP_VERSION" "$TEMP_MANIFEST"
            exit_with_code 1
        fi
    done < "$TEMP_MANIFEST"
    
    # Update local version file
    if echo "$REMOTE_VERSION" > "$VERSION_FILE" 2>/dev/null; then
        log "SUCCESS: Updated local version to $REMOTE_VERSION"
    else
        log "ERROR: Failed to update local version file"
        rm -f "$TEMP_VERSION" "$TEMP_MANIFEST"
        exit_with_code 1
    fi
    
    # Cleanup
    rm -f "$TEMP_VERSION" "$TEMP_MANIFEST"
    log "Update completed successfully"
    
    exit_with_code 0
    
} 2>&1
