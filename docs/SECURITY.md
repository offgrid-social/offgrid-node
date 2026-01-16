# OFFGRID Node Security

## Trust boundaries
- Node runtime is untrusted by the API. The API remains authoritative.
- Node owner controls the host and storage; OFFGRID does not.
- The node never authenticates end users; only the API assigns work.

## Threat model
- Stolen node secret could allow forged heartbeats or uploads.
- Malicious host could delete or leak stored media.
- Network attacker could attempt replay or interception.

## Security controls
- Node secrets are generated locally and stored only on the node.
- Authorization uses `Authorization: Node <node_id>:<node_secret>`.
- Heartbeats include capacity and health only; no user data.
- Media upload requires node authentication and respects declared policies.
- Logs are local-only and contain no user identifiers.

## Secret revocation strategy
- API can revoke a node secret at any time.
- Revoked nodes are rejected during heartbeat and upload calls.
- Installer can re-register to obtain a new secret if revoked.

## Operational guidance
- Keep the storage directory on a dedicated volume with backups as needed.
- Restrict access to `config.json` to the node owner or service account.
