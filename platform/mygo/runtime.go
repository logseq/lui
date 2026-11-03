package luimygo

import (
	"fmt"
	"path/filepath"
	goruntime "runtime"
	"sync"
	"unsafe"

	"github.com/ebitengine/purego"
)

type nativeFunctions struct {
	pointer         map[string]func(int64, float64, float64, int32, int32, string, int32) int32
	picked          func(int64, string, int32) int32
	visibleRange    func(int64, int64, int64) int32
	virtualWindow   func(int64, int64, int64, int64, *int64, int32) int32
	scrollCompleted func(int64, int64, string) int32
	scrollEdges     func(int64, int32, int32) int32
	navigationKey   func(int64, string, int32, int32) int32

	pressEx      func(int64, int32) int32
	start        func(uintptr, int32, int32) int32
	stop, resync func() int32
	text         func(int64, string, int32) int32
	toggle       func(int64, int32) int32
	toggleDetail func(int64, int32, int32) int32
	value        func(int64, float64) int32
	extension    func(int64, string, int32, string, int32, string, int32) int32
	node         map[string]func(int64) int32
}
type runtimeWorker struct {
	jobs      chan func()
	path      string
	library   uintptr
	callback  uintptr
	pending   []string
	active    *Runtime
	functions nativeFunctions
}

var workerOnce sync.Once
var worker *runtimeWorker

func nativeWorker() *runtimeWorker {
	workerOnce.Do(func() {
		worker = &runtimeWorker{jobs: make(chan func())}
		go func() {
			// caml_startup registers this OS thread. All later entries must use it;
			// the OCaml runtime and its domain thread live until process exit.
			goruntime.LockOSThread()
			for job := range worker.jobs {
				job()
			}
		}()
	})
	return worker
}
func (w *runtimeWorker) run(fn func()) {
	done := make(chan struct{})
	w.jobs <- func() { defer close(done); fn() }
	<-done
}

// Runtime owns a session in an OCaml shared library exporting lui_ocaml_*.
// OpenRuntime and all session methods are called on the backend's UI goroutine.
// A process can host one OCaml runtime library and one active session.
type Runtime struct {
	backend *Backend
	worker  *runtimeWorker
	closed  bool
}

func OpenRuntime(path string, b *Backend) (*Runtime, error) {
	if b == nil {
		return nil, fmt.Errorf("lui: backend is required")
	}
	absolute, err := filepath.Abs(path)
	if err != nil {
		return nil, err
	}
	w := nativeWorker()
	r := &Runtime{backend: b, worker: w}
	var batches []string
	w.run(func() {
		if w.active != nil {
			err = fmt.Errorf("lui: an OCaml session is already active")
			return
		}
		if w.library != 0 && w.path != absolute {
			err = fmt.Errorf("lui: cannot replace a loaded OCaml runtime library")
			return
		}
		if w.library == 0 {
			if err = w.load(absolute); err != nil {
				return
			}
		}
		w.pending = nil
		platform := int32(0)
		switch goruntime.GOOS {
		case "darwin":
			platform = 1
		case "linux":
			platform = 4
		case "windows":
			platform = 5
		}
		host := int32(0)
		if w.functions.virtualWindow != nil {
			host = 5
		}
		if w.functions.start(w.callback, platform, host) != 1 {
			w.functions.stop()
			w.pending = nil
			err = fmt.Errorf("lui: OCaml runtime initialization failed")
			return
		}
		batches = w.pending
		w.pending = nil
		w.active = r
	})
	if err != nil {
		return nil, err
	}
	b.config.Dispatch = r.Dispatch
	b.err = nil
	if err = r.receive(batches, true); err != nil {
		_ = r.Close()
		return nil, err
	}
	return r, nil
}
func (w *runtimeWorker) load(path string) error {
	handle, err := openLibrary(path)
	if err != nil {
		return fmt.Errorf("lui: load runtime: %w", err)
	}
	names := map[string]string{
		"press": "press", "long-press": "long_press", "submit": "submit", "dismiss": "dismiss",
		"double-press": "double_press", "appear": "appear", "change": "radio_changed",
		"pointer-enter": "pointer_enter", "pointer-leave": "pointer_leave", "load": "load",
		"navigate-previous": "navigate_previous", "navigate-next": "navigate_next",
	}
	f := nativeFunctions{node: map[string]func(int64) int32{}, pointer: map[string]func(int64, float64, float64, int32, int32, string, int32) int32{}}
	bindings := map[string]any{"press_ex": &f.pressEx, "start": &f.start, "stop": &f.stop, "resync": &f.resync, "text_changed_utf8": &f.text, "toggle_changed": &f.toggle, "slider_changed": &f.value, "extension_event_utf8": &f.extension}
	bindings["picked_utf8"] = &f.picked
	bindings["visible_range"] = &f.visibleRange
	bindings["scroll_completed"] = &f.scrollCompleted
	bindings["scroll_edges"] = &f.scrollEdges
	bindings["navigation_key_utf8"] = &f.navigationKey
	bindings["toggle_changed_detail"] = &f.toggleDetail
	pointerNames := map[string]string{"press-detail": "press_detail_utf8", "pointer-down": "pointer_down_utf8", "pointer-up": "pointer_up_utf8", "pointer-move": "pointer_move_utf8", "pointer-cancel": "pointer_cancel_utf8", "context-menu-press": "context_menu_press_utf8"}
	for _, suffix := range pointerNames {
		var fn func(int64, float64, float64, int32, int32, string, int32) int32
		bindings[suffix] = &fn
	}
	for _, suffix := range names {
		var fn func(int64) int32
		bindings[suffix] = &fn
	}
	// Resolve every symbol before registration/startup; an incomplete library
	// is an ordinary error, never a panic from RegisterLibFunc.
	symbols := map[string]uintptr{}
	for suffix := range bindings {
		ptr, lookupErr := librarySymbol(handle, "lui_ocaml_"+suffix)
		if lookupErr != nil {
			_ = closeLibrary(handle)
			return fmt.Errorf("lui: missing symbol lui_ocaml_%s: %w", suffix, lookupErr)
		}
		symbols[suffix] = ptr
	}
	for suffix, binding := range bindings {
		purego.RegisterFunc(binding, symbols[suffix])
	}
	for event, suffix := range names {
		f.node[event] = *bindings[suffix].(*func(int64) int32)
	}
	for event, suffix := range pointerNames {
		f.pointer[event] = *bindings[suffix].(*func(int64, float64, float64, int32, int32, string, int32) int32)
	}
	if ptr, lookupErr := librarySymbol(handle, "lui_ocaml_virtual_window"); lookupErr == nil {
		purego.RegisterFunc(&f.virtualWindow, ptr)
	}
	if goruntime.GOOS == "windows" {
		// Windows requires a pointer-sized callback result. The C void
		// callback ignores it; CDecl preserves the bridge's calling convention.
		w.callback = purego.NewCallback(func(_ purego.CDecl, ptr unsafe.Pointer) uintptr {
			w.pending = append(w.pending, cString(ptr))
			return 0
		})
	} else {
		w.callback = purego.NewCallback(func(ptr unsafe.Pointer) { w.pending = append(w.pending, cString(ptr)) })
	}
	w.functions = f
	w.library = handle
	w.path = path
	return nil
}
func cString(ptr unsafe.Pointer) string {
	if ptr == nil {
		return ""
	}
	// The C bridge owns a NUL-terminated buffer valid only during the callback.
	// Copy it before returning across the ABI, without retaining C memory.
	p := ptr
	size := 0
	for *(*byte)(unsafe.Add(p, size)) != 0 {
		size++
	}
	return string(unsafe.Slice((*byte)(p), size))
}
func (r *Runtime) receive(batches []string, snapshot bool) error {
	for i, source := range batches {
		if err := r.backend.applyJSONString(source, snapshot && i == 0); err != nil {
			return err
		}
	}
	return nil
}
func (r *Runtime) invoke(fn func(nativeFunctions) int32) ([]string, error) {
	var batches []string
	var err error
	r.worker.run(func() {
		w := r.worker
		if r.closed || w.active != r {
			err = fmt.Errorf("lui: OCaml session is closed")
			return
		}
		w.pending = nil
		if fn(w.functions) != 1 {
			err = fmt.Errorf("lui: OCaml rejected the call")
		}
		batches = w.pending
		w.pending = nil
	})
	return batches, err
}
func (r *Runtime) Dispatch(e Event) error {
	if err := validateEvent(e); err != nil {
		return err
	}
	// Encode extension values before entering native code, preserving UTF-8 and
	// embedded NULs through the length-carrying ABI.
	payload, err := extensionPayload(e)
	if err != nil {
		return err
	}
	var unknown bool
	batches, err := r.invoke(func(f nativeFunctions) int32 {
		switch e.Kind {
		case "press-detail", "pointer-down", "pointer-up", "pointer-move", "pointer-cancel", "context-menu-press":
			return f.pointer[e.Kind](e.Node, e.X, e.Y, e.Modifiers, e.Button, e.TargetClass, int32(len(e.TargetClass)))
		case "picked":
			return f.picked(e.Node, e.Payload, int32(len(e.Payload)))
		case "virtual-window":
			if f.virtualWindow == nil {
				unknown = true
				return 0
			}
			var pins *int64
			if len(e.Pins) > 0 {
				pins = &e.Pins[0]
			}
			return f.virtualWindow(e.Node, e.Generation, e.First, e.Last, pins, int32(len(e.Pins)))
		case "visible-range":
			return f.visibleRange(e.Node, e.First, e.Last)
		case "scroll-completed":
			return f.scrollCompleted(e.Node, e.Token, e.Outcome)
		case "scroll-edges":
			return f.scrollEdges(e.Node, nativeBool(e.AtStart), nativeBool(e.AtEnd))
		case "navigation-key":
			return f.navigationKey(e.Node, e.Key, int32(len(e.Key)), nativeBool(e.Shift))
		case "press-modifiers":
			return f.pressEx(e.Node, e.Modifiers)
		case "text-changed":
			return f.text(e.Node, e.Text, int32(len(e.Text)))
		case "toggle-changed":
			checked := int32(0)
			if e.Checked {
				checked = 1
			}
			return f.toggle(e.Node, checked)
		case "toggle-changed-detail":
			return f.toggleDetail(e.Node, nativeBool(e.Checked), e.Modifiers)
		case "value-changed":
			return f.value(e.Node, e.Value)
		case "extension-event":
			return f.extension(e.Node, e.Identifier, int32(len(e.Identifier)), e.Name, int32(len(e.Name)), payload, int32(len(payload)))
		default:
			if fn := f.node[e.Kind]; fn != nil {
				return fn(e.Node)
			}
			unknown = true
			return 0
		}
	})
	goruntime.KeepAlive(e.Pins)
	if unknown {
		return fmt.Errorf("lui: unsupported runtime event %q", e.Kind)
	}
	if err != nil {
		return err
	}
	if applyErr := r.receive(batches, false); applyErr != nil {
		if recoveryErr := r.Resync(); recoveryErr != nil {
			return fmt.Errorf("lui: delta rejected (%v), snapshot failed: %w", applyErr, recoveryErr)
		}
	}
	return nil
}
func (r *Runtime) Resync() error {
	batches, err := r.invoke(func(f nativeFunctions) int32 { return f.resync() })
	if err != nil {
		return err
	}
	if len(batches) != 1 {
		return fmt.Errorf("lui: expected one authoritative snapshot, got %d", len(batches))
	}
	return r.receive(batches, true)
}

// Close disposes the app once. The runtime library stays loaded because OCaml
// domains and registered callbacks cannot safely be unloaded from a process.
func (r *Runtime) Close() error {
	if r.closed {
		return nil
	}
	batches, err := r.invoke(func(f nativeFunctions) int32 { return f.stop() })
	r.worker.run(func() {
		if r.worker.active == r {
			r.worker.active = nil
		}
		r.closed = true
	})
	if err != nil {
		return err
	}
	return r.receive(batches, false)
}

func nativeBool(value bool) int32 {
	if value {
		return 1
	}
	return 0
}
