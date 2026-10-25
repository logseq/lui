//go:build darwin && lui_native_smoke

// lui-mygo-native-smoke qualifies the adapter in a real macOS GPU window.
// It reads NSAccessibility APIs; it does not test audible screen-reader output.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/egoist/mygo"
	"github.com/egoist/mygo/testing/native"
	"github.com/egoist/mygo/ui"
	luimygo "github.com/logseq/lui/platform/mygo"
)

type evidence struct {
	Started       string              `json:"started"`
	Passed        []string            `json:"passed"`
	Accessibility []native.AccessNode `json:"nsAccessibility"`
	Document      string              `json:"nativeInputDocument"`
	Selection     [2]int              `json:"nativeInputSelectionUTF16"`
	Capture       string              `json:"contentCapture"`
	Error         string              `json:"error,omitempty"`
	Scope         string              `json:"scope"`
	WindowNumber  int                 `json:"windowServerID"`
	WindowBounds  mygo.Rectangle      `json:"windowBounds"`
	ContentBounds mygo.Rectangle      `json:"contentBounds"`
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	directory := flag.String("evidence", "/tmp/lui-mygo-native-smoke", "directory for JSON and native content PNG evidence")
	flag.Parse()
	if err := os.MkdirAll(*directory, 0755); err != nil {
		return err
	}
	report := evidence{Started: time.Now().UTC().Format(time.RFC3339), Scope: "Real App.Run GPU window, Cocoa NSTextInputClient and NSAccessibility API checks against canonical adapter wire fixture; no audible VoiceOver qualification. PNG uses Window.CapturePage content capture."}
	var b *luimygo.Backend
	presses, readonlyEvents := 0, 0
	property := func(id int64, name string, value any) luimygo.Operation {
		return luimygo.Operation{Op: "set-prop", ID: id, Property: name, Value: value}
	}
	b = luimygo.New(luimygo.Config{Dispatch: func(e luimygo.Event) error {
		var ops []luimygo.Operation
		switch e.Kind {
		case "text-changed":
			if e.Node == 4 {
				readonlyEvents++
			}
			ops = append(ops, property(e.Node, "text", e.Text))
		case "toggle-changed":
			ops = append(ops, property(e.Node, "checked", e.Checked))
		case "press":
			presses++
			ops = append(ops, property(7, "text", fmt.Sprintf("Pressed %d", presses)))
		default:
			return nil
		}
		return b.ApplyBatch(luimygo.Batch{Generation: b.Generation() + 1, Ops: ops})
	}})
	defer b.Close()
	ops := []luimygo.Operation{{Op: "create-node", ID: 1, Kind: "root"}, {Op: "create-node", ID: 2, Kind: "column"}, {Op: "insert-child", Parent: 1, Child: 2, Index: 0}, property(2, "padding", 24), property(2, "gap", 16)}
	add := func(id int64, kind string, props map[string]any) {
		ops = append(ops, luimygo.Operation{Op: "create-node", ID: id, Kind: kind})
		for name, value := range props {
			ops = append(ops, property(id, name, value))
		}
		ops = append(ops, luimygo.Operation{Op: "insert-child", Parent: 2, Child: id, Index: int(id) - 3})
	}
	add(3, "text-field", map[string]any{"text": "", "placeholder": "Native editor", "accessibility-label": "Native editor", "change-enabled": true})
	add(4, "text-field", map[string]any{"text": "locked", "placeholder": "Read-only editor", "accessibility-label": "Read-only editor", "read-only": true, "change-enabled": true})
	add(5, "button", map[string]any{"text": "Native action", "press-enabled": true})
	add(6, "checkbox", map[string]any{"text": "Native choice", "checked": false, "toggle-enabled": true})
	add(7, "text", map[string]any{"text": "Pressed 0"})
	if err := b.ApplyBatch(luimygo.Batch{Generation: 1, Ops: ops}); err != nil {
		return err
	}
	done := make(chan error, 1)
	mygo.App.SetName("LUI Native Qualification")
	mygo.App.WhenReady(func() {
		window := mygo.NewWindow(mygo.WindowOptions{Title: "LUI Native Qualification", Width: 560, Height: 400, UseContentSize: true, Content: ui.View(b.View)})
		window.Focus()
		go func() {
			mygo.RunOnMain(func() {
				report.WindowNumber = native.WindowNumber(window.NativeHandle())
				report.WindowBounds = window.Bounds()
				report.ContentBounds = window.ContentBounds()
			})
			err := qualify(window, b, &report, func() int { return readonlyEvents })
			mygo.RunOnMain(func() { report.Accessibility = native.Accessibility(window.NativeHandle()) })
			if err == nil {
				png, captureErr := window.CapturePage()
				if captureErr != nil {
					err = captureErr
				} else {
					report.Capture = filepath.Join(*directory, "content.png")
					err = os.WriteFile(report.Capture, png, 0644)
				}
			}
			if err != nil {
				report.Error = err.Error()
			}
			data, encodeErr := json.MarshalIndent(report, "", "  ")
			if encodeErr == nil {
				encodeErr = os.WriteFile(filepath.Join(*directory, "report.json"), append(data, '\n'), 0644)
			}
			if err == nil {
				err = encodeErr
			}
			done <- err
			mygo.RunOnMain(func() { b.Close(); window.Close() })
		}()
	})
	mygo.App.OnWindowAllClosed(func() { mygo.App.Quit() })
	if err := mygo.App.Run(); err != nil {
		return err
	}
	select {
	case err := <-done:
		if err == nil {
			fmt.Printf("PASS: %d native checks; evidence %s\n", len(report.Passed), *directory)
		}
		return err
	default:
		return fmt.Errorf("native window closed before qualification completed")
	}
}

func qualify(window *mygo.Window, b *luimygo.Backend, report *evidence, readonlyEvents func() int) error {
	handle := window.NativeHandle()
	act := func(name string, fn func() bool) error {
		ok := false
		mygo.RunOnMain(func() { ok = fn() })
		if !ok {
			return fmt.Errorf("%s: native API rejected action", name)
		}
		return nil
	}
	await := func(name string, condition func() error) error {
		var last error
		deadline := time.Now().Add(10 * time.Second)
		for {
			mygo.RunOnMain(func() {
				last = condition()
				if last == nil {
					last = b.Err()
				}
			})
			if last == nil {
				report.Passed = append(report.Passed, name)
				return nil
			}
			if time.Now().After(deadline) {
				return fmt.Errorf("%s: %w", name, last)
			}
			time.Sleep(20 * time.Millisecond)
		}
	}
	find := func(label string) (native.AccessNode, bool) {
		for _, n := range native.Accessibility(handle) {
			if n.Label == label {
				return n, true
			}
		}
		return native.AccessNode{}, false
	}
	if err := await("WindowServer confirms real window on screen", func() error {
		if !native.OnScreen(handle) {
			return fmt.Errorf("window is not visible; a logged-in macOS desktop is required")
		}
		return nil
	}); err != nil {
		return err
	}
	if err := await("NSAccessibility editor and control roles", func() error {
		for label, role := range map[string]string{"Native editor": "AXTextField", "Read-only editor": "AXTextField", "Native action": "AXButton", "Native choice": "AXCheckBox"} {
			n, ok := find(label)
			if !ok || n.Role != role {
				return fmt.Errorf("%s: role %q, want %q", label, n.Role, role)
			}
		}
		return nil
	}); err != nil {
		return err
	}
	if err := act("focus editable through NSAccessibility", func() bool { return native.Perform(handle, "Native editor", "focus", "") }); err != nil {
		return err
	}
	if err := await("native editor owns focus", func() error {
		n, ok := find("Native editor")
		if !ok || !n.Focused {
			return fmt.Errorf("editor is not focused")
		}
		return nil
	}); err != nil {
		return err
	}
	if err := act("set native IME marked text", func() bool { return native.Compose(handle, "ni", 2, false) }); err != nil {
		return err
	}
	if err := await("NSTextInputClient exposes uncommitted marked text", func() error {
		selection, doc := native.InputClient(handle)
		n, _ := b.Node(3)
		if doc != "ni" || selection != ([2]int{2, 0}) || n.String("text") != "" {
			return fmt.Errorf("document=%q selection=%v model=%q", doc, selection, n.String("text"))
		}
		return nil
	}); err != nil {
		return err
	}
	if err := act("replace native marked text", func() bool { return native.Compose(handle, "你", 1, false) }); err != nil {
		return err
	}
	if err := await("native IME updates marked UTF-16 selection", func() error {
		selection, doc := native.InputClient(handle)
		if doc != "你" || selection != ([2]int{1, 0}) {
			return fmt.Errorf("document=%q selection=%v", doc, selection)
		}
		return nil
	}); err != nil {
		return err
	}
	if err := act("commit native IME", func() bool { return native.Compose(handle, "你", 1, true) }); err != nil {
		return err
	}
	if err := await("native IME commit reaches controlled model and AX value", func() error {
		selection, doc := native.InputClient(handle)
		n, _ := b.Node(3)
		ax, _ := find("Native editor")
		if doc != "你" || n.String("text") != "你" || ax.Value != "你" || !ax.Focused {
			return fmt.Errorf("document=%q model=%q AX=%+v", doc, n.String("text"), ax)
		}
		report.Document = doc
		report.Selection = selection
		return nil
	}); err != nil {
		return err
	}
	if err := act("focus read-only editor through NSAccessibility", func() bool { return native.Perform(handle, "Read-only editor", "focus", "") }); err != nil {
		return err
	}
	if err := await("read-only editor remains focusable", func() error {
		n, _ := find("Read-only editor")
		if !n.Focused || n.Value != "locked" {
			return fmt.Errorf("readonly AX=%+v", n)
		}
		return nil
	}); err != nil {
		return err
	}
	if err := act("attempt native input on read-only editor", func() bool { return native.Compose(handle, "bad", 3, true) }); err != nil {
		return err
	}
	if err := await("read-only suppresses native editing", func() error {
		_, doc := native.InputClient(handle)
		n, _ := b.Node(4)
		ax, _ := find("Read-only editor")
		// A read-only editor has no writable native input client. Its
		// retained document remains available to accessibility and copy.
		if n.String("text") != "locked" || ax.Value != "locked" || readonlyEvents() != 0 || (doc != "" && doc != "locked") {
			return fmt.Errorf("readonly document=%q model=%q events=%d", doc, n.String("text"), readonlyEvents())
		}
		return nil
	}); err != nil {
		return err
	}
	if err := act("read-only NSAccessibility denies value setter", func() bool { return !native.Perform(handle, "Read-only editor", "value", "bad") }); err != nil {
		return err
	}
	report.Passed = append(report.Passed, "read-only NSAccessibility denies value setter")
	if err := act("press button through NSAccessibility", func() bool { return native.Perform(handle, "Native action", "press", "") }); err != nil {
		return err
	}
	if err := await("NSAccessibility button action reaches reducer", func() error {
		n, _ := b.Node(7)
		if n.String("text") != "Pressed 1" {
			return fmt.Errorf("status=%q", n.String("text"))
		}
		return nil
	}); err != nil {
		return err
	}
	if err := act("toggle checkbox through NSAccessibility", func() bool { return native.Perform(handle, "Native choice", "press", "") }); err != nil {
		return err
	}
	if err := await("NSAccessibility checkbox action updates model and native value", func() error {
		n, _ := b.Node(6)
		ax, _ := find("Native choice")
		if !n.Bool("checked") || ax.Value != "1" {
			return fmt.Errorf("checked=%v AX=%+v", n.Bool("checked"), ax)
		}
		return nil
	}); err != nil {
		return err
	}
	mygo.RunOnMain(func() { report.Accessibility = native.Accessibility(handle) })
	return nil
}
