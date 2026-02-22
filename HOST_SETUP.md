# ETour Protocol - Host Setup Guide

> Instructions for Karim to configure the remote testing environment

---

## Quick Status Check

Run these commands to verify your setup:

```bash
# Check Anvil is running and bound to all interfaces
lsof -i :8545

# Expected output should show:
# anvil ... TCP *:8545 (LISTEN)

# Test local RPC
curl -s http://localhost:8545 \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'

# Expected: {"jsonrpc":"2.0","id":1,"result":"0x64b1a"}
```

---

## 1. Anvil Configuration

Your `start-anvil.sh` is already correctly configured:

```bash
anvil \
  --host 0.0.0.0 \      # Binds to all network interfaces (required for remote access)
  --port 8545 \         # Standard Ethereum RPC port
  --chain-id 412346 \   # Custom chain ID for ETour testnet
  ...
```

**Start Anvil:**
```bash
cd /Users/karim/Documents/workspace/zero-trust/e-tour
./start-anvil.sh
```

**Keep Anvil Running:**
- Run in a dedicated terminal tab
- Or use `tmux`/`screen` for persistence
- Or run as background process: `nohup ./start-anvil.sh > anvil.log 2>&1 &`

---

## 2. macOS Firewall Configuration

### Option A: System Preferences (GUI)

1. Open **System Settings** → **Network** → **Firewall**
2. Click **Options...**
3. Ensure "Block all incoming connections" is **OFF**
4. Add Anvil to allowed apps if prompted

### Option B: Command Line

```bash
# Check firewall status
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate

# If firewall is enabled, add Anvil to allowed apps
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /Users/karim/.foundry/bin/anvil
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /Users/karim/.foundry/bin/anvil

# Verify Anvil is allowed
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --listapps | grep -i anvil
```

### Option C: Temporarily Disable Firewall (Testing Only)

```bash
# Disable firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off

# Re-enable after testing
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
```

---

## 3. Router Port Forwarding

You need to forward port 8545 from your router to your Mac.

### Your Network Info

| Item | Value |
|------|-------|
| Public IP | `174.92.57.97` |
| Local IP | `192.168.2.164` |
| Port | `8545` |

### Generic Router Instructions

1. **Access Router Admin:**
   - Open browser to `http://192.168.2.1` (common default)
   - Or check router label for admin URL
   - Login with admin credentials

2. **Find Port Forwarding:**
   - Look for: "Port Forwarding", "NAT", "Virtual Server", or "Applications"
   - Usually under "Advanced" or "Security" settings

3. **Create Port Forward Rule:**

   | Field | Value |
   |-------|-------|
   | Service Name | `Anvil RPC` |
   | Protocol | `TCP` |
   | External Port | `8545` |
   | Internal IP | `192.168.2.164` |
   | Internal Port | `8545` |
   | Enable | Yes |

4. **Save and Apply**

### Common Router Interfaces

**Bell Home Hub:**
- Advanced Settings → Port Forwarding
- Add Custom Service

**Rogers Ignite:**
- Login to My Rogers app or web portal
- Network → Port Forwarding

**TP-Link:**
- Advanced → NAT Forwarding → Port Forwarding

**ASUS:**
- WAN → Port Forwarding

### Verify Port Forward

After configuring, test from an external network (e.g., mobile hotspot):

```bash
curl http://174.92.57.97:8545 \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```

Or use online tool: https://www.yougetsignal.com/tools/open-ports/
- Enter your IP: `174.92.57.97`
- Enter port: `8545`

---

## 4. Frontend Exposure Options

### Comparison

| Solution | Pros | Cons | Best For |
|----------|------|------|----------|
| **ngrok** | Easy setup, HTTPS | URL changes, free tier limits | Quick testing |
| **Cloudflare Tunnel** | Stable URL, free, secure | Requires domain | Extended testing |
| **Tailscale** | No port forwarding needed | Both users need Tailscale | Private team access |
| **Direct port forward** | Simple | HTTP only, exposes IP | RPC only (not frontend) |

### Recommendation: Cloudflare Tunnel

For your scenario (extended testing with cofounder), Cloudflare Tunnel is best:
- Stable, custom URL (e.g., `etour.yourdomain.com`)
- Free tier is sufficient
- HTTPS automatic
- No router port forwarding needed for frontend

---

## 5. Cloudflare Tunnel Setup (Recommended)

### Prerequisites
- A domain with DNS on Cloudflare (free tier works)
- Cloudflare account

### Install cloudflared

```bash
brew install cloudflared
```

### Authenticate

```bash
cloudflared tunnel login
# Opens browser, select your domain
```

### Create Tunnel

```bash
# Create a named tunnel
cloudflared tunnel create etour

# Note the tunnel ID from output (e.g., a1b2c3d4-...)
```

### Configure Tunnel

Create `~/.cloudflared/config.yml`:

```yaml
tunnel: etour
credentials-file: /Users/karim/.cloudflared/<TUNNEL_ID>.json

ingress:
  # Frontend (React/Vite typically runs on 5173 or 3000)
  - hostname: etour.yourdomain.com
    service: http://localhost:3000

  # RPC endpoint (optional - can use direct port forward instead)
  - hostname: rpc.etour.yourdomain.com
    service: http://localhost:8545

  # Catch-all (required)
  - service: http_status:404
```

### Add DNS Records

```bash
cloudflared tunnel route dns etour etour.yourdomain.com
cloudflared tunnel route dns etour rpc.etour.yourdomain.com
```

### Run Tunnel

```bash
# Foreground (for testing)
cloudflared tunnel run etour

# Or install as service (persistent)
sudo cloudflared service install
sudo launchctl start com.cloudflare.cloudflared
```

---

## 6. ngrok Setup (Alternative)

### Install

```bash
brew install ngrok
```

### Authenticate (Free Account)

```bash
# Sign up at https://ngrok.com and get your authtoken
ngrok config add-authtoken YOUR_TOKEN
```

### Expose Frontend

```bash
# Assuming frontend runs on port 3000
ngrok http 3000
```

### Get URL

ngrok will display:
```
Forwarding    https://xxxx-xxxx-xxxx.ngrok-free.app -> http://localhost:3000
```

Share the `https://...ngrok-free.app` URL with your cofounder.

### Limitations (Free Tier)
- URL changes every session
- 40 connections/minute
- ngrok branding/interstitial page

---

## 7. Complete Startup Checklist

Run these steps each testing session:

### Terminal 1: Start Anvil
```bash
cd /Users/karim/Documents/workspace/zero-trust/e-tour
./start-anvil.sh
```

### Terminal 2: Deploy Contracts
```bash
cd /Users/karim/Documents/workspace/zero-trust/e-tour
npm run deploy:localhost
```

### Terminal 3: Start Frontend
```bash
cd /path/to/frontend
npm run dev
```

### Terminal 4: Start Tunnel
```bash
# Using Cloudflare
cloudflared tunnel run etour

# OR using ngrok
ngrok http 3000
```

### Notify Cofounder
Share:
1. Frontend URL (from tunnel)
2. Updated contract addresses (from deployment output)
3. Confirm Anvil is running

---

## 8. Troubleshooting

### Cofounder Can't Connect to RPC

1. **Check Anvil is running:**
   ```bash
   lsof -i :8545
   ```

2. **Check firewall:**
   ```bash
   sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
   ```

3. **Check port forward:**
   - Test from mobile hotspot
   - Use port checker website

4. **Check public IP hasn't changed:**
   ```bash
   curl ifconfig.me
   ```
   If changed, update `COFOUNDER_SETUP.md`

### Frontend Not Accessible

1. **Check frontend is running:**
   ```bash
   lsof -i :3000  # or whatever port
   ```

2. **Check tunnel is running:**
   ```bash
   ps aux | grep -E "cloudflared|ngrok"
   ```

3. **Restart tunnel if needed**

### Contract Addresses Changed

After Anvil restart:
1. Redeploy contracts
2. Update `COFOUNDER_SETUP.md` with new addresses
3. Notify cofounder to update frontend config

---

## 9. Security Considerations

**For Development Testing Only:**

- Port 8545 exposed to internet accepts RPC from anyone
- Test wallets have publicly known private keys
- No authentication on Anvil RPC
- Don't use for real funds or production

**Mitigations:**
- Only keep port forward active during testing
- Consider Tailscale for truly private access
- Monitor Anvil logs for unexpected activity

---

*Host configuration guide for ETour Protocol remote testing*
