import "@nomicfoundation/hardhat-toolbox";
import dotenv from "dotenv";
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

dotenv.config();

/** @type import('hardhat/config').HardhatUserConfig */
export default {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1  // Low runs to minimize deployment size
      },
      viaIR: true  // Use IR-based code generator to avoid stack too deep errors
      // Note: evmVersion "cancun" requires Solidity 0.8.24+
      // Keeping default (Shanghai) for 0.8.20 compatibility
      // Runtime will still work with Cancun hardfork on Anvil
    }
  },
  etherscan: {
    apiKey: '2R1PT31B2HU2TS1IPJCFX9S89GI4BS4SH4',
    customChains: [
      {
        network: "arbitrum",
        chainId: 42161,
        urls: {
          apiURL: "https://api.arbiscan.io/api",
          browserURL: "https://arbiscan.io"
        }
      },
      {
        network: "arbitrumSepolia",
        chainId: 421614,
        urls: {
          apiURL: "https://api-sepolia.arbiscan.io/api",
          browserURL: "https://sepolia.arbiscan.io"
        }
      },
      {
        network: "optimismSepolia",
        chainId: 11155420,
        urls: {
          apiURL: "https://api-sepolia-optimistic.etherscan.io/api",
          browserURL: "https://sepolia-optimism.etherscan.io"
        }
      },
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org"
        }
      },
      {
        network: "optimism",
        chainId: 10,
        urls: {
          apiURL: "https://api-optimistic.etherscan.io/api",
          browserURL: "https://optimistic.etherscan.io"
        }
      },
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org"
        }
      },
      {
        network: "polygon",
        chainId: 137,
        urls: {
          apiURL: "https://api.polygonscan.com/api",
          browserURL: "https://polygonscan.com"
        }
      }
    ]
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  networks: {
    hardhat: {
      chainId: 31337,
      accounts: {
        count: 250, // Increased to support 224-player max capacity tests
        accountsBalance: "10000000000000000000000" // 10000 ETH per account
      },
      mining: {
        auto: true,
        interval: 0
      },
      allowUnlimitedContractSize: true,  // Allow larger contracts in development
      blockGasLimit: 300000000  // 300M gas block limit for large contract deployment
      // Note: Cancun hardfork for runtime is set in Anvil config (start-anvil.sh)
      // Hardhat's built-in network uses Shanghai by default
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 412346,
      gas: 1000000000, // 1B gas for complex deployment
      gasPrice: 100000000, // 0.1 Gwei
      blockGasLimit: 1125899906842624, // Match Anvil's high gas limit
      allowUnlimitedContractSize: true
    },
    // Arbitrum Local Nitro Node (Anvil simulating L2)
    arbitrumLocal: {
      url: process.env.ARBITRUM_LOCAL_RPC_URL || "http://127.0.0.1:8547",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [
        // Hardhat's default test accounts - DO NOT use these in production!
        "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", // Account #0
        "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d", // Account #1
        "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"  // Account #2
      ],
      chainId: 412346,
      gas: 1000000000, // Increase gas limit to 1B for complex contract deployment
      gasPrice: 100000000, // 0.1 Gwei - realistic Arbitrum L2 gas price
      blockGasLimit: 1125899906842624, // Arbitrum's high gas limit
      allowUnlimitedContractSize: true, // Allow larger contracts in L2 development
      // Force legacy transactions (type 0) to ensure consistent gas pricing
      type: 0
    },
    // L2 Networks - Testnets
    arbitrumSepolia: {
      url: process.env.ARBITRUM_SEPOLIA_RPC_URL || "https://sepolia-rollup.arbitrum.io/rpc",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 421614
    },
    optimismSepolia: {
      url: process.env.OPTIMISM_SEPOLIA_RPC_URL || "https://sepolia.optimism.io",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 11155420
    },
    baseSepolia: {
      url: process.env.BASE_SEPOLIA_RPC_URL || "https://sepolia.base.org",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 84532
    },
    // L2 Networks - Mainnets
    arbitrum: {
      url: process.env.ARBITRUM_RPC_URL || "https://arb1.arbitrum.io/rpc",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 42161
    },
    optimism: {
      url: process.env.OPTIMISM_RPC_URL || "https://mainnet.optimism.io",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 10
    },
    base: {
      url: process.env.BASE_RPC_URL || "https://mainnet.base.org",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 8453
    },
    polygon: {
      url: process.env.POLYGON_RPC_URL || "https://polygon-rpc.com",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 137
    }
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS ? true : false,
    currency: "USD"
  },
  mocha: {
    // Global test setup file (injects logger) - must be CommonJS
    require: [join(__dirname, 'test', 'setup.cjs')],
    // Configure timeout (40 seconds default)
    timeout: 40000,
    // Use custom reporter if SCIENTIFIC_REPORT env var is set
    reporter: process.env.SCIENTIFIC_REPORT === 'true'
      ? join(__dirname, 'test', 'reporter', 'scientific-reporter.cjs')
      : 'spec'
  }
};
