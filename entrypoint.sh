#!/bin/bash

cleanup() {
    echo "Cleaning up..."
    pkill -f squid
    exit 0
}

#trap cleanup EXIT

# Start squid proxy in background
squid -N &

echo "Current time: $(date)"
# Aguarda o Squid responder na porta 3128 (reduzido timeout e intervalos)
SQUID_TIMEOUT=8
SQUID_COUNTER=0
while ! nc -z 127.0.0.1 3128 2>/dev/null && [ $SQUID_COUNTER -lt $SQUID_TIMEOUT ]; do
    echo "Waiting for squid... ($SQUID_COUNTER/$SQUID_TIMEOUT)"
    sleep 0.5
    SQUID_COUNTER=$((SQUID_COUNTER + 1))
done

if ! nc -z 127.0.0.1 3128 2>/dev/null; then
    echo "Error: Squid not responding after $((SQUID_TIMEOUT / 2)) seconds"
    exit 1
fi

echo "Squid is ready"

# Show public IP and country via proxy (timeout mais curto)
echo "Testing public IP and country via Squid"
PROXY_RESPONSE=$(curl -s --max-time 5 --proxy http://127.0.0.1:3128 https://api.country.is/)
if [ -z "$PROXY_RESPONSE" ]; then
    echo "Public IP: (not detected)"
    echo "Public Country: (not detected)"
else
    # Extract IP and country from JSON response (otimizado com awk)
    PROXY_IP=$(echo "$PROXY_RESPONSE" | awk -F'"' '/"ip"/{print $4; exit}')
    PROXY_COUNTRY=$(echo "$PROXY_RESPONSE" | awk -F'"' '/"country"/{print $4; exit}')
    
    echo "Public IP: ${PROXY_IP:-(not detected)}"
    echo "Public Country: ${PROXY_COUNTRY:-(not detected)}"
fi

# Function to check SOCKS proxy configuration
check_socks_proxy() {
    if grep -q "^SOCKS_PROXY=True" configs.env; then
        echo "Iniciando servidor SOCKS to HTTP"
        
        # Extract SOCKS configuration from configs.env (mais eficiente com awk)
        eval "$(awk -F'=' '/^SOCKS_SERVER=|^SOCKS_USER=|^SOCKS_PASS=/ {gsub(/[[:space:]]+/, "", $2); print $1"="$2}' configs.env)"
        
        echo "SOCKS Server: $SOCKS_SERVER"
        
        sthp -p 8099 -s "$SOCKS_SERVER" -u "$SOCKS_USER" -P "$SOCKS_PASS" &> /dev/null &
        
        # Wait for SOCKS proxy to be ready (reduzido e otimizado)
        for i in {1..6}; do
            sleep 0.5
            if nc -z 127.0.0.1 8099 2>/dev/null; then
                break
            fi
        done
        
        # Test SOCKS-to-HTTP proxy on port 8099
        echo "Testing SOCKS-to-HTTP proxy on port 8099"
        SOCKS_RESPONSE=$(curl -s --max-time 5 --proxy http://127.0.0.1:8099 https://api.country.is/)
        if [ -z "$SOCKS_RESPONSE" ]; then
            echo "SOCKS Proxy IP: (not detected)"
            echo "SOCKS Proxy Country: (not detected)"
        else
            # Extract IP and country from JSON response (otimizado)
            SOCKS_IP=$(echo "$SOCKS_RESPONSE" | awk -F'"' '/"ip"/{print $4; exit}')
            SOCKS_COUNTRY=$(echo "$SOCKS_RESPONSE" | awk -F'"' '/"country"/{print $4; exit}')
            
            echo "SOCKS Proxy IP: ${SOCKS_IP:-(not detected)}"
            echo "SOCKS Proxy Country: ${SOCKS_COUNTRY:-(not detected)}"
        fi
    fi
}

# Check SOCKS proxy configuration
#check_socks_proxy

# Function to check available disk space
check_disk_space() {
    echo "=== Disk Space Information ==="
    
    # Get disk usage for current directory (otimizado - uma única chamada df)
    CURRENT_DIR=$(pwd)
    echo "Current directory: $CURRENT_DIR"
    
    # Use df to get disk space information (uma única chamada com processamento awk)
    read -r FILESYSTEM TOTAL_SIZE USED_SIZE AVAILABLE_SIZE USE_PERCENT MOUNT_POINT AVAILABLE_KB < <(df "$CURRENT_DIR" | awk 'NR==2 {
        print $1, $2, $3, $4, $5, $6, $4
    }' | sed 's/[KMG]//g')
    
    if [ -n "$FILESYSTEM" ]; then
        # Convert sizes for display
        TOTAL_SIZE_H=$(df -h "$CURRENT_DIR" | awk 'NR==2 {print $2}')
        USED_SIZE_H=$(df -h "$CURRENT_DIR" | awk 'NR==2 {print $3}')
        AVAILABLE_SIZE_H=$(df -h "$CURRENT_DIR" | awk 'NR==2 {print $4}')
        USE_PERCENT_H=$(df -h "$CURRENT_DIR" | awk 'NR==2 {print $5}')
        
        echo "Filesystem: $FILESYSTEM"
        echo "Total Size: $TOTAL_SIZE_H"
        echo "Used: $USED_SIZE_H"
        echo "Available: $AVAILABLE_SIZE_H"
        echo "Usage: $USE_PERCENT_H"
        echo "Mount Point: $MOUNT_POINT"
        
        # Check if available space is less than 1GB and warn
        AVAILABLE_GB=$((AVAILABLE_KB / 1024 / 1024))
        
        if [ "$AVAILABLE_GB" -lt 1 ]; then
            echo "⚠️  WARNING: Low disk space! Only ${AVAILABLE_SIZE_H} available"
        else
            echo "✅ Disk space is sufficient: ${AVAILABLE_SIZE_H} available"
        fi
    else
        echo "❌ Could not retrieve disk space information"
    fi
    echo "================================"
}

# Check disk space before starting
#check_disk_space

# execute CMD
echo "$@"
"$@"
