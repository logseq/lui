//go:build (darwin || linux) && (amd64 || arm64)

package luimygo

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"runtime"
	"runtime/pprof"
	"strconv"
	"syscall"
	"testing"
	"time"
	"unsafe"

	"github.com/ebitengine/purego"
)

type nativeSignalStack struct {
	address uintptr
	size    uintptr
	flags   uintptr
}

type nativeSignalState struct {
	mask     uint64
	handlers [2]uintptr
	flags    [2]uintptr
}

func signalStateProbe(t *testing.T) func() (nativeSignalState, error) {
	t.Helper()
	maskAddress, err := purego.Dlsym(purego.RTLD_DEFAULT, "pthread_sigmask")
	if err != nil {
		t.Fatal(err)
	}
	actionAddress, err := purego.Dlsym(purego.RTLD_DEFAULT, "sigaction")
	if err != nil {
		t.Fatal(err)
	}
	var mask func(int32, unsafe.Pointer, unsafe.Pointer) int32
	var action func(int32, unsafe.Pointer, unsafe.Pointer) int32
	purego.RegisterFunc(&mask, maskAddress)
	purego.RegisterFunc(&action, actionAddress)
	return func() (nativeSignalState, error) {
		var state nativeSignalState
		var maskWords [16]uint64
		if mask(0, nil, unsafe.Pointer(&maskWords)) != 0 {
			return state, fmt.Errorf("query worker signal mask")
		}
		state.mask = maskWords[0]
		preemptSignal := int32(23)
		if runtime.GOOS == "darwin" {
			state.mask = uint64(uint32(state.mask))
			preemptSignal = 16
		}
		for i, signal := range []int32{preemptSignal, 27} {
			var words [32]uintptr
			if action(signal, nil, unsafe.Pointer(&words)) != 0 {
				return state, fmt.Errorf("query process signal handler %d", signal)
			}
			state.handlers[i] = words[0]
			state.flags[i] = words[1]
			if runtime.GOOS == "darwin" {
				state.flags[i] >>= 32
			}
		}
		return state, nil
	}
}

func queueWorkerSignals(t *testing.T) func() {
	t.Helper()
	var mask func(int32, unsafe.Pointer, unsafe.Pointer) int32
	var self func() uintptr
	var send func(uintptr, int32) int32
	for _, binding := range []struct {
		name string
		fn   any
	}{{"pthread_sigmask", &mask}, {"pthread_self", &self}, {"pthread_kill", &send}} {
		address, err := purego.Dlsym(purego.RTLD_DEFAULT, binding.name)
		if err != nil {
			t.Fatal(err)
		}
		purego.RegisterFunc(binding.fn, address)
	}
	block, restore, notification := int32(0), int32(2), int32(syscall.SIGUSR1)
	if runtime.GOOS == "darwin" {
		block, restore = 1, 3
	}
	var selected, original [16]uint64
	selected[0] = 1<<uint(notification-1) | 1<<26
	var code int32
	nativeWorker().run(func() {
		code = mask(block, unsafe.Pointer(&selected), unsafe.Pointer(&original))
		if code == 0 {
			code = send(self(), notification)
		}
		if code == 0 {
			code = send(self(), 27)
		}
	})
	if code != 0 {
		t.Fatalf("queue pending worker signals: native error %d", code)
	}
	return func() {
		nativeWorker().run(func() { code = mask(restore, unsafe.Pointer(&original), nil) })
		if code != 0 {
			t.Fatalf("restore worker signal mask: native error %d", code)
		}
	}
}

func signalStackProbe(t *testing.T) func() (nativeSignalStack, error) {
	t.Helper()
	address, err := purego.Dlsym(purego.RTLD_DEFAULT, "sigaltstack")
	if err != nil {
		t.Fatal(err)
	}
	var query func(unsafe.Pointer, unsafe.Pointer) int32
	purego.RegisterFunc(&query, address)
	return func() (nativeSignalStack, error) {
		// Both supported 64-bit Unix ABIs use three words, but Darwin places
		// ss_flags after ss_size while Linux places it before ss_size.
		var words [3]uintptr
		if query(nil, unsafe.Pointer(&words)) != 0 {
			return nativeSignalStack{}, fmt.Errorf("query native alternate signal stack")
		}
		stack := nativeSignalStack{address: words[0], size: words[2], flags: uintptr(uint32(words[1]))}
		if runtime.GOOS == "darwin" {
			stack.size, stack.flags = words[1], uintptr(uint32(words[2]))
		}
		return stack, nil
	}
}

func assertRuntimeWorkerSignalStack(t *testing.T, probe func() (nativeSignalStack, error), before nativeSignalStack) {
	t.Helper()
	var after nativeSignalStack
	var err error
	nativeWorker().run(func() { after, err = probe() })
	if err != nil {
		t.Fatal(err)
	}
	if after != before {
		t.Fatalf("OCaml startup changed the Go worker's alternate signal stack: before=%+v after=%+v", before, after)
	}
}

func TestRuntimePreservesWorkerSignalStack(t *testing.T) {
	path := os.Getenv("LUI_MYGO_TEST_LIBRARY")
	if path == "" {
		t.Skip("run tooling/test_mygo.sh for the OCaml integration test")
	}
	probe := signalStackProbe(t)
	var before nativeSignalStack
	var probeErr error
	nativeWorker().run(func() { before, probeErr = probe() })
	if probeErr != nil {
		t.Fatal(probeErr)
	}
	disabled := uintptr(2)
	if runtime.GOOS == "darwin" {
		disabled = 4
	}
	if before.address == 0 || before.size == 0 || before.flags&disabled != 0 {
		t.Fatalf("Go worker has no alternate signal stack before startup: %+v", before)
	}
	b := New(Config{})
	r, err := OpenRuntime(path, b)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = r.Close() })
	assertRuntimeWorkerSignalStack(t, probe, before)
	if err := r.Resync(); err != nil {
		t.Fatal(err)
	}
	assertRuntimeWorkerSignalStack(t, probe, before)
	if err := r.Close(); err != nil {
		t.Fatal(err)
	}
	assertRuntimeWorkerSignalStack(t, probe, before)
	r, err = OpenRuntime(path, b)
	if err != nil {
		t.Fatal(err)
	}
	assertRuntimeWorkerSignalStack(t, probe, before)
}

// Every startup is a fresh process. A failed process fails its case immediately;
// later successes never replace evidence of a startup or callback crash.
func TestRuntimeFreshProcessStartup(t *testing.T) {
	paths := []struct {
		name string
		path string
	}{
		{"todos", os.Getenv("LUI_MYGO_TEST_LIBRARY")},
		{"components", os.Getenv("LUI_MYGO_COMPONENTS_TEST_LIBRARY")},
	}
	if paths[0].path == "" && paths[1].path == "" {
		t.Skip("set native integration library paths to run startup qualification")
	}
	count := 20
	if value := os.Getenv("LUI_MYGO_STARTUP_PROCESSES"); value != "" {
		var err error
		count, err = strconv.Atoi(value)
		if err != nil || count < 1 {
			t.Fatalf("LUI_MYGO_STARTUP_PROCESSES must be positive: %q", value)
		}
	}
	for _, fixture := range paths {
		if fixture.path == "" {
			continue
		}
		t.Run(fixture.name, func(t *testing.T) {
			for i := 0; i < count; i++ {
				ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
				command := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestRuntimeStartupProcess$", "-test.count=1", "-test.v")
				command.Env = append(os.Environ(), "LUI_MYGO_STARTUP_CHILD="+fixture.path)
				if i%2 == 1 {
					command.Env = append(command.Env, "LUI_MYGO_STARTUP_PENDING_SIGNALS=1")
				}
				output, err := command.CombinedOutput()
				cancel()
				if err != nil {
					t.Fatalf("fresh process %d/%d failed (%s/%s %s): %v\n%s", i+1, count, runtime.GOOS, runtime.GOARCH, runtime.Version(), err, output)
				}
			}
		})
	}
}

func TestRuntimeStartupProcess(t *testing.T) {
	path := os.Getenv("LUI_MYGO_STARTUP_CHILD")
	if path == "" {
		t.Skip("helper is launched by TestRuntimeFreshProcessStartup")
	}
	probe := signalStackProbe(t)
	signals := signalStateProbe(t)
	var releaseSignals func()
	var pendingNotification chan os.Signal
	if os.Getenv("LUI_MYGO_STARTUP_PENDING_SIGNALS") == "1" {
		pendingNotification = make(chan os.Signal, 1)
		signal.Notify(pendingNotification, syscall.SIGUSR1)
		defer signal.Stop(pendingNotification)
		releaseSignals = queueWorkerSignals(t)
	}
	var before nativeSignalStack
	var signalsBefore nativeSignalState
	var probeErr error
	nativeWorker().run(func() {
		before, probeErr = probe()
		if probeErr == nil {
			signalsBefore, probeErr = signals()
		}
	})
	if probeErr != nil {
		t.Fatal(probeErr)
	}
	if err := pprof.StartCPUProfile(io.Discard); err != nil {
		t.Fatal(err)
	}
	defer pprof.StopCPUProfile()
	for session := 0; session < 3; session++ {
		// Startup qualification isolates the native parser/runtime boundary.
		// Component rendering is verified separately without these overrides.
		b := protocolBackend()
		r, err := OpenRuntime(path, b)
		if err != nil {
			t.Fatal(err)
		}
		if len(b.Roots()) == 0 {
			t.Fatal("real OCaml startup delivered no retained roots")
		}
		assertRuntimeWorkerSignalStack(t, probe, before)
		var signalsAfter nativeSignalState
		nativeWorker().run(func() { signalsAfter, probeErr = signals() })
		if probeErr != nil {
			t.Fatal(probeErr)
		}
		if signalsAfter != signalsBefore {
			t.Fatalf("OCaml startup changed caller signal ownership: before=%+v after=%+v", signalsBefore, signalsAfter)
		}
		if releaseSignals != nil {
			// Deliver signals already pending before startup only after verifying
			// the caller's original stack and blocked mask were preserved.
			releaseSignals()
			releaseSignals = nil
			select {
			case <-pendingNotification:
			case <-time.After(3 * time.Second):
				t.Fatal("signal pending before startup was not delivered after caller mask restoration")
			}
			nativeWorker().run(func() { signalsBefore, probeErr = signals() })
			if probeErr != nil {
				t.Fatal(probeErr)
			}
		}
		// Exercise genuine profiling and scheduler preemption on the same OS
		// thread after it returns from OCaml, with both Go facilities enabled.
		nativeWorker().run(func() {
			deadline := time.Now().Add(40 * time.Millisecond)
			for time.Now().Before(deadline) {
			}
		})
		for i := 0; i < 8; i++ {
			if err := r.Resync(); err != nil {
				t.Fatal(err)
			}
		}
		if err := r.Close(); err != nil {
			t.Fatal(err)
		}
		if len(b.Roots()) != 0 {
			t.Fatal("OCaml session stop retained UI nodes")
		}
		assertRuntimeWorkerSignalStack(t, probe, before)
	}
}
