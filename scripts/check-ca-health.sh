#!/bin/sh

# PKI Certificate Authority Health Check
# Monitors CA certificate status and health indicators

# Configuration
CA_DIR="/etc/ssl/ca"
OCSP_URLS_FILE="/pkitools/etc/ocsp-urls.txt"
LOG_FILE="/pkitools/logs/ca-health.log"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to check CA certificate validity
check_ca_validity() {
    local ca_file="$1"
    local ca_name=$(basename "$ca_file")
    
    if [ ! -f "$ca_file" ]; then
        log "ERROR: CA certificate file $ca_name not found"
        return 1
    fi
    
    log "Checking CA certificate validity for $ca_name"
    
    if command -v openssl >/dev/null 2>&1; then
        # Check if certificate is valid (not expired)
        if openssl x509 -in "$ca_file" -noout -checkend 0 >/dev/null 2>&1; then
            log "OK: CA certificate $ca_name is currently valid"
            
            # Check expiration warning (30 days)
            if openssl x509 -in "$ca_file" -noout -checkend 2592000 >/dev/null 2>&1; then
                log "OK: CA certificate $ca_name valid for more than 30 days"
            else
                log "WARNING: CA certificate $ca_name expires within 30 days"
                echo "WARNING: CA $ca_name expires soon"
            fi
        else
            log "ERROR: CA certificate $ca_name has expired"
            echo "ERROR: CA $ca_name expired"
        fi
        
        # Extract CA information
        subject=$(openssl x509 -in "$ca_file" -noout -subject 2>/dev/null | sed 's/subject=//')
        not_after=$(openssl x509 -in "$ca_file" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
        
        if [ -n "$subject" ]; then
            log "INFO: CA $ca_name Subject: $subject"
        fi
        if [ -n "$not_after" ]; then
            log "INFO: CA $ca_name Expires: $not_after"
        fi
        
    else
        log "ERROR: openssl command not available"
        exit 1
    fi
}

# Function to check CA key usage and constraints
check_ca_constraints() {
    local ca_file="$1"
    local ca_name=$(basename "$ca_file")
    
    log "Checking CA constraints for $ca_name"
    
    # Check Basic Constraints
    basic_constraints=$(openssl x509 -in "$ca_file" -noout -text 2>/dev/null | grep -A 1 "Basic Constraints:" | tail -1 | sed 's/^[[:space:]]*//')
    
    if echo "$basic_constraints" | grep -q "CA:TRUE"; then
        log "OK: $ca_name has proper CA:TRUE constraint"
    else
        log "WARNING: $ca_name missing or incorrect CA constraint"
        echo "WARNING: $ca_name improper CA constraint"
    fi
    
    # Check Key Usage
    key_usage=$(openssl x509 -in "$ca_file" -noout -text 2>/dev/null | grep -A 1 "Key Usage:" | tail -1 | sed 's/^[[:space:]]*//')
    
    if echo "$key_usage" | grep -q "Certificate Sign"; then
        log "OK: $ca_name has Certificate Sign key usage"
    else
        log "WARNING: $ca_name missing Certificate Sign key usage"
        echo "WARNING: $ca_name missing cert sign usage"
    fi
    
    if echo "$key_usage" | grep -q "CRL Sign"; then
        log "OK: $ca_name has CRL Sign key usage"
    else
        log "WARNING: $ca_name missing CRL Sign key usage"
        echo "WARNING: $ca_name missing CRL sign usage"
    fi
}

# Function to check OCSP responder status
check_ocsp_status() {
    if [ ! -f "$OCSP_URLS_FILE" ]; then
        log "INFO: No OCSP URLs file found at $OCSP_URLS_FILE"
        return 0
    fi
    
    log "Checking OCSP responder status"
    
    while IFS=' ' read -r ocsp_url ca_cert || [ -n "$ocsp_url" ]; do
        # Skip empty lines and comments
        case "$ocsp_url" in
            ''|'#'*) continue ;;
        esac
        
        if [ -z "$ca_cert" ]; then
            log "ERROR: Invalid OCSP URL line: '$ocsp_url'"
            continue
        fi
        
        log "Testing OCSP responder: $ocsp_url"
        
        # Simple connectivity test
        if command -v curl >/dev/null 2>&1; then
            if curl -s --connect-timeout 10 "$ocsp_url" >/dev/null 2>&1; then
                log "OK: OCSP responder $ocsp_url is accessible"
            else
                log "WARNING: OCSP responder $ocsp_url is not accessible"
                echo "WARNING: OCSP $ocsp_url unreachable"
            fi
        elif command -v fetch >/dev/null 2>&1; then
            if fetch -q -T 10 -o /dev/null "$ocsp_url" >/dev/null 2>&1; then
                log "OK: OCSP responder $ocsp_url is accessible"
            else
                log "WARNING: OCSP responder $ocsp_url is not accessible"
                echo "WARNING: OCSP $ocsp_url unreachable"
            fi
        else
            log "WARNING: No tool available to test OCSP connectivity"
        fi
        
    done < "$OCSP_URLS_FILE"
}

# Function to check disk space for PKI directories
check_disk_space() {
    log "Checking disk space for PKI directories"
    
    for dir in "$CA_DIR" "/pkitools" "/etc/ssl"; do
        if [ -d "$dir" ]; then
            # Get disk usage (works on both FreeBSD and Linux)
            if command -v df >/dev/null 2>&1; then
                usage=$(df "$dir" | tail -1 | awk '{print $5}' | sed 's/%//')
                if [ -n "$usage" ] && [ "$usage" -gt 90 ]; then
                    log "WARNING: Disk usage for $dir is $usage%"
                    echo "WARNING: Disk space low for $dir ($usage%)"
                elif [ -n "$usage" ]; then
                    log "OK: Disk usage for $dir is $usage%"
                fi
            fi
        fi
    done
}

# Main execution
log "Starting CA health check"

# Check if CA directory exists
if [ ! -d "$CA_DIR" ]; then
    log "WARNING: CA directory $CA_DIR does not exist"
    # Try to create it
    mkdir -p "$CA_DIR" 2>/dev/null || {
        log "ERROR: Could not create CA directory"
        exit 1
    }
fi

# Find and check all CA certificate files
find "$CA_DIR" -name "*.crt" -o -name "*.pem" -o -name "*.cer" | while read -r ca_file; do
    check_ca_validity "$ca_file"
    check_ca_constraints "$ca_file"
    echo "---"
done

# Check OCSP responder status
check_ocsp_status

# Check disk space
check_disk_space

log "CA health check completed"