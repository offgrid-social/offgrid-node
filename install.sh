#!/usr/bin/env bash
set -euo pipefail

API_BASE="https://api.offgridhq.net"
GITHUB_API="https://api.github.com/repos/offgrid-social/offgrid-node/releases/latest"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/opt/offgrid-node"
CONFIG_DIR="/etc/offgrid-node"
SERVICE_NAME="offgrid-node"
BIN_PATH="/usr/local/bin/offgrid-node"

info() {
  printf "%s\n" "$1"
}

prompt() {
  local message="$1"
  local default="${2:-}"
  if [ -n "$default" ]; then
    read -r -p "$message [$default]: " value
    if [ -z "$value" ]; then
      value="$default"
    fi
  else
    read -r -p "$message: " value
  fi
  printf "%s" "$value"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    info "Missing required command: $1"
    exit 1
  }
}

python_bin() {
  if command -v python3 >/dev/null 2>&1; then
    printf "python3"
  else
    printf "python"
  fi
}

require_cmd curl
require_cmd "$(python_bin)"

os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
uname_arch="$(uname -m)"
cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc)"
total_ram_bytes="$(
  awk '/MemTotal/ {print $2 * 1024}' /proc/meminfo 2>/dev/null || echo 0
)"

arch=""
case "$uname_arch" in
  x86_64) arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  *)
    info "Unsupported architecture: $uname_arch"
    exit 1
    ;;
esac

info "Detected architecture: $arch"

release_json="$(curl -sS "$GITHUB_API")"
release_tag="$(echo "$release_json" | "$(python_bin)" -c "import json,sys; print(json.load(sys.stdin).get('tag_name',''))")"
if [ -z "$release_tag" ]; then
  info "Failed to detect release tag."
  exit 1
fi

asset_name="offgrid-node-linux-$arch"
asset_url="$(echo "$release_json" | "$(python_bin)" -c "import json,sys; data=json.load(sys.stdin); name=sys.argv[1]; url='';\n\nfor a in data.get('assets',[]):\n  if a.get('name')==name:\n    url=a.get('browser_download_url','')\n    break\nprint(url)" "$asset_name")"
if [ -z "$asset_url" ]; then
  info "Release asset not found: $asset_name"
  exit 1
fi

tmp_file="$(mktemp)"
curl -sS -L "$asset_url" -o "$tmp_file"
install -m 0755 "$tmp_file" "$BIN_PATH"
rm -f "$tmp_file"

info "Release tag: $release_tag"
info "Installed binary: $BIN_PATH"

info "Do you want to log in with an OFFGRID account?"
info "Press Enter to skip, or type 'login' to continue."
read -r login_choice

owner_token=""
if [ "$login_choice" = "login" ]; then
  device_json="$(curl -sS -X POST "$API_BASE/auth/device/request" \
    -H "Content-Type: application/json" \
    -d '{"client":"offgrid-node-installer"}')"
  device_code="$(echo "$device_json" | "$(python_bin)" -c "import json,sys; print(json.load(sys.stdin).get('device_code',''))")"
  user_code="$(echo "$device_json" | "$(python_bin)" -c "import json,sys; print(json.load(sys.stdin).get('user_code',''))")"
  verification_url="$(echo "$device_json" | "$(python_bin)" -c "import json,sys; print(json.load(sys.stdin).get('verification_url',''))")"
  interval="$(echo "$device_json" | "$(python_bin)" -c "import json,sys; print(json.load(sys.stdin).get('interval_seconds',5))")"

  if [ -z "$device_code" ] || [ -z "$verification_url" ]; then
    info "Login request failed; continuing anonymously."
  else
    info "Open this URL to authenticate:"
    info "$verification_url"
    if [ -n "$user_code" ]; then
      info "Enter code: $user_code"
    fi
    while true; do
      sleep "$interval"
      status_json="$(curl -sS -X POST "$API_BASE/auth/device/status" \
        -H "Content-Type: application/json" \
        -d "{\"device_code\":\"$device_code\"}")"
      owner_token="$(echo "$status_json" | "$(python_bin)" -c "import json,sys; print(json.load(sys.stdin).get('owner_token',''))")"
      if [ -n "$owner_token" ]; then
        break
      fi
      status="$(echo "$status_json" | "$(python_bin)" -c "import json,sys; print(json.load(sys.stdin).get('status',''))")"
      if [ "$status" = "denied" ]; then
        info "Login denied; continuing anonymously."
        owner_token=""
        break
      fi
    done
  fi
fi

public_url="$(prompt "Public URL for this node (https://...)" "")"
if [ -z "$public_url" ]; then
  info "Public URL is required."
  exit 1
fi

bind_addr="$(prompt "Bind address" "0.0.0.0:8787")"
storage_dir="$(prompt "Storage directory" "/var/lib/offgrid-node/media")"

allow_images="$(prompt "Allow images? (y/n)" "y")"
allow_videos="$(prompt "Allow videos? (y/n)" "y")"
allow_nsfw="$(prompt "Allow NSFW? (y/n)" "n")"
allow_adult="$(prompt "Allow 18+ content? (y/n)" "n")"
max_file_size_mb="$(prompt "Max file size (MB, 0 for unlimited)" "50")"
max_video_length_seconds="$(prompt "Max video length (seconds, 0 for unlimited)" "300")"
heartbeat_interval_seconds="$(prompt "Heartbeat interval (seconds)" "30")"

runtime_mode="$(prompt "Runtime mode (native/docker)" "native")"
if [ "$runtime_mode" != "native" ] && [ "$runtime_mode" != "docker" ]; then
  info "Invalid runtime mode."
  exit 1
fi

mkdir -p "$storage_dir"
df_out="$(df -k "$storage_dir" | tail -n 1)"
total_kb="$(echo "$df_out" | awk '{print $2}')"
free_kb="$(echo "$df_out" | awk '{print $4}')"
total_bytes="$((total_kb * 1024))"
free_bytes="$((free_kb * 1024))"

info ""
info "Summary"
info "Public URL: $public_url"
info "Bind address: $bind_addr"
info "Storage dir: $storage_dir"
info "Policies: images=$allow_images videos=$allow_videos nsfw=$allow_nsfw adult=$allow_adult"
info "Max file size MB: $max_file_size_mb"
info "Max video length seconds: $max_video_length_seconds"
info "Heartbeat interval seconds: $heartbeat_interval_seconds"
info "Runtime mode: $runtime_mode"
info ""

confirm="$(prompt "Type 'confirm' to continue" "")"
if [ "$confirm" != "confirm" ]; then
  info "Cancelled."
  exit 1
fi

payload="$(PUBLIC_URL="$public_url" BIND_ADDR="$bind_addr" STORAGE_DIR="$storage_dir" \
  ALLOW_IMAGES="$allow_images" ALLOW_VIDEOS="$allow_videos" ALLOW_NSFW="$allow_nsfw" \
  ALLOW_ADULT="$allow_adult" MAX_FILE_SIZE_MB="$max_file_size_mb" \
  MAX_VIDEO_LENGTH_SECONDS="$max_video_length_seconds" OS_NAME="$os_name" ARCH="$arch" \
  CORES="$cores" TOTAL_RAM_BYTES="$total_ram_bytes" TOTAL_BYTES="$total_bytes" \
  FREE_BYTES="$free_bytes" OWNER_TOKEN="$owner_token" \
  "$(python_bin)" - <<PY
import json, os
payload = {
  "public_url": os.environ["PUBLIC_URL"],
  "bind_addr": os.environ["BIND_ADDR"],
  "policies": {
    "allow_images": os.environ["ALLOW_IMAGES"] == "y",
    "allow_videos": os.environ["ALLOW_VIDEOS"] == "y",
    "allow_nsfw": os.environ["ALLOW_NSFW"] == "y",
    "allow_adult": os.environ["ALLOW_ADULT"] == "y",
    "max_file_size_mb": int(os.environ["MAX_FILE_SIZE_MB"]),
    "max_video_length_seconds": int(os.environ["MAX_VIDEO_LENGTH_SECONDS"]),
  },
  "system": {
    "os_name": os.environ["OS_NAME"],
    "arch": os.environ["ARCH"],
    "cores": int(os.environ["CORES"]),
    "total_ram_bytes": int(os.environ["TOTAL_RAM_BYTES"]),
  },
  "capacity": {
    "storage_dir": os.environ["STORAGE_DIR"],
    "total_bytes": int(os.environ["TOTAL_BYTES"]),
    "free_bytes": int(os.environ["FREE_BYTES"]),
  },
}
owner = os.environ.get("OWNER_TOKEN", "")
if owner:
  payload["owner_token"] = owner
print(json.dumps(payload))
PY
)"

register_json="$(curl -sS -X POST "$API_BASE/nodes/register" -H "Content-Type: application/json" -d "$payload")"

node_id="$(echo "$register_json" | "$(python_bin)" -c "import json,sys; print(json.load(sys.stdin).get('node_id',''))")"
node_secret="$(echo "$register_json" | "$(python_bin)" -c "import json,sys; print(json.load(sys.stdin).get('node_secret',''))")"
hb_interval="$(echo "$register_json" | "$(python_bin)" -c "import json,sys; print(json.load(sys.stdin).get('heartbeat_interval_seconds',30))")"

if [ -z "$node_id" ] || [ -z "$node_secret" ]; then
  info "Node registration failed."
  info "$register_json"
  exit 1
fi

mkdir -p "$CONFIG_DIR" "$INSTALL_DIR"
config_path="$CONFIG_DIR/config.json"

cat > "$config_path" <<EOF
{
  "node_id": "$node_id",
  "node_secret": "$node_secret",
  "public_url": "$public_url",
  "bind_addr": "$bind_addr",
  "storage_dir": "$storage_dir",
  "heartbeat_interval_seconds": $hb_interval,
  "system": {
    "os_name": "$os_name",
    "arch": "$arch",
    "cores": $cores,
    "total_ram_bytes": $total_ram_bytes
  },
  "policies": {
    "allow_images": $( [ "$allow_images" = "y" ] && echo "true" || echo "false" ),
    "allow_videos": $( [ "$allow_videos" = "y" ] && echo "true" || echo "false" ),
    "allow_nsfw": $( [ "$allow_nsfw" = "y" ] && echo "true" || echo "false" ),
    "allow_adult": $( [ "$allow_adult" = "y" ] && echo "true" || echo "false" ),
    "max_file_size_mb": $max_file_size_mb,
    "max_video_length_seconds": $max_video_length_seconds
  }
}
EOF

chmod 600 "$config_path"

if [ "$runtime_mode" = "native" ]; then
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=OFFGRID Node
After=network.target

[Service]
Type=simple
ExecStart=$BIN_PATH --config $config_path
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
else
  if command -v docker >/dev/null 2>&1; then
    :
  else
    info "Docker is required for docker mode."
    exit 1
  fi
  mkdir -p "$INSTALL_DIR"
  cat > "$INSTALL_DIR/docker-compose.yml" <<EOF
services:
  offgrid-node:
    image: alpine:3.20
    container_name: offgrid-node
    restart: unless-stopped
    command: ["/app/offgrid-node", "--config", "/app/config.json"]
    ports:
      - "8787:8787"
    volumes:
      - "$BIN_PATH:/app/offgrid-node:ro"
      - "$config_path:/app/config.json:ro"
      - "$storage_dir:$storage_dir"
EOF
  if command -v docker-compose >/dev/null 2>&1; then
    (cd "$INSTALL_DIR" && docker-compose up -d)
  else
    (cd "$INSTALL_DIR" && docker compose up -d)
  fi
fi

info "Waiting for node to become healthy..."
for i in {1..30}; do
  if curl -sS "http://127.0.0.1:8787/health" >/dev/null 2>&1; then
    info "Node is running."
    exit 0
  fi
  sleep 2
done

info "Node did not become healthy in time."
exit 1
