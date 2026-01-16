#!/usr/bin/env bash
set -euo pipefail

API_BASE="https://api.offgridhq.net"
GITHUB_API="https://api.github.com/repos/offgrid-social/offgrid-node/releases/latest"
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
  local value=""
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

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_jq_if_requested() {
  info "Optional dependency jq improves reliability."
  info "Do you want the installer to install jq if missing? [y/N]"
  read -r jq_choice
  if [ "$jq_choice" != "y" ] && [ "$jq_choice" != "Y" ]; then
    return 0
  fi
  if has_cmd jq; then
    return 0
  fi
  if has_cmd dnf; then
    info "Installing jq via dnf..."
    (sudo dnf -y install jq || dnf -y install jq) || return 0
  elif has_cmd apt-get; then
    info "Installing jq via apt-get..."
    (sudo apt-get update -y || apt-get update -y) || return 0
    (sudo apt-get install -y jq || apt-get install -y jq) || return 0
  elif has_cmd pacman; then
    info "Installing jq via pacman..."
    (sudo pacman -Sy --noconfirm jq || pacman -Sy --noconfirm jq) || return 0
  elif has_cmd apk; then
    info "Installing jq via apk..."
    (sudo apk add --no-cache jq || apk add --no-cache jq) || return 0
  else
    info "No supported package manager found; continuing without jq."
  fi
}

extract_tag() {
  if has_cmd jq; then
    jq -r '.tag_name'
  else
    grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
  fi
}

extract_asset_url() {
  local asset_name="$1"
  if has_cmd jq; then
    jq -r --arg name "$asset_name" '.assets[] | select(.name==$name) | .browser_download_url'
  else
    grep -A 2 "\"name\": \"$asset_name\"" | grep '"browser_download_url"' | sed -E 's/.*"browser_download_url": *"([^"]+)".*/\1/'
  fi
}

uname_arch="$(uname -m)"
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

install_jq_if_requested

release_json="$(curl -sS -H "User-Agent: offgrid-node-installer" "$GITHUB_API")"
release_tag="$(echo "$release_json" | extract_tag)"
if [ -z "$release_tag" ]; then
  info "Failed to detect release tag."
  exit 1
fi

asset_name="offgrid-node-linux-$arch"
asset_url="$(echo "$release_json" | extract_asset_url "$asset_name")"
if [ -z "$asset_url" ]; then
  info "Release asset not found: $asset_name"
  exit 1
fi

tmp_file="${BIN_PATH}.download"
curl -sS -L "$asset_url" -o "$tmp_file"
mv "$tmp_file" "$BIN_PATH"
chmod +x "$BIN_PATH"

info "Release tag: $release_tag"
info "Installed binary: $BIN_PATH"

os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"

info "Do you want to log in with an OFFGRID account?"
info "Press Enter to skip, or type 'login' to continue."
read -r login_choice

owner_token=""
if [ "$login_choice" = "login" ]; then
  device_json="$(curl -sS -X POST "$API_BASE/auth/device/request" \
    -H "Content-Type: application/json" \
    -d '{"client":"offgrid-node-installer"}')"
  device_code="$(echo "$device_json" | grep -m1 '"device_code"' | sed -E 's/.*"device_code": *"([^"]+)".*/\1/')"
  user_code="$(echo "$device_json" | grep -m1 '"user_code"' | sed -E 's/.*"user_code": *"([^"]+)".*/\1/')"
  verification_url="$(echo "$device_json" | grep -m1 '"verification_url"' | sed -E 's/.*"verification_url": *"([^"]+)".*/\1/')"
  interval="$(echo "$device_json" | grep -m1 '"interval_seconds"' | sed -E 's/.*"interval_seconds": *([0-9]+).*/\1/')"
  if [ -z "$interval" ]; then
    interval="5"
  fi

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
      owner_token="$(echo "$status_json" | grep -m1 '"owner_token"' | sed -E 's/.*"owner_token": *"([^"]+)".*/\1/')"
      if [ -n "$owner_token" ]; then
        break
      fi
      status="$(echo "$status_json" | grep -m1 '"status"' | sed -E 's/.*"status": *"([^"]+)".*/\1/')"
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
total_bytes="0"
free_bytes="0"
cores="0"
total_ram_bytes="0"

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

bool_value() {
  case "$1" in
    y|Y) printf "true" ;;
    *) printf "false" ;;
  esac
}

payload=$(cat <<EOF
{
  "public_url": "$public_url",
  "bind_addr": "$bind_addr",
  "policies": {
    "allow_images": $(bool_value "$allow_images"),
    "allow_videos": $(bool_value "$allow_videos"),
    "allow_nsfw": $(bool_value "$allow_nsfw"),
    "allow_adult": $(bool_value "$allow_adult"),
    "max_file_size_mb": $max_file_size_mb,
    "max_video_length_seconds": $max_video_length_seconds
  },
  "system": {
    "os_name": "$os_name",
    "arch": "$arch",
    "cores": $cores,
    "total_ram_bytes": $total_ram_bytes
  },
  "capacity": {
    "storage_dir": "$storage_dir",
    "total_bytes": $total_bytes,
    "free_bytes": $free_bytes
  }$( [ -n "$owner_token" ] && printf ',\n  "owner_token": "%s"' "$owner_token" )
}
EOF
)

register_json="$(curl -sS -X POST "$API_BASE/nodes/register" -H "Content-Type: application/json" -d "$payload")"

node_id="$(echo "$register_json" | grep -m1 '"node_id"' | sed -E 's/.*"node_id": *"([^"]+)".*/\1/')"
node_secret="$(echo "$register_json" | grep -m1 '"node_secret"' | sed -E 's/.*"node_secret": *"([^"]+)".*/\1/')"
hb_interval="$(echo "$register_json" | grep -m1 '"heartbeat_interval_seconds"' | sed -E 's/.*"heartbeat_interval_seconds": *([0-9]+).*/\1/')"
if [ -z "$hb_interval" ]; then
  hb_interval="$heartbeat_interval_seconds"
fi

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
    "allow_images": $(bool_value "$allow_images"),
    "allow_videos": $(bool_value "$allow_videos"),
    "allow_nsfw": $(bool_value "$allow_nsfw"),
    "allow_adult": $(bool_value "$allow_adult"),
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
