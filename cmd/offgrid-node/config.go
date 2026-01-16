package main

import (
	"encoding/json"
	"fmt"
	"os"
)

type Config struct {
	NodeID                   string     `json:"node_id"`
	NodeSecret               string     `json:"node_secret"`
	PublicURL                string     `json:"public_url"`
	BindAddr                 string     `json:"bind_addr"`
	StorageDir               string     `json:"storage_dir"`
	HeartbeatIntervalSeconds int        `json:"heartbeat_interval_seconds"`
	System                   SystemInfo `json:"system"`
	Policies                 Policies   `json:"policies"`
}

type SystemInfo struct {
	OSName       string `json:"os_name"`
	Arch         string `json:"arch"`
	Cores        int    `json:"cores"`
	TotalRAMByte int64  `json:"total_ram_bytes"`
}

type Policies struct {
	AllowImages        bool  `json:"allow_images"`
	AllowVideos        bool  `json:"allow_videos"`
	AllowNSFW          bool  `json:"allow_nsfw"`
	AllowAdult         bool  `json:"allow_adult"`
	MaxFileSizeMB      int64 `json:"max_file_size_mb"`
	MaxVideoLengthSecs int64 `json:"max_video_length_seconds"`
}

func LoadConfig(path string) (Config, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return Config{}, err
	}
	var cfg Config
	if err := json.Unmarshal(raw, &cfg); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

func SaveConfig(path string, cfg Config) error {
	raw, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal config: %w", err)
	}
	return os.WriteFile(path, raw, 0o600)
}
