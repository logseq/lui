//go:build (linux || windows) && lui_native_smoke

// The native host fixture uses actual GTK/Win32 windows and ATK/UIA providers.
// Composition callbacks and native surrounding-text protocols are exercised;
// keyboard candidate UI and audible screen-reader output are outside its scope.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"image"
	"image/png"
	"math"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"time"

	"github.com/egoist/mygo"
	"github.com/egoist/mygo/testing/native"
	"github.com/egoist/mygo/ui"
	luimygo "github.com/logseq/lui/platform/mygo"
)

type evidence struct {
	Started        string              `json:"started"`
	Host           string              `json:"host"`
	Scope          string              `json:"scope"`
	Passed         []string            `json:"passed"`
	Accessibility  []native.AccessNode `json:"nativeAccessibility"`
	GlyphInkPixels int                 `json:"committedGlyphInkPixels"`
	Document       string              `json:"nativeInputDocument"`
	Selection      [2]int              `json:"nativeInputSelectionRunes"`
	PopupImages    []string            `json:"nativePopupImageLabels"`
	Capture        string              `json:"contentCapture"`
	Error          string              `json:"error,omitempty"`
}

type nativeGeometry struct {
	Editor, Action ui.Rect
	Width, Height  float32
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
func run() error {
	directory := flag.String("evidence", filepath.Join(os.TempDir(), "lui-mygo-native-smoke"), "directory for native JSON and content PNG evidence")
	flag.Parse()
	if err := os.MkdirAll(*directory, 0755); err != nil {
		return err
	}
	report := evidence{Started: time.Now().UTC().Format(time.RFC3339), Host: runtime.GOOS, Scope: "Real App.Run GTK/Win32 window; native ATK/UIA provider roles/actions, native surrounding/document-feed protocol and production composition callback boundary. No keyboard IME candidate UI or audible Orca/Narrator qualification."}
	var b *luimygo.Backend
	readonlyEvents, presses := 0, 0
	prop := func(id int64, name string, value any) luimygo.Operation {
		return luimygo.Operation{Op: "set-prop", ID: id, Property: name, Value: value}
	}
	b = luimygo.New(luimygo.Config{Dispatch: func(e luimygo.Event) error {
		var ops []luimygo.Operation
		switch e.Kind {
		case "text-changed":
			if e.Node == 4 {
				readonlyEvents++
			}
			ops = append(ops, prop(e.Node, "text", e.Text))
		case "toggle-changed":
			ops = append(ops, prop(e.Node, "checked", e.Checked))
		case "press":
			presses++
			ops = append(ops, prop(7, "text", fmt.Sprintf("Pressed %d", presses)))
		default:
			return nil
		}
		return b.ApplyBatch(luimygo.Batch{Generation: b.Generation() + 1, Ops: ops})
	}})
	defer b.Close()
	ops := []luimygo.Operation{{Op: "create-node", ID: 1, Kind: "root"}, {Op: "create-node", ID: 2, Kind: "column"}, {Op: "insert-child", Parent: 1, Child: 2}, prop(2, "padding", 24), prop(2, "gap", 16)}
	add := func(id int64, kind string, props map[string]any) {
		ops = append(ops, luimygo.Operation{Op: "create-node", ID: id, Kind: kind})
		for name, value := range props {
			ops = append(ops, prop(id, name, value))
		}
		ops = append(ops, luimygo.Operation{Op: "insert-child", Parent: 2, Child: id, Index: int(id) - 3})
	}
	add(3, "text-field", map[string]any{"text": "", "placeholder": "Native editor", "accessibility-label": "Native editor", "change-enabled": true})
	add(4, "text-field", map[string]any{"text": "locked", "placeholder": "Read-only editor", "accessibility-label": "Read-only editor", "read-only": true, "change-enabled": true})
	add(5, "button", map[string]any{"text": "Native action", "press-enabled": true})
	add(6, "checkbox", map[string]any{"text": "Native choice", "checked": false, "toggle-enabled": true})
	add(7, "text", map[string]any{"text": "Pressed 0"})
	ops = append(ops, luimygo.Operation{Op: "create-node", ID: 8, Kind: "context-menu"}, luimygo.Operation{Op: "insert-child", Parent: 5, Child: 8}, luimygo.Operation{Op: "create-node", ID: 9, Kind: "menu-item"}, prop(9, "text", "Native menu icon"), prop(9, "icon", "check"), prop(9, "press-enabled", true), luimygo.Operation{Op: "insert-child", Parent: 8, Child: 9})
	if err := b.ApplyBatch(luimygo.Batch{Generation: 1, Ops: ops}); err != nil {
		return err
	}
	done := make(chan error, 1)
	mygo.App.SetName("LUI Native Qualification")
	mygo.App.WhenReady(func() {
		var geometry nativeGeometry
		window := mygo.NewWindow(mygo.WindowOptions{Title: "LUI Native Qualification", Width: 560, Height: 400, UseContentSize: true, Content: ui.View(func(c *ui.Context) {
			b.View(c)
			geometry.Editor, geometry.Action = b.NativeDemoBounds(c, 3), b.NativeDemoBounds(c, 5)
			geometry.Width, geometry.Height = c.Size()
		})})
		window.Focus()
		go func() {
			err := qualify(window, b, &report, func() int { return readonlyEvents }, func() nativeGeometry { return geometry })
			mygo.RunOnMain(func() { report.Accessibility = native.Accessibility(window.NativeHandle()) })
			// Capture failures too, so missing glyphs or other native regressions
			// retain the actual rendered window alongside their report.
			capture, captureError := window.CapturePage()
			if captureError == nil {
				report.Capture = filepath.Join(*directory, "content.png")
				captureError = os.WriteFile(report.Capture, capture, 0644)
			}
			err = errors.Join(err, captureError)
			if err != nil {
				report.Error = err.Error()
			}
			data, e := json.MarshalIndent(report, "", "  ")
			if e == nil {
				e = os.WriteFile(filepath.Join(*directory, "report.json"), append(data, '\n'), 0644)
			}
			if err == nil {
				err = e
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
			fmt.Printf("PASS: %d real %s native checks; evidence %s\n", len(report.Passed), runtime.GOOS, *directory)
		}
		return err
	default:
		return fmt.Errorf("native window closed before qualification completed")
	}
}

func qualify(window *mygo.Window, b *luimygo.Backend, report *evidence, readonlyEvents func() int, geometry func() nativeGeometry) error {
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
		deadline := time.Now().Add(10 * time.Second)
		var last error
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
	if err := await("real native window is visible", func() error {
		if !native.OnScreen(handle) {
			return fmt.Errorf("window not on screen; interactive native desktop required")
		}
		return nil
	}); err != nil {
		return err
	}
	if err := await("native accessibility editor and control roles", func() error {
		for label, role := range map[string]string{"Native editor": "textbox", "Read-only editor": "textbox", "Native action": "button", "Native choice": "checkbox"} {
			n, ok := find(label)
			if !ok || n.Role != role {
				return fmt.Errorf("%s role=%q want=%q", label, n.Role, role)
			}
		}
		return nil
	}); err != nil {
		return err
	}
	if err := act("focus editable through native accessibility", func() bool { return native.Perform(handle, "Native editor", "focus", "") }); err != nil {
		return err
	}
	if err := await("native accessibility confirms editor focus", func() error {
		n, _ := find("Native editor")
		if !n.Focused {
			return fmt.Errorf("editor not focused")
		}
		return nil
	}); err != nil {
		return err
	}
	if err := act("deliver native preedit callback", func() bool { return native.Compose(handle, "ni", 2, false) }); err != nil {
		return err
	}
	if err := await("preedit remains uncommitted and excluded from OS surrounding text", func() error {
		_, doc := native.InputClient(handle)
		n, _ := b.Node(3)
		if n.String("text") != "" || doc != "" {
			return fmt.Errorf("document=%q model=%q", doc, n.String("text"))
		}
		return nil
	}); err != nil {
		return err
	}
	if err := act("replace preedit through production input callback", func() bool { return native.Compose(handle, "你", 1, false) }); err != nil {
		return err
	}
	if err := act("commit native input", func() bool { return native.Compose(handle, "你", 1, true) }); err != nil {
		return err
	}
	if err := await("native commit reaches model surrounding text and accessibility", func() error {
		selection, doc := native.InputClient(handle)
		n, _ := b.Node(3)
		ax, _ := find("Native editor")
		if doc != "你" || n.String("text") != "你" || ax.Value != "你" || !ax.Focused {
			return fmt.Errorf("document=%q model=%q native=%+v", doc, n.String("text"), ax)
		}
		report.Document, report.Selection = doc, selection
		return nil
	}); err != nil {
		return err
	}
	if err := act("focus readonly through native accessibility", func() bool { return native.Perform(handle, "Read-only editor", "focus", "") }); err != nil {
		return err
	}
	if err := await("readonly native field remains focusable", func() error {
		n, _ := find("Read-only editor")
		if !n.Focused || n.Value != "locked" {
			return fmt.Errorf("readonly native=%+v", n)
		}
		return nil
	}); err != nil {
		return err
	}
	if err := await("committed Unicode glyph has foreground ink in the unfocused native editor", func() error {
		editor, _ := find("Native editor")
		if editor.Focused {
			return fmt.Errorf("editor must be unfocused so a caret cannot satisfy glyph coverage")
		}
		capture, err := window.CapturePage()
		if err != nil {
			return err
		}
		pixels, err := png.Decode(bytes.NewReader(capture))
		if err != nil {
			return err
		}
		g := geometry()
		if g.Width <= 0 || g.Height <= 0 || g.Editor.W <= 8 || g.Editor.H <= 8 {
			return fmt.Errorf("editor geometry is not committed: %+v", g)
		}
		// CapturePage may use physical pixels; convert the committed logical
		// bounds using the actual view size, then remove borders on every side.
		sx, sy := float64(pixels.Bounds().Dx())/float64(g.Width), float64(pixels.Bounds().Dy())/float64(g.Height)
		inner := image.Rect(int(math.Ceil(float64(g.Editor.X+4)*sx)), int(math.Ceil(float64(g.Editor.Y+4)*sy)),
			int(math.Floor(float64(g.Editor.X+g.Editor.W-4)*sx)), int(math.Floor(float64(g.Editor.Y+g.Editor.H-4)*sy)))
		count, span := darkGlyphInk(pixels, inner)
		report.GlyphInkPixels = count
		if count < 8 || span < 3 {
			return fmt.Errorf("committed Unicode glyph has no sufficient foreground ink: pixels=%d span=%d; install CJK font coverage", count, span)
		}
		return nil
	}); err != nil {
		return err
	}
	if err := act("attempt composition on readonly field", func() bool { return native.Compose(handle, "bad", 3, true) }); err != nil {
		return err
	}
	mygo.RunOnMain(func() { native.Perform(handle, "Read-only editor", "value", "bad") })
	time.Sleep(100 * time.Millisecond)
	if err := await("readonly rejects input and native accessibility mutation", func() error {
		n, _ := b.Node(4)
		ax, _ := find("Read-only editor")
		if n.String("text") != "locked" || ax.Value != "locked" || readonlyEvents() != 0 {
			return fmt.Errorf("readonly model=%q native=%+v events=%d", n.String("text"), ax, readonlyEvents())
		}
		return nil
	}); err != nil {
		return err
	}
	if err := act("native accessibility button action", func() bool { return native.Perform(handle, "Native action", "press", "") }); err != nil {
		return err
	}
	if err := await("native button action reaches controlled reducer", func() error {
		n, _ := b.Node(7)
		if n.String("text") != "Pressed 1" {
			return fmt.Errorf("status=%q", n.String("text"))
		}
		return nil
	}); err != nil {
		return err
	}
	if err := act("native accessibility checkbox action", func() bool { return native.Perform(handle, "Native choice", "press", "") }); err != nil {
		return err
	}
	if err := await("native checkbox action reaches reducer and accessibility value", func() error {
		n, _ := b.Node(6)
		ax, _ := find("Native choice")
		if !n.Bool("checked") || ax.Value != "1" {
			return fmt.Errorf("checked=%v native=%+v", n.Bool("checked"), ax)
		}
		return nil
	}); err != nil {
		return err
	}
	if err := act("open native menu with image", func() bool {
		r := geometry().Action
		return r.W > 0 && native.RightClick(handle, float64(r.X+r.W/2), float64(r.Y+r.H/2))
	}); err != nil {
		return err
	}
	if err := await("native popup preserves accessible item name and decoded image", func() error {
		named := false
		for _, labels := range native.Popups() {
			named = named || slices.Contains(labels, "Native menu icon")
		}
		images := native.PopupImages()
		if !named || !slices.Contains(images, "Native menu icon") {
			return fmt.Errorf("menus=%v images=%v", native.Popups(), images)
		}
		report.PopupImages = images
		return nil
	}); err != nil {
		return err
	}
	if err := act("choose named native popup item", func() bool { return native.ChoosePopup("Native menu icon") }); err != nil {
		return err
	}
	if err := await("native menu choice reaches retained item reducer", func() error {
		n, _ := b.Node(7)
		if n.String("text") != "Pressed 2" {
			return fmt.Errorf("status=%q", n.String("text"))
		}
		return nil
	}); err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
	defer cancel()
	paths, err := mygo.Dialog.OpenContext(ctx, mygo.OpenDialogOptions{Parent: window, Title: "LUI native cancellation qualification"})
	if !errors.Is(err, context.DeadlineExceeded) || len(paths) != 0 {
		return fmt.Errorf("native dialog cancellation: paths=%v error=%v", paths, err)
	}
	report.Passed = append(report.Passed, "actual native file dialog closes at context deadline")
	return await("native event loop remains usable after dialog cancellation", func() error {
		if !native.OnScreen(handle) {
			return fmt.Errorf("native window lost after modal cancellation")
		}
		return nil
	})
}

// darkGlyphInk excludes the light field background and borders. Luminance
// admits dark subpixel-antialiased strokes; the inset removes any focus ring.
func darkGlyphInk(pixels image.Image, inner image.Rectangle) (int, int) {
	inner = inner.Intersect(pixels.Bounds())
	count, left, right := 0, inner.Max.X, inner.Min.X
	for y := inner.Min.Y; y < inner.Max.Y; y++ {
		for x := inner.Min.X; x < inner.Max.X; x++ {
			r, g, b, a := pixels.At(x, y).RGBA()
			if a >= 0xc000 && (299*r+587*g+114*b)/1000 < 140*257 {
				count++
				left, right = min(left, x), max(right, x)
			}
		}
	}
	if count == 0 {
		return 0, 0
	}
	return count, right - left + 1
}
