//go:build darwin || linux || freebsd

package luimygo

import "github.com/ebitengine/purego"

func openLibrary(path string) (uintptr, error) {
	return purego.Dlopen(path, purego.RTLD_NOW|purego.RTLD_LOCAL)
}
func librarySymbol(handle uintptr, name string) (uintptr, error) { return purego.Dlsym(handle, name) }
func closeLibrary(handle uintptr) error                          { return purego.Dlclose(handle) }
