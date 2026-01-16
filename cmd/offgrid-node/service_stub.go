//go:build !service
// +build !service

package main

import "context"

func RunAsWindowsService(name string, run func(ctx context.Context) error, logger *Logger) {
	_ = name
	_ = run
	_ = logger
}
