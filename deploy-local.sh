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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${red}❌ This script must be run as root${plain}"
    exit 1
fi

echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo -e "${green}🚀 Starting Xray Build & Deployment${plain}"
echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"

# Step 1: Build new binary
echo -e "\n${yellow}[1/4]${plain} Building Xray binary..."
export PATH=$PATH:/usr/local/go/bin
if command -v go >/dev/null 2>&1; then
    GO_CMD="go"
elif [[ -x "/usr/local/go/bin/go" ]]; then
    GO_CMD="/usr/local/go/bin/go"
else
    echo -e "${red}❌ Go compiler not found. Please install Go.${plain}"
    exit 1
fi

echo -e "${blue}   → Using Go: $(${GO_CMD} version)${plain}"
cd /home/ubuntu/prj/xray-core-ghost || exit 1

CGO_ENABLED=0 ${GO_CMD} build \
  -o "$XRAY_BUILD_PATH" \
  -trimpath \
  -buildvcs=false \
  -ldflags="-s -w -buildid=" \
  ./main

if [[ $? -ne 0 ]]; then
    echo -e "${red}❌ Build failed${plain}"
    exit 1
fi
echo -e "${green}✅ Build successful: $XRAY_BUILD_PATH${plain}"

# Step 2: Backup current binary
echo -e "\n${yellow}[2/4]${plain} Managing backup..."
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
echo -e "\n${yellow}[3/4]${plain} Deploying new Xray binary..."

# Remove existing binary before copy to avoid "Text file busy"
if [[ -f "$XRAY_BIN_PATH" ]]; then
    rm -f "$XRAY_BIN_PATH"
fi

cp "$XRAY_BUILD_PATH" "$XRAY_BIN_PATH"
if [[ $? -ne 0 ]]; then
    echo -e "${red}❌ Failed to copy new binary${plain}"
    exit 1
fi

chmod +x "$XRAY_BIN_PATH"
if [[ $? -ne 0 ]]; then
    echo -e "${red}❌ Failed to set execute permissions${plain}"
    exit 1
fi
echo -e "${green}✅ New binary deployed: $XRAY_BIN_PATH${plain}"

# Step 4: Verify
echo -e "\n${yellow}[4/4]${plain} Verifying deployment..."
XRAY_VERSION=$($XRAY_BIN_PATH -version 2>&1 | head -1)
if [[ -n "$XRAY_VERSION" ]]; then
    echo -e "${green}✅ Binary is valid${plain}"
    echo -e "${green}   Version: $XRAY_VERSION${plain}"
else
    echo -e "${red}❌ Xray did not return version output${plain}"
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
echo -e "   ${yellow}sudo cp $XRAY_BACKUP_PATH $XRAY_BIN_PATH${plain}"

exit 0
