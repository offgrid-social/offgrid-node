//go:build windows && service
// +build windows,service

package main

import (
	"context"
	"fmt"
	"sync"
	"syscall"
	"unsafe"
)

const (
	serviceWin32OwnProcess    = 0x00000010
	serviceStartPending       = 0x00000002
	serviceRunning            = 0x00000004
	serviceStopPending        = 0x00000003
	serviceStopped            = 0x00000001
	serviceAcceptStop         = 0x00000001
	serviceAcceptShutdown     = 0x00000004
	serviceControlStop        = 0x00000001
	serviceControlShutdown    = 0x00000005
	errorFailedServiceConnect = 0x00000427
	serviceAcceptedControls   = serviceAcceptStop | serviceAcceptShutdown
)

type serviceStatus struct {
	ServiceType             uint32
	CurrentState            uint32
	ControlsAccepted        uint32
	Win32ExitCode           uint32
	ServiceSpecificExitCode uint32
	CheckPoint              uint32
	WaitHint                uint32
}

type serviceTableEntry struct {
	ServiceName *uint16
	ServiceProc uintptr
}

var (
	serviceNameUTF16 *uint16
	serviceStatusH   syscall.Handle
	serviceStopOnce  sync.Once
	serviceStopChan  chan struct{}
	serviceRun       func(context.Context) error
	serviceLogger    *Logger
)

func RunAsWindowsService(name string, run func(ctx context.Context) error, logger *Logger) {
	serviceNameUTF16, _ = syscall.UTF16PtrFromString(name)
	serviceRun = run
	serviceLogger = logger
	serviceStopChan = make(chan struct{})

	advapi := syscall.NewLazyDLL("advapi32.dll")
	startDispatcher := advapi.NewProc("StartServiceCtrlDispatcherW")

	table := []serviceTableEntry{
		{ServiceName: serviceNameUTF16, ServiceProc: syscall.NewCallback(serviceMain)},
		{},
	}

	ret, _, err := startDispatcher.Call(uintptr(unsafe.Pointer(&table[0])))
	if ret == 0 {
		if errno, ok := err.(syscall.Errno); ok && errno == errorFailedServiceConnect {
			return
		}
		if serviceLogger != nil {
			serviceLogger.Error("service_dispatcher_failed", map[string]any{"error": fmt.Sprintf("StartServiceCtrlDispatcherW: %v", err)})
		}
		return
	}
}

func serviceMain(argc uint32, argv **uint16) {
	advapi := syscall.NewLazyDLL("advapi32.dll")
	registerHandler := advapi.NewProc("RegisterServiceCtrlHandlerExW")
	setStatus := advapi.NewProc("SetServiceStatus")

	handle, _, err := registerHandler.Call(
		uintptr(unsafe.Pointer(serviceNameUTF16)),
		syscall.NewCallback(serviceCtrlHandler),
		0,
	)
	if handle == 0 {
		if serviceLogger != nil {
			serviceLogger.Error("service_register_failed", map[string]any{"error": err.Error()})
		}
		return
	}
	serviceStatusH = syscall.Handle(handle)

	updateStatus(setStatus, serviceStartPending, 3000)

	ctx, cancel := context.WithCancel(context.Background())
	errCh := make(chan error, 1)
	go func() {
		errCh <- serviceRun(ctx)
		close(errCh)
	}()

	updateStatus(setStatus, serviceRunning, 0)

	select {
	case <-serviceStopChan:
		updateStatus(setStatus, serviceStopPending, 3000)
		cancel()
		<-errCh
	case err := <-errCh:
		if err != nil && serviceLogger != nil {
			serviceLogger.Error("service_run_failed", map[string]any{"error": err.Error()})
		}
		updateStatus(setStatus, serviceStopPending, 3000)
		cancel()
	}

	updateStatus(setStatus, serviceStopped, 0)
}

func serviceCtrlHandler(ctrl uint32, eventType uint32, eventData uintptr, context uintptr) uintptr {
	switch ctrl {
	case serviceControlStop, serviceControlShutdown:
		serviceStopOnce.Do(func() { close(serviceStopChan) })
		return 0
	default:
		return 0
	}
}

func updateStatus(setStatus *syscall.LazyProc, state uint32, waitHint uint32) {
	status := serviceStatus{
		ServiceType:      serviceWin32OwnProcess,
		CurrentState:     state,
		ControlsAccepted: serviceAcceptedControls,
		WaitHint:         waitHint,
	}
	_, _, _ = setStatus.Call(uintptr(serviceStatusH), uintptr(unsafe.Pointer(&status)))
}
