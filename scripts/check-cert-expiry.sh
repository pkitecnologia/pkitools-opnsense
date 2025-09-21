#!/bin/sh

# PKI Certificate Expiry Checker
# Checks certificate expiration dates and alerts if expiring soon

# Configuration
CERT_DIR="/etc/ssl/certs"
WARN_DAYS=30
LOG_FILE="/pkitools/logs/cert-expiry.log"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to check certificate expiry
check_cert_expiry() {
    local cert_file="$1"
    local cert_name=$(basename "$cert_file")
    
    # Get certificate expiry date
    if command -v openssl >/dev/null 2>&1; then
        expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
        if [ $? -eq 0 ] && [ -n "$expiry_date" ]; then
            # Convert to epoch time for comparison
            if command -v date >/dev/null 2>&1; then
                expiry_epoch=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" "+%s" 2>/dev/null)
                current_epoch=$(date "+%s")
                
                if [ -n "$expiry_epoch" ] && [ "$expiry_epoch" -gt 0 ]; then
                    days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
                    
                    if [ "$days_until_expiry" -lt 0 ]; then
                        log "EXPIRED: $cert_name expired $((days_until_expiry * -1)) days ago"
                        echo "EXPIRED: $cert_name"
                    elif [ "$days_until_expiry" -le "$WARN_DAYS" ]; then
                        log "WARNING: $cert_name expires in $days_until_expiry days"
                        echo "WARNING: $cert_name expires in $days_until_expiry days"
                    else
                        log "OK: $cert_name expires in $days_until_expiry days"
                    fi
                else
                    log "ERROR: Could not parse expiry date for $cert_name"
                fi
            else
                log "ERROR: date command not available"
            fi
        else
            log "ERROR: Could not read certificate $cert_name"
        fi
    else
        log "ERROR: openssl command not available"
        exit 1
    fi
}

# Main execution
log "Starting certificate expiry check"

# Check if certificate directory exists
if [ ! -d "$CERT_DIR" ]; then
    log "WARNING: Certificate directory $CERT_DIR does not exist"
    exit 1
fi

# Find and check all certificate files
find "$CERT_DIR" -name "*.crt" -o -name "*.pem" -o -name "*.cer" | while read -r cert_file; do
    check_cert_expiry "$cert_file"
done

log "Certificate expiry check completed"