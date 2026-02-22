#!/bin/bash
#
# ETour Protocol - Remote Testing Session Startup
# Starts all services needed for cofounder remote testing
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FRONTEND_PORT="${FRONTEND_PORT:-3000}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  ETour Protocol - Remote Testing      ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Get public IP
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "unknown")
LOCAL_IP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | head -1 | awk '{print $2}')

echo -e "${GREEN}Network Info:${NC}"
echo "  Public IP:  $PUBLIC_IP"
echo "  Local IP:   $LOCAL_IP"
echo ""

# Check if Anvil is already running
if lsof -i :8545 >/dev/null 2>&1; then
    echo -e "${YELLOW}Anvil already running on port 8545${NC}"
else
    echo -e "${YELLOW}Starting Anvil...${NC}"
    echo "  Run in a separate terminal:"
    echo "  cd $PROJECT_DIR && ./start-anvil.sh"
    echo ""
    echo -e "${RED}Anvil must be running to continue. Start it and re-run this script.${NC}"
    exit 1
fi

# Verify Anvil is responding
echo -e "${GREEN}Verifying Anvil...${NC}"
CHAIN_ID=$(curl -s http://localhost:8545 \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

if [ "$CHAIN_ID" = "0x64aba" ]; then
    echo -e "  ${GREEN}✓ Anvil responding (Chain ID: 412346)${NC}"
elif [ -n "$CHAIN_ID" ]; then
    echo -e "  ${YELLOW}⚠ Anvil responding with different chain ID: $CHAIN_ID${NC}"
else
    echo -e "  ${RED}✗ Anvil not responding${NC}"
    exit 1
fi
echo ""

# Deploy contracts
echo -e "${GREEN}Deploying contracts...${NC}"
cd "$PROJECT_DIR"
npm run deploy:localhost 2>&1 | tail -20
echo ""

# Read deployed addresses
if [ -f "$PROJECT_DIR/deployments/localhost.json" ]; then
    echo -e "${GREEN}Deployed Contract Addresses:${NC}"
    cat "$PROJECT_DIR/deployments/localhost.json" | grep -E '"[A-Za-z]+":' | head -10
    echo ""
fi

# Check frontend and ngrok
echo -e "${GREEN}Frontend Exposure Options:${NC}"
echo ""
echo "Option 1: ngrok (you have it installed)"
echo "  ngrok http $FRONTEND_PORT"
echo ""
echo "Option 2: Cloudflare Tunnel (recommended for stable URLs)"
echo "  brew install cloudflared"
echo "  cloudflared tunnel login"
echo "  cloudflared tunnel create etour"
echo "  cloudflared tunnel run etour"
echo ""

# Summary for cofounder
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Share with Cofounder:                ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}RPC Connection:${NC}"
echo "  URL:      http://$PUBLIC_IP:8545"
echo "  Chain ID: 412346"
echo "  Symbol:   ETH"
echo ""
echo -e "${GREEN}Test Wallet (Account #1):${NC}"
echo "  Address:     0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
echo "  Private Key: 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
echo ""
echo -e "${GREEN}Documentation:${NC}"
echo "  Full setup guide: $PROJECT_DIR/COFOUNDER_SETUP.md"
echo ""
echo -e "${YELLOW}Remember:${NC}"
echo "  1. Ensure router port forwarding: 8545 -> $LOCAL_IP:8545"
echo "  2. macOS firewall must allow Anvil"
echo "  3. Start ngrok/tunnel for frontend access"
echo ""
