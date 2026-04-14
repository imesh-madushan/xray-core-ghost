#!/usr/bin/env bash

# Colors for output
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

# Xray installation directory (3x-UI location)
XRAY_BIN_DIR="/usr/local/x-ui/bin"
SYS_ARCH=$(uname -m)
SYS_OS=$(uname -s | tr '[:upper:]' '[:lower:]')
# Normalize arch to match Go convention
case "$SYS_ARCH" in
  aarch64) SYS_ARCH="arm64" ;;
  x86_64) SYS_ARCH="amd64" ;;
esac
XRAY_BIN_NAME="xray-${SYS_OS}-${SYS_ARCH}"
XRAY_BIN_PATH="${XRAY_BIN_DIR}/${XRAY_BIN_NAME}"
XRAY_BACKUP_PATH="${XRAY_BIN_DIR}/${XRAY_BIN_NAME}.backup"
XRAY_BUILD_PATH="/home/ubuntu/prj/xray-core-ghost/xray-${SYS_OS}-${SYS_ARCH}"

# Service name
XRAY_SERVICE="xray"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${red}❌ This script must be run as root${plain}"
    exit 1
fi

# Check if the built binary exists
if [[ ! -f "$XRAY_BUILD_PATH" ]]; then
    echo -e "${red}❌ Built Xray binary not found at: $XRAY_BUILD_PATH${plain}"
    exit 1
fi

echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo -e "${green}🚀 Starting Xray Deployment${plain}"
echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"

# Step 1: Stop Xray service
echo -e "\n${yellow}[1/5]${plain} Stopping Xray service..."
if systemctl is-active --quiet $XRAY_SERVICE; then
    systemctl stop $XRAY_SERVICE
    if [[ $? -eq 0 ]]; then
        echo -e "${green}✅ Service stopped successfully${plain}"
        # Wait for file handles to be released
        echo -e "${blue}   → Waiting for file handles to release...${plain}"
        sleep 2
        
        # Force close any remaining processes using the file
        if command -v fuser &> /dev/null && [[ -f "$XRAY_BIN_PATH" ]]; then
            fuser -k "$XRAY_BIN_PATH" 2>/dev/null || true
            sleep 1
        fi
    else
        echo -e "${red}❌ Failed to stop service${plain}"
        exit 1
    fi
else
    echo -e "${yellow}⚠️  Service is not running${plain}"
fi

# Step 2: Backup current binary
echo -e "\n${yellow}[2/5]${plain} Managing backup..."
if [[ -f "$XRAY_BIN_PATH" ]]; then
    if [[ -f "$XRAY_BACKUP_PATH" ]]; then
        # Backup already exists, replace it with current version
        echo -e "${blue}   → Backup already exists, updating it...${plain}"
        cp "$XRAY_BIN_PATH" "$XRAY_BACKUP_PATH"
        chmod +x "$XRAY_BACKUP_PATH"
        echo -e "${green}✅ Backup updated from current binary${plain}"
    else
        # Create new backup
        echo -e "${blue}   → Creating first backup...${plain}"
        cp "$XRAY_BIN_PATH" "$XRAY_BACKUP_PATH"
        chmod +x "$XRAY_BACKUP_PATH"
        echo -e "${green}✅ Backup created: $XRAY_BACKUP_PATH${plain}"
    fi
else
    echo -e "${yellow}⚠️  No existing binary found at: $XRAY_BIN_PATH${plain}"
fi

# Step 3: Deploy new binary
echo -e "\n${yellow}[3/5]${plain} Deploying new Xray binary..."

# Retry logic for copy operation (handles "Text file busy" errors)
RETRY_COUNT=0
MAX_RETRIES=5
while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    cp "$XRAY_BUILD_PATH" "$XRAY_BIN_PATH" 2>/dev/null && break
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; then
        echo -e "${yellow}   → Retry $RETRY_COUNT/$MAX_RETRIES (file might be in use)...${plain}"
        sleep 1
    fi
done

if [[ $RETRY_COUNT -eq $MAX_RETRIES ]]; then
    echo -e "${red}❌ Failed to copy new binary after $MAX_RETRIES attempts${plain}"
    exit 1
fi

chmod +x "$XRAY_BIN_PATH"
if [[ $? -ne 0 ]]; then
    echo -e "${red}❌ Failed to set execute permissions${plain}"
    exit 1
fi
echo -e "${green}✅ New binary deployed: $XRAY_BIN_PATH${plain}"

# Step 4: Start service
echo -e "\n${yellow}[4/5]${plain} Starting Xray service..."
systemctl start $XRAY_SERVICE
if [[ $? -eq 0 ]]; then
    echo -e "${green}✅ Service started successfully${plain}"
else
    echo -e "${red}❌ Failed to start service${plain}"
    echo -e "${yellow}⚠️  Attempting to restore from backup...${plain}"
    if [[ -f "$XRAY_BACKUP_PATH" ]]; then
        cp "$XRAY_BACKUP_PATH" "$XRAY_BIN_PATH"
        chmod +x "$XRAY_BIN_PATH"
        systemctl start $XRAY_SERVICE
        echo -e "${yellow}⚠️  Restored from backup and restarted${plain}"
    fi
    exit 1
fi

# Step 5: Verify
echo -e "\n${yellow}[5/5]${plain} Verifying deployment..."
sleep 2

if systemctl is-active --quiet $XRAY_SERVICE; then
    XRAY_VERSION=$($XRAY_BIN_PATH -version 2>&1 | head -1)
    echo -e "${green}✅ Xray is running${plain}"
    echo -e "${green}   Version: $XRAY_VERSION${plain}"
else
    echo -e "${red}❌ Xray is not running${plain}"
    exit 1
fi

echo -e "\n${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo -e "${green}✅ Deployment completed successfully!${plain}"
echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"

# Show backup info
echo -e "\n${green}📊 Deployment Summary:${plain}"
echo -e "   Working binary: ${yellow}$XRAY_BIN_PATH${plain}"
echo -e "   Backup location: ${yellow}$XRAY_BACKUP_PATH${plain}"

if [[ -f "$XRAY_BACKUP_PATH" ]]; then
    BACKUP_SIZE=$(du -h "$XRAY_BACKUP_PATH" | cut -f1)
    echo -e "   Backup size: ${yellow}$BACKUP_SIZE${plain}"
fi

echo -e "\n${blue}Remote restore command if needed:${plain}"
echo -e "   ${yellow}sudo cp $XRAY_BACKUP_PATH $XRAY_BIN_PATH && sudo systemctl restart $XRAY_SERVICE${plain}"

exit 0
