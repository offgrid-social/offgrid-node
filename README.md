# OFFGRID-Node

<p align="center">
  <em>Privacy-first media worker for the OFFGRID ecosystem.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/github/last-commit/offgrid-social/offgrid-node?style=flat-square" />
  <img src="https://img.shields.io/github/languages/top/offgrid-social/offgrid-node?style=flat-square" />
  <img src="https://img.shields.io/github/languages/count/offgrid-social/offgrid-node?style=flat-square" />
  <img src="https://img.shields.io/github/license/offgrid-social/offgrid-node?style=flat-square" />
  <img src="https://img.shields.io/badge/Ecosystem-OFFGRID-black?style=flat-square" />
</p>

<p align="center">
  Built with
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Go-00ADD8?style=flat-square&logo=go" />
</p>

---

## Overview

**offgrid-node** is a media worker service for OFFGRID.

Nodes store and serve media assigned by **offgrid-api** and periodically report
capacity and health. Nodes are infrastructure components and hold no authority
over users, content, or visibility.

---

## Scope

The node runtime is intentionally minimal.

It exists only to:
- store media blobs
- serve media on request
- report operational state

---

## Features

- Single static Go binary (standard library only)
- Stateless, configuration-driven runtime
- Media storage and delivery
- Capacity and health reporting (heartbeat)
- Linux and Windows installers
- Docker support
- Hardened-by-default execution model

---

## Non-Features

- No databases
- No user accounts
- No authentication authority
- No moderation or policy decisions
- No analytics, tracking, or profiling
- No feeds, ranking, or recommendation logic

Nodes are blind workers, not platforms.

---

## Getting started

### Requirements

- Go 1.22+
- Linux or Windows host
- Reachable **offgrid-api**

---

### Build

    go build -o offgrid-node ./cmd/offgrid-node

---

### Run

    ./offgrid-node --config config.json

---

## Installation

### Linux

    chmod +x install.sh
    ./install.sh

### Windows (PowerShell)

    .\install.ps1

Installers:
- place the binary
- register a system service
- apply minimal permissions
- do not enable telemetry or auto-updaters

---

## Configuration

A sample configuration is provided:

    config.json

Key values include:
- node_id
- api_url
- storage_path
- max_storage_gb
- heartbeat_interval_seconds

---

## Documentation

- API contract: docs/API.md
- Security model: docs/SECURITY.md
- Sample config: config.json

---

## Security

- No embedded secrets
- Scoped node credentials only
- No long-lived sessions
- Minimal OS permissions
- No inbound trust assumptions

Nodes are assumed to be untrusted infrastructure.

---

## License

Licensed under **AGPL-3.0**.  
See LICENSE for details.

---

*Calm over clicks · Humans over metrics · Chronology over control*
