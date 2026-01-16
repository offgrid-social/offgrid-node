package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"syscall"
	"time"
)

const (
	apiBaseURL       = "https://api.offgridhq.net"
	defaultBindAddr  = "0.0.0.0:8787"
	defaultHeartbeat = 30 * time.Second
)

func main() {
	// Only enter Windows service mode when explicitly requested to avoid
	// invoking service callbacks during normal CLI execution.
	serviceMode := hasArg("--service")

	cfgPath := flag.String("config", "config.json", "path to config.json")
	flag.Parse()

	logger := NewLogger(os.Stdout)

	if runtime.GOOS == "windows" && serviceMode {
		ran, err := RunAsWindowsService("OFFGRIDNode", func(ctx context.Context) error {
			return runNode(ctx, *cfgPath, logger)
		}, logger)
		if err != nil {
			logger.Error("service_start_failed", map[string]any{"error": err.Error()})
			os.Exit(1)
		}
		_ = ran
		return
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := runNode(ctx, *cfgPath, logger); err != nil {
		logger.Error("node_exit", map[string]any{"error": err.Error()})
		os.Exit(1)
	}
}

func hasArg(flag string) bool {
	for _, arg := range os.Args[1:] {
		if arg == flag {
			return true
		}
	}
	return false
}

func runNode(ctx context.Context, cfgPath string, logger *Logger) error {
	cfg, err := LoadConfig(cfgPath)
	if err != nil {
		return fmt.Errorf("load config: %w", err)
	}

	if err := validateConfig(&cfg); err != nil {
		return fmt.Errorf("invalid config: %w", err)
	}

	if err := os.MkdirAll(cfg.StorageDir, 0o755); err != nil {
		return fmt.Errorf("create storage dir: %w", err)
	}

	server := &http.Server{
		Addr:         cfg.BindAddr,
		Handler:      NewRouter(cfg, logger),
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	heartbeatInterval := time.Duration(cfg.HeartbeatIntervalSeconds) * time.Second
	if heartbeatInterval <= 0 {
		heartbeatInterval = defaultHeartbeat
	}

	errCh := make(chan error, 1)

	go func() {
		logger.Info("http_listen", map[string]any{"addr": cfg.BindAddr})
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
	}()

	go func() {
		runHeartbeatLoop(ctx, cfg, heartbeatInterval, logger)
	}()

	select {
	case <-ctx.Done():
	case err := <-errCh:
		return fmt.Errorf("http server: %w", err)
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		logger.Error("http_shutdown_failed", map[string]any{"error": err.Error()})
	}

	logger.Info("node_shutdown", map[string]any{})
	return nil
}

func validateConfig(cfg *Config) error {
	if cfg.NodeID == "" || cfg.NodeSecret == "" {
		return fmt.Errorf("node_id and node_secret are required")
	}
	if cfg.StorageDir == "" {
		return fmt.Errorf("storage_dir is required")
	}
	if cfg.BindAddr == "" {
		cfg.BindAddr = defaultBindAddr
	}
	if cfg.PublicURL == "" {
		return fmt.Errorf("public_url is required")
	}
	if cfg.HeartbeatIntervalSeconds <= 0 {
		cfg.HeartbeatIntervalSeconds = int(defaultHeartbeat.Seconds())
	}
	return nil
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	_ = enc.Encode(payload)
}
