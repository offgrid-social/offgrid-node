# OFFGRID Node API Contract

Base URL (fixed):
`https://api.offgridhq.net`

Authentication header:
`Authorization: Node <node_id>:<node_secret>`

## POST /nodes/register
Registers a node and returns its credentials. The installer calls this endpoint once the owner confirms settings.

Request headers:
- `Content-Type: application/json`
- `Authorization: Node <node_id>:<node_secret>` is **not** used for registration

Request body:
```json
{
  "public_url": "https://node.example.org",
  "bind_addr": "0.0.0.0:8787",
  "policies": {
    "allow_images": true,
    "allow_videos": true,
    "allow_nsfw": false,
    "allow_adult": false,
    "max_file_size_mb": 50,
    "max_video_length_seconds": 300
  },
  "system": {
    "os_name": "linux",
    "arch": "amd64",
    "cores": 4,
    "total_ram_bytes": 17179869184
  },
  "capacity": {
    "storage_dir": "/var/lib/offgrid-node/media",
    "total_bytes": 1099511627776,
    "free_bytes": 824633720832
  },
  "owner_token": "optional-short-lived-token"
}
```

Response (200):
```json
{
  "node_id": "4cba2b21-944e-4a56-8d07-3abef21f5d4d",
  "node_secret": "random-shared-secret",
  "heartbeat_interval_seconds": 30
}
```

## POST /nodes/heartbeat
Sent periodically by the node runtime.

Request headers:
- `Content-Type: application/json`
- `Authorization: Node <node_id>:<node_secret>`

Request body:
```json
{
  "node_id": "4cba2b21-944e-4a56-8d07-3abef21f5d4d",
  "timestamp_utc": "2026-01-16T12:00:00Z",
  "public_url": "https://node.example.org",
  "policies": {
    "allow_images": true,
    "allow_videos": true,
    "allow_nsfw": false,
    "allow_adult": false,
    "max_file_size_mb": 50,
    "max_video_length_seconds": 300
  },
  "system": {
    "os_name": "linux",
    "arch": "amd64",
    "cores": 4,
    "total_ram_bytes": 17179869184
  },
  "capacity": {
    "storage_dir": "/var/lib/offgrid-node/media",
    "total_bytes": 1099511627776,
    "free_bytes": 824633720832
  },
  "health": "ok",
  "software": "offgrid-node",
  "api_version": "v1"
}
```

Response (200):
```json
{ "ok": true }
```
