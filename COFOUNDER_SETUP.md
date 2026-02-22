# ETour Protocol - Remote Testing Setup Guide

> **Last Updated:** 2025-11-30
> **Status:** Ready for cofounder testing

---

## Quick Reference

| Item | Value |
|------|-------|
| **RPC URL** | `http://174.92.57.97:8545` |
| **Chain ID** | `412346` |
| **Currency Symbol** | `ETH` |
| **Network Name** | `ETour Anvil` |
| **Block Explorer** | *(none - local testnet)* |
| **Frontend** | See Section 4 below |

---

## 1. MetaMask Network Setup

### Add Custom Network

1. Open MetaMask browser extension
2. Click the network dropdown (top-left, shows current network)
3. Click **"Add network"** at the bottom
4. Click **"Add a network manually"**
5. Enter these exact values:

| Field | Value |
|-------|-------|
| Network Name | `ETour Anvil` |
| New RPC URL | `http://174.92.57.97:8545` |
| Chain ID | `412346` |
| Currency Symbol | `ETH` |
| Block Explorer URL | *(leave empty)* |

6. Click **"Save"**
7. Click **"Switch to ETour Anvil"** when prompted

### Verify Connection

After adding, you should see:
- Network name shows "ETour Anvil" in the dropdown
- No "Could not fetch chain ID" error
- Balance shows 0 ETH (until you import a test wallet)

---

## 2. Import Test Wallet

Anvil generates deterministic test wallets with 10,000 ETH each. Import one of these:

### Your Assigned Wallet: Account #1

```
Address:     0x70997970C51812dc3A010C7d01b50e0d17dc79C8
Private Key: 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
Balance:     10,000 ETH
```

### How to Import

1. In MetaMask, click the account selector (circle icon, top-right)
2. Click **"Add account or hardware wallet"**
3. Select **"Import account"**
4. In "Select Type", keep **"Private Key"** selected
5. Paste the private key: `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d`
6. Click **"Import"**

### Verify Import

- Account should show ~10,000 ETH balance
- Address should match: `0x70997970...79C8`

### Alternative Wallets

If you need additional accounts for testing:

| Account | Address | Private Key |
|---------|---------|-------------|
| #2 | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a` |
| #3 | `0x90F79bf6EB2c4f870365E785982E1f101E93b906` | `0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6` |
| #4 | `0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65` | `0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a` |

---

## 3. Contract Addresses

Currently deployed contracts:

| Contract | Address | Status |
|----------|---------|--------|
| ChessOnChain | `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512` | Deployed |
| TicTacChain | *Redeploy needed* | - |
| ETour | *Redeploy needed* | - |

> **Note:** Contracts are redeployed when Anvil restarts. Updated addresses will be shared via chat.

---

## 4. Frontend Access

### Option A: Cloudflare Tunnel (Recommended)

If configured, frontend will be available at a stable URL:
```
https://etour.YOUR_DOMAIN.com
```

### Option B: ngrok Tunnel

Temporary URL format:
```
https://xxxx-xxxx-xxxx.ngrok-free.app
```

> **Important:** ngrok URLs change each session. Get the current URL from Karim.

### First Visit

When accessing ngrok URLs, you'll see an interstitial page. Click **"Visit Site"** to proceed.

---

## 5. Troubleshooting

### "Could not fetch chain ID" or Connection Refused

**Possible causes:**
1. Anvil node not running on Karim's machine
2. Firewall blocking port 8545
3. Router not forwarding port 8545

**Quick test from your terminal:**
```bash
curl http://174.92.57.97:8545 \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```

Expected response: `{"jsonrpc":"2.0","id":1,"result":"0x64aba"}`

If this fails, contact Karim to verify the node is running.

### Transaction Stuck/Pending Forever

Anvil auto-mines blocks every 1 second. If transactions stay pending:

1. **Reset MetaMask account state:**
   - Settings → Advanced → Clear activity tab data

2. **Check you're on the right network:**
   - Chain ID should be `412346`
   - Not Ethereum Mainnet or other networks

### "Nonce too high" Error

This happens when MetaMask's nonce is out of sync with Anvil:

1. Settings → Advanced → Clear activity tab data
2. Try the transaction again

### Wrong Contract Address

If contract calls fail with "execution reverted":
- Contracts redeploy when Anvil restarts
- Ask Karim for the latest contract addresses
- Check the `deployments/localhost.json` file

---

## 6. Testing Checklist

Before starting tests, verify:

- [ ] MetaMask connected to "ETour Anvil" network
- [ ] Chain ID shows 412346
- [ ] Test wallet imported with ~10,000 ETH balance
- [ ] Can access frontend URL
- [ ] Frontend shows correct contract addresses

---

## 7. All Test Wallets Reference

All wallets derived from Anvil's default mnemonic:
```
test test test test test test test test test test test junk
```

| # | Address | Private Key |
|---|---------|-------------|
| 0 | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |
| 1 | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` |
| 2 | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a` |
| 3 | `0x90F79bf6EB2c4f870365E785982E1f101E93b906` | `0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6` |
| 4 | `0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65` | `0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a` |
| 5 | `0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc` | `0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba` |
| 6 | `0x976EA74026E726554dB657fA54763abd0C3a0aa9` | `0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e` |
| 7 | `0x14dC79964da2C08b23698B3D3cc7Ca32193d9955` | `0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356` |
| 8 | `0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f` | `0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97` |
| 9 | `0xa0Ee7A142d267C1f36714E4a8F75612F20a79720` | `0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6` |
| 10 | `0xBcd4042DE499D14e55001CcbB24a551F3b954096` | `0xf214f2b2cd398c806f84e317254e0f0b801d0643303237d97a22a48e01628897` |
| 11 | `0x71bE63f3384f5fb98995898A86B02Fb2426c5788` | `0x701b615bbdfb9de65240bc28bd21bbc0d996645a3dd57e7b12bc2bdf6f192c82` |
| 12 | `0xFABB0ac9d68B0B445fB7357272Ff202C5651694a` | `0xa267530f49f8280200edf313ee7af6b827f2a8bce2897751d06a843f644967b1` |
| 13 | `0x1CBd3b2770909D4e10f157cABC84C7264073C9Ec` | `0x47c99abed3324a2707c28affff1267e45918ec8c3f20b8aa892e8b065d2942dd` |
| 14 | `0xdF3e18d64BC6A983f673Ab319CCaE4f1a57C7097` | `0xc526ee95bf44d8fc405a158bb884d9d1238d99f0612e9f33d006bb0789009aaa` |
| 15 | `0xcd3B766CCDd6AE721141F452C550Ca635964ce71` | `0x8166f546bab6da521a8369cab06c5d2b9e46670292d85c875ee9ec20e84ffb61` |
| 16 | `0x2546BcD3c84621e976D8185a91A922aE77ECEc30` | `0xea6c44ac03bff858b476bba40716402b03e41b8e97e276d1baec7c37d42484a0` |
| 17 | `0xbDA5747bFD65F08deb54cb465eB87D40e51B197E` | `0x689af8efa8c651a91ad287602527f3af2fe9f6501a7ac4b061667b5a93e037fd` |
| 18 | `0xdD2FD4581271e230360230F9337D5c0430Bf44C0` | `0xde9be858da4a475276426320d5e9262ecfc3ba460bfac56360bfa6c4c28b4ee0` |
| 19 | `0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199` | `0xdf57089febbacf7ba0bc227dafbffa9fc08a93fdc68e1e42411a14efcf23656e` |
| 20 | `0x09DB0a93B389bEF724429898f539AEB7ac2Dd55f` | `0xeaa861a9a01391ed3d587d8a5a84ca56ee277629a8b02c22093a419bf240e65d` |
| 21 | `0x02484cb50AAC86Eae85610D6f4Bf026f30f6627D` | `0xa95bd7ea7e61801df099d551cc53bcf1c5c03da182e59ee6f9dd52c270436196` |
| 22 | `0x08135Da0A343E492FA2d4282F2AE34c6c5CC1BbE` | `0x725fd1619b2653b7ff1806bf29ae11d0568606d83777afd5b1f2e649bd5132a9` |
| 23 | `0x5E661B79FE2D3F6cE70F5AAC07d8Cd9abb2743F1` | `0xbea6eb0383079abc3cd7b81c9c6eb5db78feb9e1f31bba2e5ed286ce6f3a9e2a` |
| 24 | `0x61097BA76cD906d2ba4FD106E757f7Eb455fc295` | `0x09ae3ec66dbee9b780e9f0850596dbb34c0a75c83afb1b9de8feae0db2144cb4` |
| 25 | `0xDf37F81dAAD2b0327A0A50003769C8e697E2aD47` | `0x1ef9ff0eb925974acbc144fc88a8af5df2235de4c1205a9631ad75a8c3f2ce09` |
| 26 | `0x553BC17A05702530097c3677091C5BB47a3a7931` | `0xac3dee22fe997cf4e6c263e5d8d3b05599adaca49ec53b7ff6f48d4a58ac829e` |
| 27 | `0x87BdCE72c06C21cd96219BD8521bDF1F42C78b5e` | `0x4bdf2d6209b8f8e96c260b5e53be8e59768aa660a95b7a17dae0f4f5bfb2f8ae` |
| 28 | `0x40Fc963A729c542424cD800349a7E4Ecc4896624` | `0x7a60407f3459c47de6e4c53cc30f53e13e175d13d6a5f666a068e2a52d5bae11` |
| 29 | `0x9DCCe783B6464611f38631e6C851bf441907c710` | `0x4f69e5d2e557e4185d496d36f93af4ed497e4f7a76e171c2cd5ae5e5cf82c840` |

> **Account #0** (`0xf39F...`) is used for contract deployment. Use accounts #1-29 for testing.

---

## 8. Security Notes

**These are TEST wallets only:**
- Never use these private keys for real funds
- Never send real ETH to these addresses
- The mnemonic is publicly known (Anvil default)
- This setup is for development testing only

---

*ETour Protocol - Remote Testing Environment*
