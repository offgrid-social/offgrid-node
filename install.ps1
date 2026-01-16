$ErrorActionPreference = "Stop"

$ApiBase = "https://api.offgridhq.net"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir = "C:\ProgramData\offgrid-node"
$ServiceName = "OFFGRIDNode"

function Prompt-Value {
  param([string]$Message, [string]$Default = "")
  if ($Default -ne "") {
    $value = Read-Host "$Message [$Default]"
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
  }
  return Read-Host $Message
}

function Get-YesNo {
  param([string]$Message, [string]$Default = "n")
  $value = Prompt-Value $Message $Default
  if ($value -match '^(y|yes)$') { return $true }
  return $false
}

$osName = (Get-CimInstance Win32_OperatingSystem).Caption
$arch = $env:PROCESSOR_ARCHITECTURE
$cores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$totalRamBytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory

Write-Host "Do you want to log in with an OFFGRID account?"
Write-Host "Press Enter to skip, or type 'login' to continue."
$loginChoice = Read-Host

$ownerToken = ""
if ($loginChoice -eq "login") {
  try {
    $device = Invoke-RestMethod -Method Post -Uri "$ApiBase/auth/device/request" -Body '{"client":"offgrid-node-installer"}' -ContentType "application/json"
    if ($device.device_code) {
      Write-Host "Open this URL to authenticate:"
      Write-Host $device.verification_url
      if ($device.user_code) { Write-Host "Enter code: $($device.user_code)" }
      $interval = 5
      if ($device.interval_seconds) { $interval = [int]$device.interval_seconds }
      while ($true) {
        Start-Sleep -Seconds $interval
        $status = Invoke-RestMethod -Method Post -Uri "$ApiBase/auth/device/status" -Body (@{"device_code"=$device.device_code} | ConvertTo-Json) -ContentType "application/json"
        if ($status.owner_token) {
          $ownerToken = $status.owner_token
          break
        }
        if ($status.status -eq "denied") {
          Write-Host "Login denied; continuing anonymously."
          break
        }
      }
    }
  } catch {
    Write-Host "Login request failed; continuing anonymously."
  }
}

$publicUrl = Prompt-Value "Public URL for this node (https://...)" ""
if ([string]::IsNullOrWhiteSpace($publicUrl)) {
  Write-Host "Public URL is required."
  exit 1
}
$bindAddr = Prompt-Value "Bind address" "0.0.0.0:8787"
$storageDir = Prompt-Value "Storage directory" "C:\ProgramData\offgrid-node\data"

$allowImages = Get-YesNo "Allow images? (y/n)" "y"
$allowVideos = Get-YesNo "Allow videos? (y/n)" "y"
$allowNSFW = Get-YesNo "Allow NSFW? (y/n)" "n"
$allowAdult = Get-YesNo "Allow 18+ content? (y/n)" "n"
$maxFileSizeMB = [int](Prompt-Value "Max file size (MB, 0 for unlimited)" "50")
$maxVideoLengthSeconds = [int](Prompt-Value "Max video length (seconds, 0 for unlimited)" "300")
$heartbeatIntervalSeconds = [int](Prompt-Value "Heartbeat interval (seconds)" "30")

$runtimeMode = Prompt-Value "Runtime mode (native/docker)" "native"
if ($runtimeMode -ne "native" -and $runtimeMode -ne "docker") {
  Write-Host "Invalid runtime mode."
  exit 1
}

New-Item -ItemType Directory -Force -Path $storageDir | Out-Null
$driveName = (Split-Path -Path $storageDir -Qualifier).TrimEnd(':')
$drive = Get-PSDrive -Name $driveName
$totalBytes = [int64]($drive.Used + $drive.Free)
$freeBytes = [int64]$drive.Free

Write-Host ""
Write-Host "Summary"
Write-Host "Public URL: $publicUrl"
Write-Host "Bind address: $bindAddr"
Write-Host "Storage dir: $storageDir"
Write-Host "Policies: images=$allowImages videos=$allowVideos nsfw=$allowNSFW adult=$allowAdult"
Write-Host "Max file size MB: $maxFileSizeMB"
Write-Host "Max video length seconds: $maxVideoLengthSeconds"
Write-Host "Heartbeat interval seconds: $heartbeatIntervalSeconds"
Write-Host "Runtime mode: $runtimeMode"
Write-Host ""

$confirm = Prompt-Value "Type 'confirm' to continue" ""
if ($confirm -ne "confirm") {
  Write-Host "Cancelled."
  exit 1
}

$payload = @{
  public_url = $publicUrl
  bind_addr = $bindAddr
  policies = @{
    allow_images = $allowImages
    allow_videos = $allowVideos
    allow_nsfw = $allowNSFW
    allow_adult = $allowAdult
    max_file_size_mb = $maxFileSizeMB
    max_video_length_seconds = $maxVideoLengthSeconds
  }
  system = @{
    os_name = $osName
    arch = $arch
    cores = $cores
    total_ram_bytes = $totalRamBytes
  }
  capacity = @{
    storage_dir = $storageDir
    total_bytes = $totalBytes
    free_bytes = $freeBytes
  }
}
if ($ownerToken) { $payload.owner_token = $ownerToken }

$register = Invoke-RestMethod -Method Post -Uri "$ApiBase/nodes/register" -Body ($payload | ConvertTo-Json) -ContentType "application/json"
if (-not $register.node_id -or -not $register.node_secret) {
  Write-Host "Node registration failed."
  exit 1
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$configPath = Join-Path $InstallDir "config.json"

$hbInterval = $register.heartbeat_interval_seconds
if (-not $hbInterval) { $hbInterval = $heartbeatIntervalSeconds }

$config = @{
  node_id = $register.node_id
  node_secret = $register.node_secret
  public_url = $publicUrl
  bind_addr = $bindAddr
  storage_dir = $storageDir
  heartbeat_interval_seconds = $hbInterval
  system = @{
    os_name = $osName
    arch = $arch
    cores = $cores
    total_ram_bytes = $totalRamBytes
  }
  policies = @{
    allow_images = $allowImages
    allow_videos = $allowVideos
    allow_nsfw = $allowNSFW
    allow_adult = $allowAdult
    max_file_size_mb = $maxFileSizeMB
    max_video_length_seconds = $maxVideoLengthSeconds
  }
}
$config | ConvertTo-Json | Set-Content -Path $configPath -Encoding UTF8

if ($runtimeMode -eq "native") {
  if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    Write-Host "Go is required for native mode."
    exit 1
  }
  Push-Location $ScriptDir
  go build -o "$InstallDir\offgrid-node.exe" .\cmd\offgrid-node
  Pop-Location

  sc.exe create $ServiceName binPath= "`"$InstallDir\offgrid-node.exe`" --config `"$configPath`"" start= auto DisplayName= "OFFGRID Node" | Out-Null
  sc.exe start $ServiceName | Out-Null
} else {
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "Docker is required for docker mode."
    exit 1
  }
  New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir "data") | Out-Null
  Copy-Item -Path (Join-Path $ScriptDir "docker-compose.yml") -Destination (Join-Path $InstallDir "docker-compose.yml") -Force
  Copy-Item -Path $configPath -Destination (Join-Path $InstallDir "config.json") -Force
  Push-Location $InstallDir
  if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
    docker-compose up -d --build
  } else {
    docker compose up -d --build
  }
  Pop-Location
}

Write-Host "Waiting for node to become healthy..."
for ($i = 0; $i -lt 30; $i++) {
  try {
    Invoke-RestMethod -Uri "http://127.0.0.1:8787/health" -Method Get | Out-Null
    Write-Host "Node is running."
    exit 0
  } catch {
    Start-Sleep -Seconds 2
  }
}

Write-Host "Node did not become healthy in time."
exit 1
