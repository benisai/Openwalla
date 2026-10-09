# Openwalla Server

Openwalla Server is the external Detailed Flow collector for Openwalla. It connects to one OpenWrt router's Netify TCP stream, stores hybrid relational and original JSON flow data in SQLite, and exposes it to the Openwalla app through a REST API.

The existing on-router collector remains available. Choose **Local router** or **Openwalla Server** from Flow Settings in the app.

## Router preparation

Netify must listen on the router LAN address instead of only `127.0.0.1`. Openwalla applies this setting when external mode is saved. TCP port `7150` should remain restricted to the LAN.

## Start

Run the bootstrap installer from the directory where Openwalla Server should be installed:

```sh
wget -qO openwalla-server-install.sh https://raw.githubusercontent.com/benisai/Openwalla/main/openwalla-server/install.sh
chmod +x openwalla-server-install.sh
./openwalla-server-install.sh
```

The installer downloads the current runtime files into `./openwalla-server`, creates a persistent `.env`, and runs `docker compose up -d --build`. Edit `openwalla-server/.env` to set the router LAN address and optional API token, then rerun the installer to apply the settings.

For a manual installation, copy `.env.example` to `.env`, update the values, then run:

```sh
docker compose up -d --build
```

The API is available at `http://<docker-host>:8080`. Enter that URL under **Network Flows > Flow Settings**.

Set `OPENWALLA_API_TOKEN` to require `Authorization: Bearer <token>`. Enter the same token in the app. Leaving it empty allows LAN access without authentication.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `OPENWALLA_NETIFY_HOST` | `192.168.1.1` | Router running Netify |
| `OPENWALLA_NETIFY_PORT` | `7150` | Netify TCP stream port |
| `OPENWALLA_ROUTER_LAN_IP` | empty | Router traffic excluded from stored flows |
| `OPENWALLA_DATABASE_PATH` | `/data/openwalla-netify.sqlite` | SQLite database path |
| `OPENWALLA_RETENTION_HOURS` | `24` | Detailed flow retention |
| `OPENWALLA_API_TOKEN` | empty | Optional REST bearer token |

## API

- `GET /api/v1/health`
- `GET /api/v1/status`
- `GET /api/v1/flows?limit=250&offset=0&hours=24`
- `GET /api/v1/flows/count?hours=24`
- `POST /api/v1/maintenance/prune`

Flow endpoints also accept `protocol`, `mac`, and `search` query parameters.
