#!/usr/bin/env bash

# Colors
green='\033[0;32m'
red='\033[0;31m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo -e "${blue}        Xray Ghost Deployment Status Check${plain}"
echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"

XRAY_BIN="/usr/local/bin/xray"
XRAY_BACKUP="/usr/local/bin/xray.backup"
XRAY_SERVICE="xray"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
BANDWIDTH_SOCKET="/tmp/xray_bandwidth.sock"

# 1. Service Status
echo -e "\n${yellow}📊 Service Status${plain}"
if systemctl is-active --quiet $XRAY_SERVICE; then
    echo -e "   ${green}✅ Xray service is RUNNING${plain}"
else
    echo -e "   ${red}❌ Xray service is STOPPED${plain}"
fi

# 2. Binary Versions
echo -e "\n${yellow}📦 Binary Versions${plain}"
if [[ -f "$XRAY_BIN" ]]; then
    VERSION=$($XRAY_BIN -version 2>&1 | head -1)
    SIZE=$(du -h "$XRAY_BIN" | cut -f1)
    MODIFIED=$(stat -c %y "$XRAY_BIN" | cut -d' ' -f1,2)
    echo -e "   ${green}✅ Working${plain}"
    echo -e "      Version: ${blue}$VERSION${plain}"
    echo -e "      Size: ${blue}$SIZE${plain}"
    echo -e "      Modified: ${blue}$MODIFIED${plain}"
else
    echo -e "   ${red}❌ Working binary not found${plain}"
fi

if [[ -f "$XRAY_BACKUP" ]]; then
    BACKUP_VERSION=$($XRAY_BACKUP -version 2>&1 | head -1)
    BACKUP_SIZE=$(du -h "$XRAY_BACKUP" | cut -f1)
    BACKUP_MODIFIED=$(stat -c %y "$XRAY_BACKUP" | cut -d' ' -f1,2)
    echo -e "   ${green}✅ Backup${plain}"
    echo -e "      Version: ${blue}$BACKUP_VERSION${plain}"
    echo -e "      Size: ${blue}$BACKUP_SIZE${plain}"
    echo -e "      Modified: ${blue}$BACKUP_MODIFIED${plain}"
else
    echo -e "   ${yellow}⚠️  Backup not found (first deployment?)${plain}"
fi

# 3. Configuration
echo -e "\n${yellow}⚙️  Configuration${plain}"
if [[ -f "$XRAY_CONFIG" ]]; then
    echo -e "   ${green}✅ Config found at: ${blue}$XRAY_CONFIG${plain}"
else
    echo -e "   ${red}❌ Config not found${plain}"
fi

# 4. Bandwidth Tracking
echo -e "\n${yellow}📡 Bandwidth Tracking${plain}"
if [[ -S "$BANDWIDTH_SOCKET" ]]; then
    SOCKET_PERMS=$(stat -c "%a" "$BANDWIDTH_SOCKET")
    echo -e "   ${green}✅ Socket exists${plain}"
    echo -e "      Path: ${blue}$BANDWIDTH_SOCKET${plain}"
    echo -e "      Permissions: ${blue}$SOCKET_PERMS${plain}"
else
    echo -e "   ${yellow}⚠️  Bandwidth socket not found${plain}"
    echo -e "      (Listener should create it on first data)"
fi

# 5. Ports
echo -e "\n${yellow}🔌 Open Ports${plain}"
LISTENING_PORTS=$(ss -tlnp 2>/dev/null | grep -E 'xray|LISTEN' | awk '{print $4}' | grep -v State | sort -u)
if [[ -z "$LISTENING_PORTS" ]]; then
    echo -e "   ${yellow}⚠️  No Xray processes listening${plain}"
else
    echo -e "   ${green}✅ Listening on:${plain}"
    echo "$LISTENING_PORTS" | while read port; do
        echo -e "      ${blue}$port${plain}"
    done
fi

# 6. Recent Logs
echo -e "\n${yellow}📋 Recent Logs (last 5 lines)${plain}"
RECENT_LOGS=$(journalctl -u $XRAY_SERVICE -n 5 --no-pager 2>/dev/null | tail -5)
if [[ -z "$RECENT_LOGS" ]]; then
    echo -e "   ${yellow}⚠️  No logs available${plain}"
else
    echo "$RECENT_LOGS" | while read line; do
        echo -e "   ${blue}$line${plain}"
    done
fi

# 7. Memory Usage
echo -e "\n${yellow}💾 Resource Usage${plain}"
XRAY_PID=$(pgrep xray | head -1)
if [[ -n "$XRAY_PID" ]]; then
    MEM=$(ps aux | grep "^[^ ].*$XRAY_PID" | awk '{print $6}' | numfmt --to=iec-i --suffix=B 2>/dev/null || echo "N/A")
    CPU=$(ps aux | grep "^[^ ].*$XRAY_PID" | awk '{print $3}')
    echo -e "   ${green}✅ Process running (PID: ${blue}$XRAY_PID${green})${plain}"
    echo -e "      Memory: ${blue}$MEM${plain}"
    echo -e "      CPU: ${blue}$CPU%${plain}"
else
    echo -e "   ${red}❌ No Xray process found${plain}"
fi

# 8. Recommendations
echo -e "\n${yellow}💡 Recommendations${plain}"
if ! systemctl is-active --quiet $XRAY_SERVICE; then
    echo -e "   ${red}→ Service is down. Start with: ${yellow}sudo systemctl start $XRAY_SERVICE${plain}"
fi

if [[ ! -f "$XRAY_BACKUP" ]]; then
    echo -e "   ${yellow}→ No backup found. Run deployment first: ${blue}sudo bash deploy-local.sh${plain}"
fi

if [[ ! -S "$BANDWIDTH_SOCKET" ]]; then
    echo -e "   ${yellow}→ Start bandwidth listener: ${blue}python3 test_listener.py${plain}"
fi

echo -e "\n${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo -e "${green}Status check complete${plain}"
echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}\n"

exit 0
