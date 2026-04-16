# Mailu Mail Stack

This stack uses [Mailu](https://mailu.io/latest/compose/cli.html), an open-source Docker-based mail server, as the backbone instead of a hand-assembled mail container. It is a better fit for automation because Mailu ships both an official CLI and an official REST API/Swagger surface.

What is included:

- Mailu front-end, admin, SMTP, IMAP, antispam, Redis, and webmail containers
- Cloudflare DNS-based certificate issuance through Certbot
- a local MCP server that wraps the supported Mailu admin CLI for agent access
- a Cloudflare Tunnel example for exposing the HTTP surface only

## Why this backbone

Mailu is the right base here because:

- it is fully open source and Docker-native
- it already exposes an admin GUI, a documented CLI, and a documented REST API
- it has native support for domains, users, aliases, quotas, DKIM/DMARC/SPF export, and webmail

References:

- Mailu overview: https://mailu.io/latest/compose/cli.html
- Mailu CLI: https://mailu.io/2024.06/cli.html
- Mailu REST API: https://mailu.io/2024.06/api.html

## Architecture

- `mail.example.com` stays `DNS only` and is used for SMTP/IMAP clients and MX
- `webmail.example.com` is proxied through your existing Cloudflare Tunnel to `http://localhost:8080`
- Mailu serves `/admin`, `/webmail`, and `/api` on the HTTP front-end
- agents connect through `mcp-server.js`, which calls the official Mailu CLI inside the `admin` container

That split matters because Cloudflare Tunnel is suitable for the web surface, but not as the public MX path for normal Internet mail delivery.

References:

- Cloudflare client-side TCP access requires `cloudflared` on both ends: https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/ssh/ssh-cloudflared-authentication/
- Cloudflare notes SMTP port `25` is not proxied unless you use Spectrum: https://developers.cloudflare.com/fundamentals/reference/network-ports/

## Files

- `docker-compose.yml`: Mailu deployment
- `.env.example`: Mailu and certificate settings
- `scripts/bootstrap.sh`: validates config, generates secrets, issues certs, starts Mailu
- `scripts/provision-cert.sh`: gets a certificate for all names in `HOSTNAMES`
- `scripts/renew-cert.sh`: renews the certificate and syncs it into Mailu
- `scripts/add-domain.sh`: add a hosted domain
- `scripts/add-user.sh`: add a mailbox
- `scripts/add-alias.sh`: add an alias
- `scripts/set-password.sh`: update a mailbox password
- `scripts/export-config.sh`: export Mailu config or DNS data
- `mcp-server.js`: MCP server for agents
- `mcp-config.example.json`: example MCP client config
- `docs/`: production control-plane and rollout spec
- `openapi/control-plane.yaml`: initial control-plane API contract
- `sql/control-plane.sql`: initial Postgres schema draft

## Production Build Spec

Implementation planning lives here:

- [Control Plane Architecture](./docs/control-plane-architecture.md)
- [Data Model](./docs/data-model.md)
- [Security and Operations](./docs/security-ops.md)
- [Rollout Plan](./docs/rollout-plan.md)
- [Initial Backlog](./docs/backlog.md)

## Quick start

1. Copy `.env.example` to `.env`.
2. Replace at least these values:

- `DOMAIN`
- `PRIMARY_HOSTNAME`
- `HOSTNAMES`
- `CERTBOT_EMAIL`
- `CLOUDFLARE_DNS_API_TOKEN`

3. Run:

```bash
cd /home/yaya/mail-stack
./scripts/bootstrap.sh
```

The bootstrap script will generate `SECRET_KEY`, `API_TOKEN`, and `INITIAL_ADMIN_PW` if they are still placeholders. Generated values are written to `bootstrap.generated`.

## Common operations

Create a hosted domain:

```bash
./scripts/add-domain.sh example.com
```

Create a mailbox:

```bash
./scripts/add-user.sh me@example.com 'strong-password'
```

Create an alias:

```bash
./scripts/add-alias.sh postmaster@example.com me@example.com
```

Export DNS-ready configuration from Mailu:

```bash
./scripts/export-config.sh --dns
```

Show stack status:

```bash
./scripts/status.sh
```

## Agent integration

The MCP server exposes these Mailu operations:

- stack status and logs
- derived admin, webmail, API, IMAP, and SMTP endpoints
- add domain
- add user
- delete user
- set password
- add alias
- delete alias
- export Mailu config and DNS records

Example MCP client config is in `mcp-config.example.json`.

The server is dependency-free and uses only Node's standard library:

```bash
node /home/yaya/mail-stack/mcp-server.js
```

## Cloudflare Tunnel

Use the tunnel only for the HTTP surface. A minimal example is in `cloudflared-webmail.example.yml`.

Suggested public hostname:

- `webmail.example.com` -> `http://localhost:8080`

Mailu then serves:

- `https://webmail.example.com/admin`
- `https://webmail.example.com/webmail`
- `https://webmail.example.com/api/`

## DNS

For the mail hostname use `DNS only`, not proxied.

- `A` record: `mail.example.com` -> your public IPv4
- `MX` record: `example.com` -> `10 mail.example.com`
- `TXT` SPF: `example.com` -> `"v=spf1 mx -all"`
- `TXT` DMARC: `_dmarc.example.com` -> `"v=DMARC1; p=none; rua=mailto:dmarc@example.com; ruf=mailto:dmarc@example.com; adkim=s; aspf=s; pct=100"`
- DKIM: pull from `./scripts/export-config.sh --dns` after the domain exists
- PTR/rDNS: set your public IP reverse DNS to `mail.example.com`

Mailu's own docs also call out creating a real `POSTMASTER` user or alias to avoid broken behavior.

Reference:

- Mailu compose setup and postmaster note: https://mailu.io/2024.06/compose/setup.html

## Notes

- Web ports are bound to localhost by default so the HTTP surface can stay behind Tunnel.
- Mail ports are published directly because SMTP/IMAP clients and remote MTAs cannot use Cloudflare Tunnel as their normal path.
- Certificates are copied into `./certs` because Mailu expects local certificate files when `TLS_FLAVOR=cert`.

References:

- Mailu external certificate handling: https://mailu.io/master/maintain.html
- Mailu config for automatic admin creation: https://mailu.io/2024.06/configuration.html
