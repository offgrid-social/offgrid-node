# OFFGRID Node

OFFGRID Nodes are privacy-first media workers. They store and serve media assigned by the OFFGRID API and report capacity/health. Nodes are infrastructure, not authorities.

## What this repo contains
- Go-based node runtime (single binary, standard library only)
- Linux and Windows installers
- Docker support
- API contract docs (register + heartbeat)
- Security documentation

## What nodes do not do
- No databases
- No analytics or tracking
- No user accounts at runtime
- No moderation decisions
- No ranking or feeds

## Quick start (development)
```bash
go build -o offgrid-node ./cmd/offgrid-node
./offgrid-node --config config.json
```

## Installers
- Linux: `install.sh`
- Windows: `install.ps1`

## Docs
- API contract: `docs/API.md`
- Security model: `docs/SECURITY.md`
- Sample config: `config.json`

## License
AGPL-3.0
