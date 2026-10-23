# Openwalla Standalone OpenWrt Installers

These scripts install individual Openwalla router helpers. The main installer at `openwrt-setup/setup-openwrt-router.sh` is a dispatcher that downloads and runs these feature bundles.

Use the dispatcher when you want a simple feature command:

```sh
sh openwrt-setup/setup-openwrt-router.sh netify
sh openwrt-setup/setup-openwrt-router.sh conntrack
sh openwrt-setup/setup-openwrt-router.sh device-speed
sh openwrt-setup/setup-openwrt-router.sh network-monitor dns speedtest
sh openwrt-setup/setup-openwrt-router.sh stack --with-netify
```

Run them from the repository root or from this folder on the router:

```sh
sh openwrt-setup/standalone/install-netify.sh
```

## Background Installation

The app uses one shared detached-job wrapper for Router Setup, individual
feature installs, component updates, removals, and package actions. SSH only
starts the job and polls its status; disconnecting does not stop installation.
Wrapper upload and log polling do not require `base64` or an extra encoding package.
To opt into the same behavior from a router terminal, put `--background` first:

```sh
sh openwrt-setup/setup-openwrt-router.sh --background --force devices
sh openwrt-setup/setup-openwrt-router.sh --background uninstall netify
sh openwrt-setup/standalone/install-netify.sh --background
```

The command returns `OPENWALLA_JOB|<job-id>` immediately. Read the job's log
and result on the router:

```sh
cat /tmp/openwalla/install/<job-id>/status.json
tail -f /tmp/openwalla/install/<job-id>/install.log
```

Completion comes from `state` and `exit_code` in `status.json`, not a success
message in the log. States are `starting`, `running`, `completed`, `failed`,
and `interrupted`. The wrapper prevents concurrent wrapped jobs. Do not run a
foreground installer alongside a background job. Existing foreground commands
remain unchanged. Temporary job files disappear on router reboot, and an
interrupted installation is never automatically repeated.

For low-space routers, the mobile app downloads only the selected installer
scripts and `standalone/lib/openwalla-standalone-common.sh` into `/tmp/openwalla`. The
shared helper fetches each required file from `openwrt-setup/files/` with
`wget` or `curl` only when that installer needs it.

Available installers:

- `install-standard-apps.sh` - uhttpd-mod-ubus, nlbwmon, vnstat2, sqlite, conntrack, and qrencode
- `install-adblock.sh` - OpenWrt adblock and LuCI adblock packages
- `install-qos-scripts.sh` - Smart Queue/SQM package support
- `install-banip.sh` - banIP package and country-blocking support
- `install-pbr.sh` - PBR package support
- `install-netify.sh` - netifyd plus Openwalla Netify collector
- `install-conntrack.sh` - connection flow collector backed by SQLite
- `install-device-speed.sh` - one-shot conntrack byte summary for live per-device speed
- `install-network-monitor.sh` - latency, outage, and Ethernet link monitoring
- `install-dns-monitor.sh` / `install-dns-test.sh` - DNS monitor output
- `install-speedtest-monitor.sh` - speedtest helper and cron schedule
- `install-usage-monitoring.sh` - vnStat/nlbwmon usage package support
- `install-devices-collector.sh` - device inventory SQLite collector keyed by MAC
- `install-device-bandwidth.sh` - per-device bandwidth collector and summary helper
- `install-internet-blocking.sh` - device internet-blocking pause helper and cron job
- `install-quarantine.sh` - device quarantine helper service
- `install-notifications-db.sh` - notifications SQLite helper
- `install-state-sync.sh` - Openwalla state backup/restore helper

Each installer keeps existing `/etc/config/openwalla` if present, installs the needed worker/init files, applies only that feature's UCI defaults, installs the shared rpcd ACL, and starts/enables only the relevant service.
