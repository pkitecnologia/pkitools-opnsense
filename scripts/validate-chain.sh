#!/bin/sh

# PKI Certificate Chain Validator
# Validates certificate chains and trust relationships

# Configuration
CERT_DIR="/etc/ssl/certs"
CA_DIR="/etc/ssl/ca"
LOG_FILE="/pkitools/logs/chain-validation.log"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to validate certificate chain
validate_chain() {
    local cert_file="$1"
    local cert_name=$(basename "$cert_file")
    
    if [ ! -f "$cert_file" ]; then
        log "ERROR: Certificate file $cert_name not found"
        return 1
    fi
    
    log "Validating certificate chain for $cert_name"
    
    if command -v openssl >/dev/null 2>&1; then
        # Check if we have a CA directory for validation
        if [ -d "$CA_DIR" ]; then
            # Validate against CA certificates
            if openssl verify -CApath "$CA_DIR" "$cert_file" >/dev/null 2>&1; then
                log "OK: Certificate chain valid for $cert_name"
                echo "OK: $cert_name chain valid"
            else
                log "ERROR: Certificate chain validation failed for $cert_name"
                echo "ERROR: $cert_name chain invalid"
            fi
        else
            log "WARNING: No CA directory found at $CA_DIR for validation"
            
            # Basic certificate format validation
            if openssl x509 -in "$cert_file" -noout >/dev/null 2>&1; then
                log "OK: Certificate format valid for $cert_name"
                echo "OK: $cert_name format valid"
            else
                log "ERROR: Certificate format invalid for $cert_name"
                echo "ERROR: $cert_name format invalid"
            fi
        fi
        
        # Extract and display certificate information
        subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/subject=//')
        issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null | sed 's/issuer=//')
        
        if [ -n "$subject" ]; then
            log "INFO: $cert_name Subject: $subject"
        fi
        if [ -n "$issuer" ]; then
            log "INFO: $cert_name Issuer: $issuer"
        fi
        
    else
        log "ERROR: openssl command not available"
        exit 1
    fi
}

# Function to check certificate key usage
check_key_usage() {
    local cert_file="$1"
    local cert_name=$(basename "$cert_file")
    
    # Extract key usage extensions
    key_usage=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep -A 1 "Key Usage:" | tail -1 | sed 's/^[[:space:]]*//')
    ext_key_usage=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep -A 1 "Extended Key Usage:" | tail -1 | sed 's/^[[:space:]]*//')
    
    if [ -n "$key_usage" ]; then
        log "INFO: $cert_name Key Usage: $key_usage"
    fi
    if [ -n "$ext_key_usage" ]; then
        log "INFO: $cert_name Extended Key Usage: $ext_key_usage"
    fi
}

# Function to check certificate algorithm strength
check_algorithm_strength() {
    local cert_file="$1"
    local cert_name=$(basename "$cert_file")
    
    # Check signature algorithm
    sig_alg=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep "Signature Algorithm:" | head -1 | sed 's/.*Signature Algorithm: //')
    
    if [ -n "$sig_alg" ]; then
        log "INFO: $cert_name Signature Algorithm: $sig_alg"
        
        # Check for weak algorithms
        case "$sig_alg" in
            *md5*|*MD5*)
                log "WARNING: $cert_name uses weak MD5 signature algorithm"
                echo "WARNING: $cert_name uses weak MD5"
                ;;
            *sha1*|*SHA1*)
                log "WARNING: $cert_name uses weak SHA1 signature algorithm"
                echo "WARNING: $cert_name uses weak SHA1"
                ;;
            *)
                log "OK: $cert_name uses acceptable signature algorithm"
                ;;
        esac
    fi
    
    # Check key size
    key_size=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep "Public-Key:" | sed 's/.*(\([0-9]*\) bit).*/\1/')
    
    if [ -n "$key_size" ] && [ "$key_size" -lt 2048 ]; then
        log "WARNING: $cert_name has weak key size: $key_size bits"
        echo "WARNING: $cert_name weak key size ($key_size bits)"
    elif [ -n "$key_size" ]; then
        log "OK: $cert_name key size: $key_size bits"
    fi
}

# Main execution
log "Starting certificate chain validation"

# Check if certificate directory exists
if [ ! -d "$CERT_DIR" ]; then
    log "WARNING: Certificate directory $CERT_DIR does not exist"
    exit 1
fi

# Find and validate all certificate files
find "$CERT_DIR" -name "*.crt" -o -name "*.pem" -o -name "*.cer" | while read -r cert_file; do
    validate_chain "$cert_file"
    check_key_usage "$cert_file"
    check_algorithm_strength "$cert_file"
    echo "---"
done

log "Certificate chain validation completed"