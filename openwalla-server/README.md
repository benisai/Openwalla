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

The dashboard and API are available at `http://<docker-host>:2020`. Enter that URL under **Network Flows > Flow Settings**.

Openwalla Server does not require Traefik, Caddy, or another reverse proxy. Docker publishes the dashboard/API directly on `OPENWALLA_API_PORT`. A reverse proxy is optional when you want HTTPS and a hostname.

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
| `OPENWALLA_UI_USERNAME` | `admin` | Dashboard login name |
| `OPENWALLA_UI_PASSWORD` | empty | Dashboard password; empty disables UI login |
| `OPENWALLA_UI_PASSWORD_HASH` | empty | Scrypt password hash used instead of the plain password |
| `OPENWALLA_SESSION_HOURS` | `24` | Dashboard session lifetime |
| `OPENWALLA_AUTH_MAX_FAILURES` | `5` | Failed logins allowed during the tracking window |
| `OPENWALLA_AUTH_WINDOW_SECONDS` | `900` | Failed-login tracking window |
| `OPENWALLA_AUTH_BAN_SECONDS` | `3600` | Temporary IP ban duration |
| `OPENWALLA_AUTH_BAN_PATH` | `/data/openwalla-auth-bans.json` | Persistent IP-ban state file |
| `OPENWALLA_AUTH_TRUST_PROXY` | `false` | Trust the first `X-Forwarded-For` address |
| `OPENWALLA_AUTH_SECURE_COOKIE` | `false` | Send the session cookie over HTTPS only |
| `OPENWALLA_DOCKER_NETWORK` | `openwalla` | Docker network created for Openwalla services and optional proxies |
| `OPENWALLA_TUNNEL_GATEWAY_BIND` | `0.0.0.0` | Host address accepting the router's outbound SSH tunnel |
| `OPENWALLA_TUNNEL_SSH_PORT` | `2222` | Public SSH gateway port used by the router |
| `OPENWALLA_TUNNEL_HTTP_BIND` | `127.0.0.1` | Host address exposing tunneled LuCI |
| `OPENWALLA_TUNNEL_HTTP_PORT` | `10080` | Host and container port for tunneled LuCI |
| `OPENWALLA_TUNNEL_REMOTE_SSH_BIND` | `127.0.0.1` | Host address exposing tunneled router SSH |
| `OPENWALLA_TUNNEL_REMOTE_SSH_PORT` | `10022` | Host and container port for tunneled router SSH |

## API

- `GET /api/v1/health`
- `GET /api/v1/status`
- `GET /api/v1/dashboard?hours=24`
- `GET /api/v1/tunnel/status`
- `GET /api/v1/flows?limit=250&offset=0&hours=24`
- `GET /api/v1/flows/count?hours=24`
- `POST /api/v1/maintenance/prune`

Flow endpoints also accept `protocol`, `mac`, and `search` query parameters.

The web dashboard displays collector health, reverse-tunnel reachability, flow and device totals, top detected applications, and recent flows. It refreshes every 10 seconds. When `OPENWALLA_API_TOKEN` is configured, the dashboard asks for the token and stores it in the browser on that device.

## Dashboard authentication

Set `OPENWALLA_UI_USERNAME` and either `OPENWALLA_UI_PASSWORD` or `OPENWALLA_UI_PASSWORD_HASH` in `.env`, then recreate the service:

```sh
docker compose up -d --build
```

For a hashed password, generate an scrypt value without placing the password in shell history:

```sh
docker compose exec openwalla-server python -m app.auth
```

Paste the resulting value into `OPENWALLA_UI_PASSWORD_HASH`, leave `OPENWALLA_UI_PASSWORD` empty, and recreate the service. Dashboard sessions use signed `HttpOnly`, `SameSite=Strict` cookies. Set `OPENWALLA_AUTH_SECURE_COOKIE=true` when the dashboard is available exclusively through HTTPS.

The server temporarily bans a client address after the configured number of failed logins. The dashboard Security panel displays the active policy and current temporary bans. Active bans are written atomically to `/data/openwalla-auth-bans.json`, which is preserved by the existing `./data:/data` volume, and are restored after container updates or restarts. Expired entries are removed automatically.

When Traefik is the only path to Openwalla Server, set `OPENWALLA_AUTH_TRUST_PROXY=true` so limits apply to the original client address. Keep it disabled if clients can connect directly, because an untrusted client could forge `X-Forwarded-For`.

`OPENWALLA_API_TOKEN` remains separate from dashboard authentication and should be retained for the Openwalla phone app and other API clients.

## Optional reverse tunnel

Openwalla Server includes an optional SSH gateway for reaching a router behind NAT without opening an inbound router firewall port. The router initiates a key-authenticated outbound SSH connection to the server. LuCI is forwarded to port `10080` and router SSH to port `10022`.

Both forwarded services bind to `127.0.0.1` on the Docker host by default. This works directly with a host-installed Caddy, Traefik, nginx, or another proxy without exposing LuCI or router SSH publicly. The router-facing gateway listens on port `2222` on all host interfaces so the remote router can establish its outbound connection.

The first implementation supports one router per Openwalla Server instance.

### 1. Prepare the router

Download the router installer and run it with the public VPS hostname or IP:

```sh
wget -qO /tmp/install-openwalla-tunnel.sh https://raw.githubusercontent.com/benisai/Openwalla/main/openwalla-server/tunnel/install-router.sh
chmod +x /tmp/install-openwalla-tunnel.sh
OPENWALLA_TUNNEL_HOST=vps.example.com /tmp/install-openwalla-tunnel.sh
```

The installer creates a dedicated key and prints its public key. It does not copy the private key off the router.

### 2. Authorize the router

Paste the printed public-key line into:

```text
openwalla-server/tunnel-data/authorized_keys
```

Start the optional gateway:

```sh
docker compose --profile tunnel up -d --build
```

Restart the router connection:

```sh
/etc/init.d/openwalla-tunnel restart
```

The OpenWrt `procd` service reconnects automatically after a network interruption or VPS restart.

### 3. Open LuCI directly or through a proxy

From the Docker host, tunneled LuCI is available at:

```text
http://127.0.0.1:10080
```

Tunneled router SSH is available with:

```sh
ssh -p 10022 root@127.0.0.1
```

To access LuCI directly from another trusted machine without a reverse proxy, set a LAN address in `.env`, then recreate the tunnel service:

```env
OPENWALLA_TUNNEL_HTTP_BIND=192.168.1.10
```

Avoid `0.0.0.0` unless a host firewall restricts access. Publishing tunneled LuCI directly to the internet is not recommended.

### Caddy on the Docker host

Use `tunnel/Caddyfile.example`, or add:

```caddyfile
router.example.com {
    reverse_proxy 127.0.0.1:10080
}
```

### Containerized reverse proxies

Compose creates a regular Docker network named `openwalla`; it does not require an existing proxy network. Connect the proxy container to that network and route to:

```text
http://openwalla-tunnel:10080
```

For example:

```sh
docker network connect openwalla caddy
```

Replace `caddy` with the actual proxy container name. For a persistent Compose configuration, add the network to the proxy's Compose file:

```yaml
services:
  caddy:
    networks:
      - default
      - openwalla

networks:
  openwalla:
    external: true
    name: openwalla
```

Set `OPENWALLA_DOCKER_NETWORK` if you want Openwalla to create the network under a different name, and use that same name in the proxy configuration.

### Traefik file provider

Copy `tunnel/traefik-dynamic.example.yaml` into the Traefik file-provider directory, change `router.example.com`, and configure the desired certificate resolver or TLS options. Connect the Traefik container to the `openwalla` Docker network first.

Protect the router hostname with reverse-proxy authentication or an IP allowlist. The SSH gateway authenticates the router connection, but the LuCI endpoint still needs normal access controls at the proxy.

Useful checks:

```sh
docker compose logs -f openwalla-tunnel
logread -e openwalla-tunnel
```
