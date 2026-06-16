# ⬡ Celestia Node Management Tool

A comprehensive CLI tool for managing Celestia consensus node operations on both **Mainnet** and **Mocha Testnet**.

Built by [MegaNode ]([https://meganode.top/] — an independent Celestia validator operator.

## Features

| # | Feature | Description |
|---|---------|-------------|
| 1 | **Quick Status** | Service health, sync status, peer count, RAM at a glance |
| 2 | **Sync Verification** | Compare local height vs network reference height |
| 3 | **Validator Info** | Validator pubkey, node ID, voting power, active set status |
| 4 | **Service Status** | Detailed systemd status for celestia-appd |
| 5 | **View Logs** | Browse recent logs, follow realtime, filter proposals/errors/consensus issues |
| 6 | **Resource Monitor** | CPU affinity, RAM, disk usage, data directory size, time sync |
| 7 | **Peers Management** | Connected peer count, persistent peers, connected peer IPs |
| 8 | **Restart Service** | Safely restart celestia-appd with status verification |
| 9 | **Soft Reset** | State-sync reset — backup validator state, `unsafe-reset-all`, update peers, configure trust height/hash, restore state |
| 10 | **Hard Reset** | Full data wipe with validator state backup + auto-fetch latest snapshot from itrocket |
| 11 | **Environment Check** | Config, binary version, ports, system info |
| 12 | **Swap Management** | Clear swap, set swappiness |

## Requirements

- Ubuntu 22.04 / 24.04
- Celestia consensus node installed ([official docs](https://docs.celestia.org/nodes/consensus-node))
- `jq`, `curl` installed
- Root or sudo access
- Service managed via systemd (`celestia-appd`, `celestia`, or `celestiad`)

## Installation

```bash
git clone https://github.com/<your-username>/celestia-node-tool.git
cd celestia-node-tool
chmod +x celestia-tool.sh
sudo bash celestia-tool.sh
```

Or one-liner:

```bash
curl -sSL https://raw.githubusercontent.com/<your-username>/celestia-node-tool/main/celestia-tool.sh -o celestia-tool.sh && chmod +x celestia-tool.sh && sudo bash celestia-tool.sh
```

## Usage

1. Select network: **Mainnet** or **Mocha Testnet**
2. Choose from the menu (1-12)
3. Follow on-screen instructions

```
╔══════════════════════════════════════════════════════╗
║ ⬡ CELESTIA NODE MANAGEMENT TOOL v1.0                ║
║ MegaNode                                    ║
╚══════════════════════════════════════════════════════╝

 Network: MOCHA TESTNET | Chain ID: mocha-4
 RPC: http://localhost:26657 | Service: celestia-appd
──────────────────────────────────────────────────────
   1)  Quick Status Check
   2)  Sync Verification
   3)  Validator Info
   4)  Service Status (detailed)
   5)  View Logs
   6)  Resource Monitor
   7)  Peers Management
   8)  Restart Service
   9)  Soft Reset (State Sync)
  10)  Hard Reset (full wipe + snapshot)
  11)  Environment Check
  12)  Swap Management
──────────────────────────────────────────────────────
   s)  Switch Network
   0)  Exit
```

## Auto-Detection

The tool automatically tries to detect:

- **App home directory**: defaults to `$HOME/.celestia-app`, falls back to `/root/.celestia-app` if running via sudo and the user's home doesn't have it
- **RPC port**: parsed from `config.toml` (`[rpc] laddr`)
- **Service name**: `celestia-appd`, `celestia`, `celestia-mocha`, `celestiad`
- **Latest snapshot**: fetched from itrocket's `.current_state.json` for the selected network

If auto-detection fails, edit the script's global variables (`APP_HOME`, `RPC_PORT`, `SERVICE_NAME`, `SNAPSHOT_BASE_URL`) to match your setup.

## Snapshot & Peer Sources

Data is sourced from [ITRocket](https://itrocket.net), a public Cosmos ecosystem service provider:

| Network | Snapshot Source | RPC (for state-sync) |
|---------|-----------------|----------------------|
| Mainnet | `server-1.itrocket.net/mainnet/celestia` | `celestia-mainnet-rpc.itrocket.net` |
| Mocha Testnet | `server-6.itrocket.net/testnet/celestia` | `celestia-testnet-rpc.itrocket.net` |

These are third-party community services by MegaNode. Always verify peer/RPC sources you trust before running state-sync or snapshot restore on mainnet.

## Soft Reset vs Hard Reset

| | Soft Reset (State Sync) | Hard Reset |
|---|-----------|-----------|
| Stops service | ✅ | ✅ |
| Backs up validator state | ✅ | ✅ |
| Resets chain data | ✅ (`unsafe-reset-all`) | ✅ (full wipe of `data/`) |
| Updates persistent_peers | ✅ | ❌ |
| Configures trust height/hash | ✅ | ❌ |
| Snapshot restore | ❌ (syncs live via state-sync) | ✅ (auto-fetches latest from itrocket) |
| Speed | Fast (syncs last ~1000 blocks + light blocks forward) | Slower (downloads full snapshot, several GB) |
| Use when | Node stuck, minor corruption, want quick recovery | State-sync fails, severe corruption, want a known-good full state |

**⚠️ Important — Double-signing risk:** Both Soft Reset and Hard Reset back up and restore `priv_validator_state.json` to help prevent double-signing after a reset. However, **always verify your validator is not running on another machine simultaneously** before restarting after any reset. Running the same validator key on two nodes at once can result in slashing.

## Safety

- **Read-only by default** — status checks and monitoring don't modify anything
- **Confirmation required** — Soft Reset and Hard Reset require explicit confirmation
- **Hard Reset requires typing `YES`** — extra safety for destructive operations
- **No private keys stored or transmitted** — the tool only reads local config and public RPC data
- **Open source** — review the code before running

## Testing Recommendation

**Test on Mocha Testnet first** before using on Mainnet, especially the Soft Reset and Hard Reset options. Validate that:

- Auto-detected paths and ports match your setup
- Your snapshot provider URL works with the extraction method used
- The validator restarts correctly without double-signing

## Performance Tuning (Recommended)

For optimal node performance when running alongside other services (e.g. Monad):

- **Swap**: Set `vm.swappiness=1` (use option 12)
- **CPU Isolation**: Dedicate CPUs to celestia-appd via systemd `AllowedCPUs`/`CPUAffinity`
- **Time Sync**: Install `chrony` for accurate NTP
- **Separate Disk**: Use a dedicated NVMe/SSD for `~/.celestia-app/data`

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-feature`)
3. Commit your changes (`git commit -m 'Add new feature'`)
4. Push to the branch (`git push origin feature/new-feature`)
5. Open a Pull Request

## License

MIT License — see [LICENSE](LICENSE) for details.

## Disclaimer

This tool is provided as-is for the Celestia validator community. It is not officially affiliated with or endorsed by Celestia team. Always review the code before running on production systems, especially reset operations. Use at your own risk.

## Links

- [Celestia Official Docs](https://docs.celestia.org)
- [Celestia Consensus Node Setup](https://docs.celestia.org/nodes/consensus-node)
- [MegaNode](https://meganode.top/)

