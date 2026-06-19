#!/bin/bash
# ============================================================
# CELESTIA VALIDATOR MANAGEMENT TOOL v1.0
# Author: MegaNode
# Description: All-in-one tool for Celestia node operations
#              (Mainnet / Mocha Testnet)
# ============================================================

set +e  # Don't exit on errors - handle them gracefully

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Globals
NETWORK=""
CHAIN_ID=""
RPC_PORT="26657"
LOCAL_RPC=""
PUBLIC_RPC=""
APP_HOME="$HOME/.celestia-app"
SERVICE_NAME="celestia-appd"
SNAPSHOT_BASE_URL=""
CELESTIA_BIN=""

# ============================================================
# UTILITY FUNCTIONS
# ============================================================

print_banner() {
    clear
    local width=54
    local title="⬡ CELESTIA NODE MANAGEMENT TOOL v1.0"
    local author="MegaNode"
    local pad1=$(( (width - 2 - ${#title}) ))
    local pad2=$(( (width - 2 - ${#author}) ))
    echo -e "${PURPLE}╔$(printf '═%.0s' $(seq 1 $width))╗${NC}"
    echo -e "${PURPLE}║${NC} ${BOLD}${CYAN}${title}${NC}$(printf ' %.0s' $(seq 1 $pad1))${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC} ${BOLD}${author}${NC}$(printf ' %.0s' $(seq 1 $pad2))${PURPLE}║${NC}"
    echo -e "${PURPLE}╚$(printf '═%.0s' $(seq 1 $width))╝${NC}"
    echo ""
}

print_separator() {
    echo -e "${BLUE}──────────────────────────────────────────────────────${NC}"
}

print_info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

press_enter() {
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

rpc_call() {
    local url="$1"
    local endpoint="$2"
    local result
    result=$(curl -s --connect-timeout 10 --max-time 20 "${url}${endpoint}" 2>/dev/null) || result=""
    echo "$result"
}

# ============================================================
# NETWORK SELECTION
# ============================================================

select_network() {
    print_banner
    echo -e "${BOLD}Select Network:${NC}"
    print_separator
    echo -e "  ${GREEN}1)${NC} Celestia Mainnet (celestia)"
    echo -e "  ${GREEN}2)${NC} Mocha Testnet (mocha-4)"
    echo -e "  ${RED}0)${NC} Exit"
    print_separator
    echo ""
    read -rp "$(echo -e ${CYAN}'Enter choice [1/2/0]: '${NC})" choice

    case $choice in
        1)
            NETWORK="MAINNET"
            CHAIN_ID="celestia"
            PUBLIC_RPC="https://celestia-mainnet-rpc.itrocket.net:443"
            SNAPSHOT_BASE_URL="https://server-1.itrocket.net/mainnet/celestia"
            ;;
        2)
            NETWORK="MOCHA TESTNET"
            CHAIN_ID="mocha-4"
            PUBLIC_RPC="https://rpc-mocha.pops.one"
            SNAPSHOT_BASE_URL="https://server-6.itrocket.net/testnet/celestia"
            ;;
        0)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            print_error "Invalid choice"
            select_network
            return
            ;;
    esac

    # APP_HOME defaults to $HOME/.celestia-app, fallback to /root if running as non-root via sudo
    APP_HOME="${APP_HOME%/}"
    if [ ! -d "$APP_HOME" ] && [ -d "/root/.celestia-app" ]; then
        APP_HOME="/root/.celestia-app"
    fi

    # Auto-detect local RPC port from config
    if [ -f "$APP_HOME/config/config.toml" ]; then
        local detected_port
        detected_port=$(grep -A1 '^\[rpc\]' "$APP_HOME/config/config.toml" 2>/dev/null | grep "laddr" | grep -oP ':\K[0-9]+(?="?$)' | head -1)
        if [ -n "$detected_port" ]; then
            RPC_PORT="$detected_port"
        fi
    fi

    LOCAL_RPC="http://localhost:${RPC_PORT}"

    # Test local RPC connection
    local test_result
    test_result=$(curl -s --connect-timeout 3 --max-time 5 "${LOCAL_RPC}/status" 2>/dev/null || echo "")
    if [ -z "$test_result" ] || ! echo "$test_result" | jq -e '.result' &>/dev/null; then
        print_warn "Cannot connect to local RPC at ${LOCAL_RPC}"
        
        # Try common alternative ports
        local found_port=""
        for try_port in 26657 26667 36657 46657 11657 26680; do
            local try_result
            try_result=$(curl -s --connect-timeout 2 --max-time 3 "http://localhost:${try_port}/status" 2>/dev/null || echo "")
            if [ -n "$try_result" ] && echo "$try_result" | jq -e '.result' &>/dev/null; then
                found_port="$try_port"
                break
            fi
        done

        if [ -n "$found_port" ]; then
            RPC_PORT="$found_port"
            LOCAL_RPC="http://localhost:${RPC_PORT}"
            print_success "Found RPC at port ${found_port}"
        else
            echo ""
            read -rp "$(echo -e ${CYAN}'Enter your local RPC port (or press Enter to use public RPC only): '${NC})" manual_port
            if [ -n "$manual_port" ]; then
                RPC_PORT="$manual_port"
                LOCAL_RPC="http://localhost:${RPC_PORT}"
            else
                LOCAL_RPC="$PUBLIC_RPC"
                print_warn "Using public RPC — some features (validator info, local sync) will be limited"
            fi
        fi
    else
        print_success "Local RPC connected at ${LOCAL_RPC}"
    fi

    # Auto-detect celestia-appd binary path
    CELESTIA_BIN=""
    if command -v celestia-appd &>/dev/null; then
        CELESTIA_BIN="celestia-appd"
    elif [ -f "/root/go/bin/celestia-appd" ]; then
        CELESTIA_BIN="/root/go/bin/celestia-appd"
    elif [ -f "$HOME/go/bin/celestia-appd" ]; then
        CELESTIA_BIN="$HOME/go/bin/celestia-appd"
    elif [ -f "/usr/local/bin/celestia-appd" ]; then
        CELESTIA_BIN="/usr/local/bin/celestia-appd"
    fi

    # Auto-detect service name
    if ! systemctl list-units --full --all 2>/dev/null | grep -q "^${SERVICE_NAME}.service"; then
        for alt in celestia celestia-mocha celestia-node celestiad; do
            if systemctl list-units --full --all 2>/dev/null | grep -q "^${alt}.service"; then
                SERVICE_NAME="$alt"
                break
            fi
        done
    fi
}

# ============================================================
# MENU FUNCTIONS
# ============================================================

# 1. Quick Status Check
quick_status() {
    print_banner
    echo -e "${BOLD}⬡ Quick Status Check [${NETWORK}]${NC}"
    print_separator

    echo -e "\n${BOLD}Service:${NC}"
    local status
    status=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || echo "unknown")
    if [ "$status" = "active" ]; then
        echo -e "  ${GREEN}●${NC} $SERVICE_NAME: ${GREEN}active${NC}"
    elif [ "$status" = "failed" ]; then
        echo -e "  ${RED}●${NC} $SERVICE_NAME: ${RED}failed${NC}"
    else
        echo -e "  ${YELLOW}●${NC} $SERVICE_NAME: ${YELLOW}$status${NC}"
    fi

    echo -e "\n${BOLD}Sync Info:${NC}"
    local sync_info
    sync_info=$(rpc_call "$LOCAL_RPC" "/status")
    if [ -n "$sync_info" ] && echo "$sync_info" | jq -e '.result' &>/dev/null; then
        local height catching_up node_id block_time
        height=$(echo "$sync_info" | jq -r '.result.sync_info.latest_block_height // "N/A"' 2>/dev/null)
        catching_up=$(echo "$sync_info" | jq -r 'if .result.sync_info.catching_up then "true" else "false" end' 2>/dev/null || echo "unknown")
        node_id=$(echo "$sync_info" | jq -r '.result.node_info.id // "N/A"' 2>/dev/null)
        block_time=$(echo "$sync_info" | jq -r '.result.sync_info.latest_block_time // "N/A"' 2>/dev/null | cut -d'.' -f1)
        echo -e "  Height: ${GREEN}${height}${NC}"
        echo -e "  Block Time: ${block_time}"
        if [ "$catching_up" = "false" ]; then
            echo -e "  Status: ${GREEN}✓ Synced${NC}"
        elif [ "$catching_up" = "true" ]; then
            echo -e "  Status: ${YELLOW}⏳ Catching up...${NC}"
        else
            echo -e "  Status: ${RED}Unable to determine${NC}"
        fi
        echo -e "  Node ID: ${node_id}"
    else
        echo -e "  ${RED}Cannot connect to local RPC ($LOCAL_RPC)${NC}"
    fi

    echo -e "\n${BOLD}Network:${NC}"
    local net_info n_peers
    net_info=$(rpc_call "$LOCAL_RPC" "/net_info")
    if [ -n "$net_info" ] && echo "$net_info" | jq -e '.result' &>/dev/null; then
        n_peers=$(echo "$net_info" | jq -r '.result.n_peers // "N/A"' 2>/dev/null)
        echo -e "  Peers: ${n_peers}"
    else
        echo -e "  Peers: ${YELLOW}N/A${NC}"
    fi

    echo -e "\n${BOLD}Resources:${NC}"
    echo -e "  RAM: $(free -h | awk '/Mem:/{printf "%s / %s used", $3, $2}')"

    echo -e "\n${BOLD}Uptime:${NC}"
    local since
    since=$(systemctl show "$SERVICE_NAME" --property=ActiveEnterTimestamp 2>/dev/null | cut -d= -f2)
    if [ -n "$since" ]; then
        echo -e "  $SERVICE_NAME: since $since"
    fi

    press_enter
}

# 2. Sync Verification
sync_check() {
    print_banner
    echo -e "${BOLD}⬡ Sync Verification [${NETWORK}]${NC}"
    print_separator

    echo -e "\n${BOLD}Fetching data...${NC}"

    local local_info local_height local_catching_up local_block_time
    local_info=$(rpc_call "$LOCAL_RPC" "/status" 2>/dev/null || echo "")

    if [ -z "$local_info" ] || ! echo "$local_info" | jq -e '.result' &>/dev/null; then
        print_error "Cannot connect to local RPC ($LOCAL_RPC)"
        print_warn "Check if $SERVICE_NAME is running: systemctl status $SERVICE_NAME"
        press_enter
        return
    fi

    local_height=$(echo "$local_info" | jq -r '.result.sync_info.latest_block_height // "N/A"' 2>/dev/null)
    local_catching_up=$(echo "$local_info" | jq -r 'if .result.sync_info.catching_up then "true" else "false" end' 2>/dev/null || echo "unknown")
    local_block_time=$(echo "$local_info" | jq -r '.result.sync_info.latest_block_time // "N/A"' 2>/dev/null | cut -d'.' -f1)

    local network_info network_height
    network_info=$(rpc_call "$PUBLIC_RPC" "/status" 2>/dev/null || echo "")
    if [ -n "$network_info" ] && echo "$network_info" | jq -e '.result' &>/dev/null; then
        network_height=$(echo "$network_info" | jq -r '.result.sync_info.latest_block_height // "N/A"' 2>/dev/null)
    else
        network_height="N/A (public RPC unreachable)"
    fi

    echo ""
    echo -e "  ${BOLD}Local Height:${NC}     ${CYAN}${local_height}${NC}"
    echo -e "  ${BOLD}Local Block Time:${NC} ${local_block_time}"
    echo -e "  ${BOLD}Network Height:${NC}   ${CYAN}${network_height}${NC}"

    if [[ "$local_height" =~ ^[0-9]+$ ]] && [[ "$network_height" =~ ^[0-9]+$ ]]; then
        local diff=$((network_height - local_height))
        echo -e "  ${BOLD}Diff:${NC}             ${diff} blocks"

        if [ "$diff" -le 5 ] && [ "$diff" -ge -100 ]; then
            echo -e "  ${BOLD}Status:${NC}           ${GREEN}✓ FULLY SYNCED${NC}"
        elif [ "$diff" -gt 5 ] && [ "$diff" -le 100 ]; then
            echo -e "  ${BOLD}Status:${NC}           ${YELLOW}⏳ Almost synced (${diff} blocks behind)${NC}"
        else
            echo -e "  ${BOLD}Status:${NC}           ${RED}⏳ Syncing... (${diff} blocks behind)${NC}"
        fi
    else
        if [ "$local_catching_up" = "false" ]; then
            echo -e "  ${BOLD}Status:${NC}           ${GREEN}✓ FULLY SYNCED${NC}"
        elif [ "$local_catching_up" = "true" ]; then
            echo -e "  ${BOLD}Status:${NC}           ${YELLOW}⏳ Catching up...${NC}"
        else
            echo -e "  ${BOLD}Status:${NC}           ${RED}Cannot determine (public RPC issue)${NC}"
        fi
    fi

    press_enter
}

# 3. Validator Info
validator_info() {
    print_banner
    echo -e "${BOLD}⬡ Validator Info [${NETWORK}]${NC}"
    print_separator

    # Validator key from local binary
    echo -e "\n${BOLD}Local Keys:${NC}"
    if [ -n "$CELESTIA_BIN" ] && [ -d "$APP_HOME" ]; then
        local valkey_addr
        valkey_addr=$($CELESTIA_BIN tendermint show-validator --home "$APP_HOME" 2>/dev/null || echo "")
        if [ -n "$valkey_addr" ]; then
            echo -e "  ${BOLD}Validator Pubkey:${NC} $valkey_addr"
        else
            echo -e "  ${BOLD}Validator Pubkey:${NC} ${YELLOW}N/A (key not found)${NC}"
        fi

        local node_id
        node_id=$($CELESTIA_BIN tendermint show-node-id --home "$APP_HOME" 2>/dev/null || echo "")
        if [ -n "$node_id" ]; then
            echo -e "  ${BOLD}Node ID:${NC} $node_id"
        else
            echo -e "  ${BOLD}Node ID:${NC} ${YELLOW}N/A${NC}"
        fi
    else
        echo -e "  ${YELLOW}celestia-appd not found or APP_HOME ($APP_HOME) not found${NC}"
        echo -e "  ${YELLOW}Checked: /root/go/bin/, \$HOME/go/bin/, /usr/local/bin/, PATH${NC}"
    fi

    # RPC info
    echo -e "\n${BOLD}From RPC:${NC}"
    local status_info
    status_info=$(rpc_call "$LOCAL_RPC" "/status" 2>/dev/null || echo "")

    if [ -z "$status_info" ] || ! echo "$status_info" | jq -e '.result' &>/dev/null; then
        print_error "Cannot connect to local RPC ($LOCAL_RPC)"
        press_enter
        return
    fi

    local validator_addr voting_power moniker chain_id_rpc
    validator_addr=$(echo "$status_info" | jq -r '.result.validator_info.address // "N/A"' 2>/dev/null)
    voting_power=$(echo "$status_info" | jq -r '.result.validator_info.voting_power // "0"' 2>/dev/null)
    moniker=$(echo "$status_info" | jq -r '.result.node_info.moniker // "N/A"' 2>/dev/null)
    chain_id_rpc=$(echo "$status_info" | jq -r '.result.node_info.network // "N/A"' 2>/dev/null)

    echo -e "  ${BOLD}Moniker:${NC}      ${moniker}"
    echo -e "  ${BOLD}Chain ID:${NC}     ${chain_id_rpc}"
    echo -e "  ${BOLD}Address:${NC}      ${validator_addr}"
    echo -e "  ${BOLD}Voting Power:${NC} ${voting_power}"

    # Active set check
    echo -e "\n${BOLD}Active Set:${NC}"
    if [ -n "$validator_addr" ] && [ "$validator_addr" != "null" ] && [ "$validator_addr" != "N/A" ]; then
        if [ "$voting_power" != "0" ] && [ -n "$voting_power" ]; then
            echo -e "  ${GREEN}✓ In active validator set (voting power: ${voting_power})${NC}"
        else
            echo -e "  ${YELLOW}✗ Not in active set (voting power: 0)${NC}"
        fi

        # Count total validators
        local val_info total_vals
        val_info=$(rpc_call "$LOCAL_RPC" "/validators?per_page=1" 2>/dev/null || echo "")
        total_vals=$(echo "$val_info" | jq -r '.result.total // "N/A"' 2>/dev/null)
        echo -e "  ${BOLD}Total Validators:${NC} ${total_vals}"
    else
        echo -e "  ${RED}Cannot determine (no validator address)${NC}"
    fi

    # Peers
    echo -e "\n${BOLD}Peers:${NC}"
    local net_info n_peers
    net_info=$(rpc_call "$LOCAL_RPC" "/net_info" 2>/dev/null || echo "")
    n_peers=$(echo "$net_info" | jq -r '.result.n_peers // "N/A"' 2>/dev/null)
    echo -e "  Connected: ${n_peers}"

    press_enter
}

# 4. Service Status
service_status() {
    print_banner
    echo -e "${BOLD}⬡ Service Status [${NETWORK}]${NC}"
    print_separator

    sudo systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null | head -40

    press_enter
}

# 5. View Logs
view_logs() {
    print_banner
    echo -e "${BOLD}⬡ View Logs [${NETWORK}]${NC}"
    print_separator
    echo -e "  ${GREEN}1)${NC} Last 50 lines"
    echo -e "  ${GREEN}2)${NC} Follow logs (realtime)"
    echo -e "  ${GREEN}3)${NC} Proposals (last 1 hour)"
    echo -e "  ${GREEN}4)${NC} Errors & Warnings (last 1 hour)"
    echo -e "  ${GREEN}5)${NC} Missed blocks / consensus issues"
    echo -e "  ${RED}0)${NC} Back"
    print_separator
    echo ""
    read -rp "$(echo -e ${CYAN}'Enter choice: '${NC})" choice

    case $choice in
        1) journalctl -u "$SERVICE_NAME" -n 50 --no-pager; press_enter ;;
        2) echo -e "${YELLOW}Press Ctrl+C to exit...${NC}"; journalctl -u "$SERVICE_NAME" -f ;;
        3)
            echo -e "\n${BOLD}Proposals (last 1 hour):${NC}"
            journalctl -u "$SERVICE_NAME" --since "1 hour ago" --no-pager | grep -i "received proposal" | tail -20
            press_enter
            ;;
        4)
            echo -e "\n${BOLD}Errors & Warnings (last 1 hour):${NC}"
            journalctl -u "$SERVICE_NAME" --since "1 hour ago" --no-pager | grep -iE "error|warn|fail|panic|timeout" | tail -30
            press_enter
            ;;
        5)
            echo -e "\n${BOLD}Consensus issues (last 1 hour):${NC}"
            journalctl -u "$SERVICE_NAME" --since "1 hour ago" --no-pager | grep -iE "miss|skip|prevote|precommit|round" | tail -20
            press_enter
            ;;
        0) return ;;
        *) print_error "Invalid choice"; press_enter ;;
    esac
}

# 6. Resource Monitor
resource_monitor() {
    print_banner
    echo -e "${BOLD}⬡ Resource Monitor [${NETWORK}]${NC}"
    print_separator

    echo -e "\n${BOLD}CPU:${NC}"
    echo -e "  Cores: $(nproc)"
    echo -e "  Load: $(uptime | awk -F'load average:' '{print $2}')"

    local pid
    pid=$(pgrep -f "${SERVICE_NAME}" | head -1)
    if [ -n "$pid" ]; then
        echo -e "  Affinity (PID $pid): $(taskset -p "$pid" 2>/dev/null | awk -F': ' '{print $2}')"
    fi

    echo -e "\n${BOLD}Memory:${NC}"
    free -h | awk '/Mem:/{printf "  Total: %s | Used: %s | Available: %s\n", $2, $3, $7}'
    free -h | awk '/Swap:/{printf "  Swap: %s used / %s total\n", $3, $2}'
    echo -e "  Swappiness: $(cat /proc/sys/vm/swappiness 2>/dev/null)"

    echo -e "\n${BOLD}Disk:${NC}"
    if [ -d "$APP_HOME" ]; then
        echo -e "  Data dir: $APP_HOME"
        du -sh "$APP_HOME/data" 2>/dev/null | awk '{print "  Data size: " $1}'
    fi
    df -h "$APP_HOME" 2>/dev/null | tail -1 | awk '{print "  Disk usage: " $3 " / " $2 " (" $5 ")"}'

    echo -e "\n${BOLD}Time Sync:${NC}"
    if command -v chronyc &>/dev/null; then
        chronyc tracking 2>/dev/null | grep "System time" | awk '{printf "  Offset: %s %s %s %s %s\n", $4, $5, $6, $7, $8}'
    else
        echo -e "  ${YELLOW}chrony not installed${NC}"
    fi

    press_enter
}

# 7. Peers Management
peers_management() {
    print_banner
    echo -e "${BOLD}⬡ Peers Management [${NETWORK}]${NC}"
    print_separator

    local net_info n_peers
    net_info=$(rpc_call "$LOCAL_RPC" "/net_info")
    n_peers=$(echo "$net_info" | jq -r '.result.n_peers' 2>/dev/null)
    echo -e "\n${BOLD}Connected Peers:${NC} ${n_peers:-N/A}"

    echo -e "\n${BOLD}Persistent Peers (config):${NC}"
    if [ -f "$APP_HOME/config/config.toml" ]; then
        grep "^persistent_peers" "$APP_HOME/config/config.toml" | head -1 | tr ',' '\n' | grep -oP '@[^:]+' | sed 's/@/  - /' | head -15
    fi

    echo ""
    echo -e "  ${GREEN}1)${NC} List connected peer IPs"
    echo -e "  ${RED}0)${NC} Back"
    print_separator
    echo ""
    read -rp "$(echo -e ${CYAN}'Enter choice: '${NC})" choice

    case $choice in
        1)
            echo -e "\n${BOLD}Connected Peer IPs:${NC}"
            echo "$net_info" | jq -r '.result.peers[].remote_ip' 2>/dev/null | sort -u
            press_enter
            ;;
        0) return ;;
    esac
}

# 8. Restart Service
restart_service() {
    print_banner
    echo -e "${BOLD}⬡ Restart Service [${NETWORK}]${NC}"
    print_separator

    read -rp "$(echo -e ${YELLOW}"Restart $SERVICE_NAME? [y/N]: "${NC})" confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        print_info "Restarting $SERVICE_NAME..."
        sudo systemctl restart "$SERVICE_NAME"
        sleep 3
        local status
        status=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null)
        if [ "$status" = "active" ]; then
            print_success "$SERVICE_NAME: active"
        else
            print_error "$SERVICE_NAME: $status"
        fi
    else
        print_info "Cancelled."
    fi

    press_enter
}

# 9. Soft Reset (State Sync)
soft_reset() {
    print_banner
    echo -e "${BOLD}⬡ Soft Reset (State Sync) [${NETWORK}]${NC}"
    print_separator
    echo -e "${YELLOW}This will:${NC}"
    echo -e "  - Stop the service"
    echo -e "  - Backup priv_validator_state.json"
    echo -e "  - Run unsafe-reset-all"
    echo -e "  - Update persistent_peers"
    echo -e "  - Configure state-sync (trust height/hash from RPC)"
    echo -e "  - Restore priv_validator_state.json"
    echo -e "  - Restart the service"
    print_separator

    read -rp "$(echo -e ${RED}'Are you sure? [y/N]: '${NC})" confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        print_info "Cancelled."
        press_enter
        return
    fi

    local peers snap_rpc
    if [ "$NETWORK" = "MAINNET" ]; then
        peers="d535cbf8d0efd9100649aa3f53cb5cbab33ef2d6@celestia-mainnet-peer.itrocket.net:26656,12ad7c73c7e1f2460941326937a039139aa78884@celestia-mainnet-seed.itrocket.net:40656"
        snap_rpc="https://celestia-mainnet-rpc.itrocket.net:443"
    else
        peers="daf2cecee2bd7f1b3bf94839f993f807c6b15fbf@celestia-testnet-peer.itrocket.net:11656,0d49c141eca5dd1d1c7577b61c4408c7a43d929f@194.48.168.10:28656,c7dc0a1d45f062a6f929b98cb14bbc22b58d821b@173.201.36.182:26656,b858b5b5afa5169c2d6265646be9d3529d1628ce@169.255.59.138:26656,f05e6a065b772dda4c7c0cbed40894a8c43416c7@51.15.18.22:26656,8bbe141f8f8186e15c4c5046003b0700121bbc45@40.160.16.51:26656,e26506bc1ed8f5ea373e1b8c5bc74551607d78a6@151.115.60.15:26656,43e9da043318a4ea0141259c17fcb06ecff816af@164.132.247.253:43656,e40a4f74fb1f6b8cfdc1f14e50056aeebe2a5d7d@95.141.37.15:12656,51ac9bc2a76d1aed7051cb36c69922f093be43c1@65.21.20.16:26656,42a56aadd35b9d0b0027594b035da6022fbfbcc9@178.63.89.179:26656,c54b1c53896d4147142ecc6664fce4c226b2e913@149.50.110.119:11656,387e3834d8023bf23adf3888f803ac4bae499da5@217.28.48.238:28656,588f56ecd9dbac1a2a6529939030393b22ec709f@216.158.94.178:26656,9b4aa64e7e67a78ef769c78d3e4c7454d80195a6@144.76.18.142:26630,69c08410d85b22daf02afff669dfee2b72204511@216.106.185.180:11656,7a649733c5ae1b8bba9a5d855d697811646a0f6a@184.107.149.93:36656,ae7d00d6d70d9b9118c31ac0913e0808f2613a75@216.106.177.153:26656,8d8ea488c2d9f0a98f0f0b72bbdb4929c768a8e6@193.34.213.77:11007,c449cf45dc362b436ae5bcd28cd8a8584c5ad92e@195.154.153.32:26656,bbdb266294c6e7b3f661dbcabdb4efaf0466c504@92.204.168.57:26656,4809a2832d9f871504c76da4b27fae0cc6460025@84.32.32.140:26656,d872e98148db5016920975686acb4897f5a3c459@65.108.228.199:10356,2c52c43c24bdc9ebbb39fbeeec93385ebd497814@84.32.70.3:26656,f689e6ab2db5f0a3a1db2ed33958a00240689a7b@65.109.59.22:11656,ac1338ace0d7ebaa77221c977acace15de4c81a8@57.128.192.23:26686,41f8d0c59684cad33eee17b1b30468c8a33777d2@95.217.75.149:44656,89487bc081cad4b073b33cecb5db72b3654e1681@195.154.218.203:26656,825105d9a1e27cbfc4dc8550fe0bb9147e1e4a3c@184.107.185.201:6050,e0a8d105c137e5e9ab163673f08f7638c1350f20@38.248.91.243:26656,546cc6e7e987e0d8790efaab1645f7dc7512d760@64.130.45.151:26656,4eeea98dd704ba43b2745f1041c81eb91b43d750@195.154.103.60:26656"
        snap_rpc="https://celestia-testnet-rpc.itrocket.net:443"
    fi

    print_info "Stopping service..."
    sudo systemctl stop "$SERVICE_NAME"

    print_info "Backing up priv_validator_state.json..."
    cp "$APP_HOME/data/priv_validator_state.json" "$APP_HOME/priv_validator_state.json.backup"

    print_info "Running unsafe-reset-all..."
    if [ -n "$CELESTIA_BIN" ]; then
        $CELESTIA_BIN tendermint unsafe-reset-all --home "$APP_HOME" 2>/dev/null || \
            $CELESTIA_BIN unsafe-reset-all --home "$APP_HOME" 2>/dev/null || \
            print_error "unsafe-reset-all failed"
    else
        print_error "celestia-appd binary not found. Cannot run unsafe-reset-all."
        press_enter
        return
    fi

    print_info "Updating persistent_peers..."
    sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$peers\"/" "$APP_HOME/config/config.toml"

    print_info "Fetching trust height/hash for state-sync..."
    local config_toml latest_height block_height trust_hash
    config_toml="$APP_HOME/config/config.toml"

    latest_height=$(curl -s --connect-timeout 5 --max-time 10 "$snap_rpc/block" | jq -r .result.block.header.height 2>/dev/null)
    if [[ "$latest_height" =~ ^[0-9]+$ ]]; then
        block_height=$((latest_height - 1000))
        trust_hash=$(curl -s --connect-timeout 5 --max-time 10 "$snap_rpc/block?height=$block_height" | jq -r .result.block_id.hash 2>/dev/null)
        echo -e "  Latest: $latest_height | Trust height: $block_height | Trust hash: $trust_hash"

        print_info "Configuring state-sync in config.toml..."
        sed -i.bak -E "s|^(enable[[:space:]]+=[[:space:]]+).*$|\1true| ;
s|^(rpc_servers[[:space:]]+=[[:space:]]+).*$|\1\"$snap_rpc,$snap_rpc\"| ;
s|^(trust_height[[:space:]]+=[[:space:]]+).*$|\1$block_height| ;
s|^(trust_hash[[:space:]]+=[[:space:]]+).*$|\1\"$trust_hash\"| ;
s|^(seeds[[:space:]]+=[[:space:]]+).*$|\1\"\"|" "$config_toml"
    else
        print_error "Could not fetch trust height/hash from $snap_rpc. State-sync NOT configured."
        print_warn "Node will sync via blocksync/p2p instead. You may want to retry or set [statesync] manually."
    fi

    print_info "Restoring priv_validator_state.json..."
    mv "$APP_HOME/priv_validator_state.json.backup" "$APP_HOME/data/priv_validator_state.json"

    print_info "Starting service..."
    sudo systemctl restart "$SERVICE_NAME"

    sleep 5
    local status
    status=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null)
    if [ "$status" = "active" ]; then
        print_success "$SERVICE_NAME: active"
        print_info "Run option 5 > View Logs > Follow to monitor state-sync progress."
    else
        print_error "$SERVICE_NAME: $status"
    fi

    press_enter
}

# 10. Hard Reset (full wipe + snapshot)
hard_reset() {
    print_banner
    echo -e "${BOLD}⬡ Hard Reset [${NETWORK}]${NC}"
    print_separator
    echo -e "${RED}${BOLD}⚠ WARNING: DESTRUCTIVE OPERATION${NC}"
    echo -e "${RED}This will:${NC}"
    echo -e "  - Stop the service"
    echo -e "  - Completely wipe ${APP_HOME}/data"
    echo -e "  - Keep config, genesis, validator keys (priv_validator_key.json)"
    echo -e "  - Offer to download latest snapshot automatically from itrocket"
    print_separator

    echo ""
    echo -e "${BOLD}Snapshot source:${NC} ${CYAN}${SNAPSHOT_BASE_URL}${NC}"
    print_info "Checking latest snapshot info..."
    local state_json snapshot_name snapshot_height snapshot_size snapshot_url
    state_json=$(curl -s --connect-timeout 5 --max-time 15 "${SNAPSHOT_BASE_URL}/.current_state.json" 2>/dev/null)
    snapshot_name=$(echo "$state_json" | jq -r '.snapshot_name' 2>/dev/null)
    snapshot_height=$(echo "$state_json" | jq -r '.snapshot_height' 2>/dev/null)
    snapshot_size=$(echo "$state_json" | jq -r '.snapshot_size' 2>/dev/null)

    if [ -n "$snapshot_name" ] && [ "$snapshot_name" != "null" ]; then
        snapshot_url="${SNAPSHOT_BASE_URL}/${snapshot_name}"
        echo -e "  ${BOLD}Latest snapshot:${NC} $snapshot_name"
        echo -e "  ${BOLD}Height:${NC} $snapshot_height"
        echo -e "  ${BOLD}Size:${NC} $snapshot_size"
        echo -e "  ${BOLD}URL:${NC} $snapshot_url"
    else
        print_warn "Could not auto-detect latest snapshot."
        snapshot_url=""
    fi

    echo ""
    echo -e "  ${GREEN}1)${NC} Use latest snapshot (auto-detected above)"
    echo -e "  ${GREEN}2)${NC} Enter custom snapshot URL"
    echo -e "  ${GREEN}3)${NC} Skip snapshot (sync from genesis / state-sync)"
    echo -e "  ${RED}0)${NC} Cancel"
    print_separator
    read -rp "$(echo -e ${CYAN}'Enter choice: '${NC})" snap_choice

    case $snap_choice in
        1)
            if [ -z "$snapshot_url" ]; then
                print_error "No auto-detected snapshot available. Cancelling."
                press_enter
                return
            fi
            ;;
        2)
            read -rp "$(echo -e ${CYAN}'Enter snapshot URL: '${NC})" snapshot_url
            ;;
        3)
            snapshot_url=""
            ;;
        *)
            print_info "Cancelled."
            press_enter
            return
            ;;
    esac

    read -rp "$(echo -e ${RED}'Type YES to confirm hard reset: '${NC})" confirm
    if [ "$confirm" != "YES" ]; then
        print_info "Cancelled."
        press_enter
        return
    fi

    print_info "Stopping service..."
    sudo systemctl stop "$SERVICE_NAME"

    print_info "Backing up priv_validator_state.json..."
    cp "$APP_HOME/data/priv_validator_state.json" /tmp/priv_validator_state.json.bak 2>/dev/null || true

    print_info "Wiping data directory..."
    rm -rf "${APP_HOME}/data"
    mkdir -p "${APP_HOME}/data"

    print_info "Restoring priv_validator_state.json..."
    cp /tmp/priv_validator_state.json.bak "$APP_HOME/data/priv_validator_state.json" 2>/dev/null || \
        echo '{"height":"0","round":0,"step":0}' > "$APP_HOME/data/priv_validator_state.json"

    if [ -n "$snapshot_url" ]; then
        print_info "Downloading and extracting snapshot from: $snapshot_url"
        print_info "This may take a while depending on your connection..."
        curl -L "$snapshot_url" | lz4 -dc | tar -xf - -C "$APP_HOME/data" 2>/dev/null || \
            { curl -L "$snapshot_url" -o /tmp/snapshot.tar.lz4 && lz4 -dc /tmp/snapshot.tar.lz4 | tar -xf - -C "$APP_HOME/data"; }
        rm -f /tmp/snapshot.tar.lz4
        print_success "Snapshot extracted"
    else
        print_warn "No snapshot used. Node will sync from genesis or use state-sync if configured."
    fi

    print_info "Starting service..."
    sudo systemctl start "$SERVICE_NAME"

    sleep 5
    local status
    status=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null)
    if [ "$status" = "active" ]; then
        print_success "$SERVICE_NAME: active"
    else
        print_error "$SERVICE_NAME: $status"
    fi

    press_enter
}

# 11. Environment Check
env_check() {
    print_banner
    echo -e "${BOLD}⬡ Environment Check [${NETWORK}]${NC}"
    print_separator

    echo -e "\n${BOLD}App Home:${NC} $APP_HOME"

    echo -e "\n${BOLD}Config:${NC}"
    if [ -f "$APP_HOME/config/client.toml" ]; then
        grep -E "chain-id|node" "$APP_HOME/config/client.toml" 2>/dev/null | sed 's/^/  /'
    fi

    echo -e "\n${BOLD}RPC/P2P Ports:${NC}"
    grep -E "^laddr" "$APP_HOME/config/config.toml" 2>/dev/null | sed 's/^/  /'

    echo -e "\n${BOLD}Binary:${NC}"
    if [ -n "$CELESTIA_BIN" ]; then
        echo -e "  Path: $CELESTIA_BIN"
        echo -n "  Version: "
        $CELESTIA_BIN version 2>/dev/null || echo "N/A"
    else
        echo -e "  ${YELLOW}celestia-appd not found${NC}"
    fi

    echo -e "\n${BOLD}System:${NC}"
    echo -e "  Hostname: $(hostname)"
    echo -e "  OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)"
    echo -e "  Kernel: $(uname -r)"
    echo -e "  CPU: $(nproc) cores"
    echo -e "  RAM: $(free -h | awk '/Mem:/{print $2}')"

    echo -e "\n${BOLD}Service:${NC} $SERVICE_NAME"

    press_enter
}

# 12. Swap Management
swap_management() {
    print_banner
    echo -e "${BOLD}⬡ Swap Management${NC}"
    print_separator

    echo -e "\n${BOLD}Current Status:${NC}"
    free -h | grep Swap
    echo -e "  Swappiness: $(cat /proc/sys/vm/swappiness)"

    echo ""
    echo -e "  ${GREEN}1)${NC} Clear swap now (swapoff -a && swapon -a)"
    echo -e "  ${GREEN}2)${NC} Set swappiness to 1"
    echo -e "  ${RED}0)${NC} Back"
    print_separator
    echo ""
    read -rp "$(echo -e ${CYAN}'Enter choice: '${NC})" choice

    case $choice in
        1)
            print_info "Clearing swap..."
            sudo swapoff -a && sudo swapon -a
            print_success "Swap cleared"
            free -h | grep Swap
            ;;
        2)
            echo 1 | sudo tee /proc/sys/vm/swappiness > /dev/null
            if ! grep -q "vm.swappiness=1" /etc/sysctl.conf 2>/dev/null; then
                echo "vm.swappiness=1" | sudo tee -a /etc/sysctl.conf > /dev/null
            fi
            sudo sysctl -p > /dev/null 2>&1
            print_success "Swappiness set to 1"
            ;;
        0) return ;;
    esac

    press_enter
}

# ============================================================
# MAIN MENU
# ============================================================

main_menu() {
    while true; do
        print_banner
        echo -e " ${BOLD}Network: ${CYAN}${NETWORK}${NC} | ${BOLD}Chain ID: ${CYAN}${CHAIN_ID}${NC}"
        echo -e " ${BOLD}RPC: ${CYAN}${LOCAL_RPC}${NC} | ${BOLD}Service: ${CYAN}${SERVICE_NAME}${NC}"
        print_separator
        echo -e "  ${GREEN} 1)${NC}  Quick Status Check"
        echo -e "  ${GREEN} 2)${NC}  Sync Verification"
        echo -e "  ${GREEN} 3)${NC}  Validator Info"
        echo -e "  ${GREEN} 4)${NC}  Service Status (detailed)"
        echo -e "  ${GREEN} 5)${NC}  View Logs"
        echo -e "  ${GREEN} 6)${NC}  Resource Monitor"
        echo -e "  ${GREEN} 7)${NC}  Peers Management"
        echo -e "  ${GREEN} 8)${NC}  Restart Service"
        echo -e "  ${YELLOW} 9)${NC}  Soft Reset (State Sync)"
        echo -e "  ${RED}10)${NC}  Hard Reset (full wipe + snapshot)"
        echo -e "  ${GREEN}11)${NC}  Environment Check"
        echo -e "  ${GREEN}12)${NC}  Swap Management"
        print_separator
        echo -e "  ${PURPLE} s)${NC}  Switch Network"
        echo -e "  ${RED} 0)${NC}  Exit"
        print_separator
        echo ""
        read -rp "$(echo -e ${CYAN}'Enter choice: '${NC})" choice

        case $choice in
            1)  quick_status ;;
            2)  sync_check ;;
            3)  validator_info ;;
            4)  service_status ;;
            5)  view_logs ;;
            6)  resource_monitor ;;
            7)  peers_management ;;
            8)  restart_service ;;
            9)  soft_reset ;;
            10) hard_reset ;;
            11) env_check ;;
            12) swap_management ;;
            s|S) select_network ;;
            0)
                echo -e "\n${GREEN}Goodbye! Happy validating! ⬡${NC}\n"
                exit 0
                ;;
            *)
                print_error "Invalid choice"
                sleep 1
                ;;
        esac
    done
}

# ============================================================
# ENTRY POINT
# ============================================================

if [ "$EUID" -ne 0 ]; then
    print_warn "Some features require root. Run with: sudo bash celestia-tool.sh"
fi

select_network
main_menu
