#!/usr/bin/env bash

green='\033[0;32m'
red='\033[0;31m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

SYS_ARCH=$(uname -m)
SYS_OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$SYS_ARCH" in
    aarch64) SYS_ARCH="arm64" ;;
    x86_64) SYS_ARCH="amd64" ;;
esac

XRAY_BIN="/usr/local/x-ui/bin/xray-${SYS_OS}-${SYS_ARCH}"
XRAY_BACKUP="/usr/local/x-ui/bin/xray-${SYS_OS}-${SYS_ARCH}.backup"

echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo -e "${blue}        Xray Ghost Status Check${plain}"
echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"

echo -e "\n${yellow}📦 Binary${plain}"
if [[ -f "$XRAY_BIN" ]]; then
    echo -e "   ${green}✅ Found: $XRAY_BIN${plain}"
    VERSION=$($XRAY_BIN -version 2>&1 | head -1)
    echo -e "   ${blue}Version: $VERSION${plain}"
else
    echo -e "   ${red}❌ Missing: $XRAY_BIN${plain}"
fi

echo -e "\n${yellow}💾 Backup${plain}"
if [[ -f "$XRAY_BACKUP" ]]; then
    SIZE=$(du -h "$XRAY_BACKUP" | cut -f1)
    echo -e "   ${green}✅ Found: $XRAY_BACKUP${plain}"
    echo -e "   ${blue}Size: $SIZE${plain}"
else
    echo -e "   ${yellow}⚠️  Missing: $XRAY_BACKUP${plain}"
fi

echo -e "\n${yellow}🔄 x-ui${plain}"
if command -v x-ui >/dev/null 2>&1; then
    XUI_STATUS=$(x-ui status 2>/dev/null || true)
    if [[ -n "$XUI_STATUS" ]]; then
        echo -e "   ${green}✅ x-ui command available${plain}"
        echo "$XUI_STATUS" | sed 's/^/   /'
    else
        echo -e "   ${yellow}⚠️  Could not read x-ui status (permission or runtime issue)${plain}"
    fi
else
    echo -e "   ${red}❌ x-ui command not found${plain}"
fi

echo -e "\n${green}Status check complete${plain}"
exit 0