package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type HeartbeatPayload struct {
	NodeID     string     `json:"node_id"`
	Timestamp  string     `json:"timestamp_utc"`
	PublicURL  string     `json:"public_url"`
	Policies   Policies   `json:"policies"`
	System     SystemInfo `json:"system"`
	Capacity   Capacity   `json:"capacity"`
	Health     string     `json:"health"`
	Software   string     `json:"software"`
	APIVersion string     `json:"api_version"`
}

type Capacity struct {
	StorageDir string `json:"storage_dir"`
	TotalBytes int64  `json:"total_bytes"`
	FreeBytes  int64  `json:"free_bytes"`
}

func runHeartbeatLoop(ctx context.Context, cfg Config, interval time.Duration, logger *Logger) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		if err := sendHeartbeat(ctx, cfg); err != nil {
			logger.Error("heartbeat_failed", map[string]any{"error": err.Error()})
		} else {
			logger.Info("heartbeat_ok", map[string]any{})
		}

		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func sendHeartbeat(ctx context.Context, cfg Config) error {
	total, free, err := GetDiskUsage(cfg.StorageDir)
	if err != nil {
		return fmt.Errorf("disk usage: %w", err)
	}

	payload := HeartbeatPayload{
		NodeID:     cfg.NodeID,
		Timestamp:  time.Now().UTC().Format(time.RFC3339Nano),
		PublicURL:  cfg.PublicURL,
		Policies:   cfg.Policies,
		System:     cfg.System,
		Capacity:   Capacity{StorageDir: cfg.StorageDir, TotalBytes: total, FreeBytes: free},
		Health:     "ok",
		Software:   "offgrid-node",
		APIVersion: "v1",
	}

	raw, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal payload: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, apiBaseURL+"/nodes/heartbeat", bytes.NewReader(raw))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", fmt.Sprintf("Node %s:%s", cfg.NodeID, cfg.NodeSecret))

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("heartbeat status %d", resp.StatusCode)
	}
	return nil
}
