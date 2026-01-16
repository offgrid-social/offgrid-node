package main

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

func NewRouter(cfg Config, logger *Logger) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"status":   "ok",
			"node_id":  cfg.NodeID,
			"time_utc": time.Now().UTC().Format(time.RFC3339Nano),
		})
	})
	mux.HandleFunc("/media/upload", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "method_not_allowed"})
			return
		}
		if !authorizeNode(cfg, r) {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "unauthorized"})
			return
		}

		contentType := r.Header.Get("Content-Type")
		if !isAllowedMediaType(cfg.Policies, contentType) {
			writeJSON(w, http.StatusUnsupportedMediaType, map[string]any{"error": "media_type_not_allowed"})
			return
		}
		if isHeaderTrue(r.Header.Get("X-Content-NSFW")) && !cfg.Policies.AllowNSFW {
			writeJSON(w, http.StatusForbidden, map[string]any{"error": "nsfw_not_allowed"})
			return
		}
		if isHeaderTrue(r.Header.Get("X-Content-Adult")) && !cfg.Policies.AllowAdult {
			writeJSON(w, http.StatusForbidden, map[string]any{"error": "adult_not_allowed"})
			return
		}

		maxBytes := int64(0)
		if cfg.Policies.MaxFileSizeMB > 0 {
			maxBytes = cfg.Policies.MaxFileSizeMB * 1024 * 1024
		}

		reader := io.Reader(r.Body)
		if maxBytes > 0 {
			reader = http.MaxBytesReader(w, r.Body, maxBytes)
		}

		filename := sanitizeFilename(r.Header.Get("X-File-Name"))
		if filename == "" {
			filename = randomName()
		}
		targetPath := filepath.Join(cfg.StorageDir, filename)

		if cfg.Policies.MaxVideoLengthSecs > 0 {
			if err := enforceVideoLength(cfg, r.Header.Get("X-Video-Length-Seconds")); err != nil {
				writeJSON(w, http.StatusBadRequest, map[string]any{"error": err.Error()})
				return
			}
		}

		bytesWritten, err := saveFile(targetPath, reader)
		if err != nil {
			var maxErr *http.MaxBytesError
			if errors.As(err, &maxErr) {
				writeJSON(w, http.StatusRequestEntityTooLarge, map[string]any{"error": "file_too_large"})
				return
			}
			writeJSON(w, http.StatusInternalServerError, map[string]any{"error": "write_failed"})
			logger.Error("media_write_failed", map[string]any{"error": err.Error(), "path": targetPath})
			return
		}

		writeJSON(w, http.StatusOK, map[string]any{
			"stored":    true,
			"filename":  filename,
			"size_byte": bytesWritten,
		})
	})
	return mux
}

func authorizeNode(cfg Config, r *http.Request) bool {
	auth := r.Header.Get("Authorization")
	expected := fmt.Sprintf("Node %s:%s", cfg.NodeID, cfg.NodeSecret)
	return auth == expected
}

func isAllowedMediaType(p Policies, contentType string) bool {
	contentType = strings.ToLower(contentType)
	if strings.HasPrefix(contentType, "image/") {
		return p.AllowImages
	}
	if strings.HasPrefix(contentType, "video/") {
		return p.AllowVideos
	}
	return false
}

func enforceVideoLength(cfg Config, header string) error {
	if header == "" {
		return nil
	}
	seconds, err := strconv.ParseInt(header, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid_video_length")
	}
	if cfg.Policies.MaxVideoLengthSecs > 0 && seconds > cfg.Policies.MaxVideoLengthSecs {
		return fmt.Errorf("video_length_exceeds_limit")
	}
	return nil
}

func saveFile(path string, r io.Reader) (int64, error) {
	tmpPath := path + ".partial"
	out, err := os.Create(tmpPath)
	if err != nil {
		return 0, err
	}
	defer out.Close()

	written, err := io.Copy(out, r)
	if err != nil {
		return written, err
	}
	if err := out.Sync(); err != nil {
		return written, err
	}
	if err := os.Rename(tmpPath, path); err != nil {
		return written, err
	}
	return written, nil
}

func sanitizeFilename(name string) string {
	if name == "" {
		return ""
	}
	name = filepath.Base(name)
	name = strings.ReplaceAll(name, "..", "")
	return name
}

func randomName() string {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return fmt.Sprintf("upload-%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(buf)
}

func isHeaderTrue(value string) bool {
	value = strings.TrimSpace(strings.ToLower(value))
	return value == "true" || value == "1" || value == "yes"
}
