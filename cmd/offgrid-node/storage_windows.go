//go:build windows

package main

import (
	"syscall"
	"unsafe"
)

func GetDiskUsage(path string) (totalBytes int64, freeBytes int64, err error) {
	kernel32 := syscall.NewLazyDLL("kernel32.dll")
	proc := kernel32.NewProc("GetDiskFreeSpaceExW")

	pathPtr, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return 0, 0, err
	}

	var freeAvailable uint64
	var total uint64
	var free uint64

	ret, _, callErr := proc.Call(
		uintptr(unsafe.Pointer(pathPtr)),
		uintptr(unsafe.Pointer(&freeAvailable)),
		uintptr(unsafe.Pointer(&total)),
		uintptr(unsafe.Pointer(&free)),
	)
	if ret == 0 {
		if callErr != nil {
			return 0, 0, callErr
		}
		return 0, 0, syscall.EINVAL
	}
	return int64(total), int64(free), nil
}
