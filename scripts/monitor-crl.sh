#!/bin/sh

# PKI Certificate Revocation List (CRL) Monitor
# Monitors CRL freshness and validates CRL signatures

# Configuration
CRL_DIR="/etc/ssl/crl"
CRL_URLS_FILE="/pkitools/etc/crl-urls.txt"
MAX_AGE_HOURS=24
LOG_FILE="/pkitools/logs/crl-monitor.log"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to check CRL freshness
check_crl_freshness() {
    local crl_file="$1"
    local crl_name=$(basename "$crl_file")
    
    if [ ! -f "$crl_file" ]; then
        log "ERROR: CRL file $crl_name not found"
        return 1
    fi
    
    # Get CRL next update time
    if command -v openssl >/dev/null 2>&1; then
        next_update=$(openssl crl -in "$crl_file" -noout -nextupdate 2>/dev/null | cut -d= -f2)
        if [ $? -eq 0 ] && [ -n "$next_update" ]; then
            # Convert to epoch time
            if command -v date >/dev/null 2>&1; then
                next_update_epoch=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$next_update" "+%s" 2>/dev/null)
                current_epoch=$(date "+%s")
                
                if [ -n "$next_update_epoch" ] && [ "$next_update_epoch" -gt 0 ]; then
                    if [ "$current_epoch" -gt "$next_update_epoch" ]; then
                        hours_overdue=$(( (current_epoch - next_update_epoch) / 3600 ))
                        log "WARNING: CRL $crl_name is $hours_overdue hours overdue"
                        echo "WARNING: CRL $crl_name is overdue"
                    else
                        hours_until_update=$(( (next_update_epoch - current_epoch) / 3600 ))
                        log "OK: CRL $crl_name valid for $hours_until_update more hours"
                    fi
                else
                    log "ERROR: Could not parse next update time for $crl_name"
                fi
            else
                log "ERROR: date command not available"
            fi
        else
            log "ERROR: Could not read CRL $crl_name"
        fi
    else
        log "ERROR: openssl command not available"
        exit 1
    fi
}

# Function to download CRL from URL
download_crl() {
    local url="$1"
    local output_file="$2"
    
    # Detect download tool
    if command -v fetch >/dev/null 2>&1; then
        fetch -q -o "$output_file" "$url" >/dev/null 2>&1
    elif command -v curl >/dev/null 2>&1; then
        curl -s -o "$output_file" "$url" >/dev/null 2>&1
    else
        log "ERROR: No download tool available (fetch/curl)"
        return 1
    fi
}

# Function to update CRLs from URLs
update_crls() {
    if [ ! -f "$CRL_URLS_FILE" ]; then
        log "INFO: No CRL URLs file found at $CRL_URLS_FILE"
        return 0
    fi
    
    log "Updating CRLs from URLs"
    while IFS=' ' read -r crl_url crl_filename || [ -n "$crl_url" ]; do
        # Skip empty lines and comments
        case "$crl_url" in
            ''|'#'*) continue ;;
        esac
        
        if [ -z "$crl_filename" ]; then
            log "ERROR: Invalid CRL URL line: '$crl_url'"
            continue
        fi
        
        crl_path="$CRL_DIR/$crl_filename"
        log "Downloading CRL: $crl_url -> $crl_path"
        
        if download_crl "$crl_url" "$crl_path"; then
            log "SUCCESS: Downloaded $crl_filename"
        else
            log "ERROR: Failed to download $crl_filename from $crl_url"
        fi
    done < "$CRL_URLS_FILE"
}

# Main execution
log "Starting CRL monitoring"

# Create CRL directory if it doesn't exist
if [ ! -d "$CRL_DIR" ]; then
    log "Creating CRL directory: $CRL_DIR"
    mkdir -p "$CRL_DIR" 2>/dev/null || {
        log "ERROR: Could not create CRL directory"
        exit 1
    }
fi

# Update CRLs from URLs if configured
update_crls

# Check freshness of all CRL files
if [ -d "$CRL_DIR" ]; then
    find "$CRL_DIR" -name "*.crl" -o -name "*.pem" | while read -r crl_file; do
        check_crl_freshness "$crl_file"
    done
else
    log "WARNING: CRL directory $CRL_DIR does not exist"
fi

log "CRL monitoring completed"