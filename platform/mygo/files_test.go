package luimygo

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/egoist/mygo/ui"
)

type widgetFileReply struct {
	paths []string
	err   error
}
type widgetFileCall struct {
	options     FileDialogOptions
	ctx         context.Context
	reply       chan widgetFileReply
	duringBuild bool
}
type widgetFileService struct {
	calls     chan widgetFileCall
	committed *atomic.Bool
}

func (s *widgetFileService) OpenFiles(ctx context.Context, options FileDialogOptions) ([]string, error) {
	call := widgetFileCall{options: options, ctx: ctx, reply: make(chan widgetFileReply, 1)}
	if s.committed != nil {
		call.duringBuild = !s.committed.Load()
	}
	select {
	case s.calls <- call:
	case <-ctx.Done():
		return nil, ctx.Err()
	}
	select {
	case reply := <-call.reply:
		return reply.paths, reply.err
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}
func widgetFileBackend(t *testing.T, service FileServices, events *[]Event) *Backend {
	t.Helper()
	b := New(Config{FileServices: service, Dispatch: func(e Event) error { *events = append(*events, e); return nil }})
	apply(t, b, 1, create(1, "root"), create(2, "column"), insert(1, 2, 0))
	return b
}
func widgetFileWait(t *testing.T, tt *ui.Tester, ready func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		tt.Frame()
		if ready() {
			return
		}
		runtime.Gosched()
		time.Sleep(time.Millisecond)
	}
	t.Fatal("file operation failed to settle")
}
func widgetFileNext(t *testing.T, tt *ui.Tester, service *widgetFileService) widgetFileCall {
	t.Helper()
	var call widgetFileCall
	widgetFileWait(t, tt, func() bool {
		select {
		case call = <-service.calls:
			return true
		default:
			return false
		}
	})
	return call
}
func widgetPicked(t *testing.T, events []Event, id int64) map[string]any {
	t.Helper()
	event := widgetLast(t, events, "picked", id)
	decoder := json.NewDecoder(strings.NewReader(event.Payload))
	decoder.UseNumber()
	var payload map[string]any
	if err := decoder.Decode(&payload); err != nil {
		t.Fatalf("invalid picked payload %q: %v", event.Payload, err)
	}
	return payload
}

func TestFilesPickerEchoesTokenAndRetainsUntilCompletion(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "你好 draft.txt")
	if err := os.WriteFile(path, []byte("draft"), 0600); err != nil {
		t.Fatal(err)
	}
	service := &widgetFileService{calls: make(chan widgetFileCall, 4)}
	var events []Event
	b := widgetFileBackend(t, service, &events)
	apply(t, b, 2, create(3, "file-picker"), prop(3, "request", "pick\x00one"), prop(3, "accept", ".txt,image/*"), prop(3, "types", "public.plain-text"), prop(3, "multiple", true), insert(2, 3, 0))
	tt := ui.NewTester(b.View, 500, 320)
	call := widgetFileNext(t, tt, service)
	if !call.options.Multiple || call.options.Directory || len(call.options.Accept) != 2 || len(call.options.Types) != 1 {
		t.Fatalf("dialog constraints lost: %+v", call.options)
	}
	call.reply <- widgetFileReply{paths: []string{path}}
	widgetFileWait(t, tt, func() bool { return widgetCount(events, "picked", 3) == 1 })
	payload := widgetPicked(t, events, 3)
	if payload["request"] != "pick\x00one" {
		t.Fatalf("request token changed: %#v", payload)
	}
	files, ok := payload["files"].([]any)
	if !ok || len(files) != 1 {
		t.Fatalf("picked files: %#v", payload)
	}
	entry := files[0].(map[string]any)
	if entry["path"] != path || entry["name"] != "你好 draft.txt" || !strings.HasPrefix(entry["content-type"].(string), "text/plain") {
		t.Fatalf("file metadata: %#v", entry)
	}
	apply(t, b, 3, prop(3, "request", "ignored while retained"))
	tt.Frame()
	select {
	case <-service.calls:
		t.Fatal("second request bypassed completion handshake")
	default:
	}
	apply(t, b, 4, prop(3, "completion", "pick\x00one"), prop(3, "request", int64(9007199254740993)))
	tt.Frame()
	second := widgetFileNext(t, tt, service)
	second.reply <- widgetFileReply{paths: []string{path}}
	widgetFileWait(t, tt, func() bool { return widgetCount(events, "picked", 3) == 2 })
	if got := widgetPicked(t, events, 3)["request"]; got != json.Number("9007199254740993") {
		t.Fatalf("integer token lost precision: %#v", got)
	}
}

func TestFilesPickerCancelFailureAndDisabledRequests(t *testing.T) {
	for _, failure := range []bool{false, true} {
		t.Run(fmt.Sprint(failure), func(t *testing.T) {
			service := &widgetFileService{calls: make(chan widgetFileCall, 4)}
			var events []Event
			b := widgetFileBackend(t, service, &events)
			apply(t, b, 2, create(3, "file-picker"), prop(3, "request", 1), prop(3, "enabled", false), insert(2, 3, 0))
			tt := ui.NewTester(b.View, 500, 320)
			select {
			case <-service.calls:
				t.Fatal("disabled picker started dialog")
			default:
			}
			apply(t, b, 3, prop(3, "enabled", true))
			tt.Frame()
			call := widgetFileNext(t, tt, service)
			reply := widgetFileReply{}
			if failure {
				reply.err = fmt.Errorf("native presentation failed")
			}
			call.reply <- reply
			widgetFileWait(t, tt, func() bool { return widgetCount(events, "dismiss", 3) == 1 })
			for range 3 {
				tt.Frame()
			}
			if widgetCount(events, "dismiss", 3) != 1 || widgetCount(events, "picked", 3) != 0 {
				t.Fatalf("cancel/failure events: %+v", events)
			}
			select {
			case <-service.calls:
				t.Fatal("cancelled request reopened automatically")
			default:
			}
		})
	}
}

func TestFilesPickerStartsAfterCommitAndIgnoresDisposedCompletion(t *testing.T) {
	service := &widgetFileService{calls: make(chan widgetFileCall, 4), committed: &atomic.Bool{}}
	var events []Event
	b := widgetFileBackend(t, service, &events)
	apply(t, b, 2, create(3, "file-picker"), prop(3, "request", "old"), insert(2, 3, 0))
	tt := ui.NewTester(func(c *ui.Context) { c.AfterFrame(func() { service.committed.Store(true) }); b.View(c) }, 500, 320)
	old := widgetFileNext(t, tt, service)
	if old.duringBuild {
		t.Fatal("native dialog started during view construction")
	}
	apply(t, b, 3, Operation{Op: "detach-subtree", ID: 3}, create(3, "file-picker"), prop(3, "request", "new"), insert(2, 3, 0))
	select {
	case <-old.ctx.Done():
	default:
		t.Fatal("committed retirement did not cancel picker before next frame")
	}
	tt.Frame()
	next := widgetFileNext(t, tt, service)
	select {
	case <-old.ctx.Done():
	default:
		t.Fatal("retired picker operation was not cancelled")
	}
	old.reply <- widgetFileReply{paths: []string{"/old/result"}}
	next.reply <- widgetFileReply{}
	widgetFileWait(t, tt, func() bool { return widgetCount(events, "dismiss", 3) == 1 })
	if widgetCount(events, "picked", 3) != 0 {
		t.Fatalf("stale picker emitted completion: %+v", events)
	}
}

func TestFilesPickerDirectoryAndAcknowledgedMount(t *testing.T) {
	service := &widgetFileService{calls: make(chan widgetFileCall, 4)}
	var events []Event
	b := widgetFileBackend(t, service, &events)
	apply(t, b, 2, create(3, "file-picker"), prop(3, "request", 42), prop(3, "completion", 42), prop(3, "directory", true), insert(2, 3, 0))
	tt := ui.NewTester(b.View, 500, 320)
	select {
	case <-service.calls:
		t.Fatal("acknowledged token re-presented after mounting")
	default:
	}
	apply(t, b, 3, prop(3, "request", 43))
	tt.Frame()
	call := widgetFileNext(t, tt, service)
	if !call.options.Directory {
		t.Fatal("directory selection constraint lost")
	}
	call.reply <- widgetFileReply{paths: []string{t.TempDir()}}
	widgetFileWait(t, tt, func() bool { return widgetCount(events, "picked", 3) == 1 })
}

func TestFilesPreviewOwnsTextPresentationAndDismissal(t *testing.T) {
	dir := t.TempDir()
	first := filepath.Join(dir, "draft.txt")
	second := filepath.Join(dir, "updated.txt")
	if err := os.WriteFile(first, []byte("你好 draft\nLine two"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(second, []byte("Updated preview"), 0600); err != nil {
		t.Fatal(err)
	}
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "file-preview"), prop(3, "path", first), insert(2, 3, 0))
	tt := ui.NewTester(b.View, 700, 500)
	widgetFileWait(t, tt, func() bool { return tt.HasText("你好 draft") })
	widgetTexts(t, tt, []string{"draft.txt", "Line two", "Close preview"}, nil)
	apply(t, b, 3, prop(3, "path", second))
	tt.Frame()
	widgetFileWait(t, tt, func() bool { return tt.HasText("Updated preview") })
	widgetTexts(t, tt, nil, []string{"你好 draft"})
	widgetClick(t, tt, "Close preview")
	if widgetCount(events, "dismiss", 3) != 1 {
		t.Fatalf("owned preview must dismiss once: %+v", events)
	}
	tt.Key(0, ui.KeyEscape)
	tt.Frame()
	if widgetCount(events, "dismiss", 3) != 1 {
		t.Fatal("preview dismissed twice")
	}
	if len(tt.OpenedURLs()) != 0 {
		t.Fatal("preview launched an external app")
	}
}

func TestFilesPreviewRendersRealImagePixels(t *testing.T) {
	path := filepath.Join(t.TempDir(), "red.png")
	f, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	pixels := image.NewRGBA(image.Rect(0, 0, 40, 30))
	for y := range 30 {
		for x := range 40 {
			pixels.SetRGBA(x, y, color.RGBA{R: 255, A: 255})
		}
	}
	if err := png.Encode(f, pixels); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	b := mounted(t, nil)
	apply(t, b, 2, create(3, "file-preview"), prop(3, "path", path), insert(2, 3, 0))
	tt := ui.NewTester(b.View, 700, 500)
	var r ui.Rect
	widgetFileWait(t, tt, func() bool { var ok bool; r, ok = tt.Find("Preview page"); return ok })
	pixel := tt.Image().RGBAAt(int(r.X+r.W/2), int(r.Y+r.H/2))
	if pixel.R < 240 || pixel.G > 15 || pixel.B > 15 {
		t.Fatalf("preview did not decode actual image: %+v", pixel)
	}
}

func widgetPDF(t *testing.T, path string) {
	t.Helper()
	var data bytes.Buffer
	data.WriteString("%PDF-1.4\n")
	offsets := []int{0}
	objects := []string{"<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>", "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << >> /Contents 4 0 R >>"}
	content := "1 0 0 rg 0 0 50 100 re f\n0 0 1 rg 50 0 50 100 re f\n"
	objects = append(objects, fmt.Sprintf("<< /Length %d >>\nstream\n%sendstream", len(content), content))
	for i, obj := range objects {
		offsets = append(offsets, data.Len())
		fmt.Fprintf(&data, "%d 0 obj\n%s\nendobj\n", i+1, obj)
	}
	xref := data.Len()
	fmt.Fprintf(&data, "xref\n0 %d\n0000000000 65535 f \n", len(offsets))
	for _, offset := range offsets[1:] {
		fmt.Fprintf(&data, "%010d 00000 n \n", offset)
	}
	fmt.Fprintf(&data, "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n", len(offsets), xref)
	if err := os.WriteFile(path, data.Bytes(), 0600); err != nil {
		t.Fatal(err)
	}
}

func TestFilesPreviewRasterizesActualPDFPage(t *testing.T) {
	path := filepath.Join(t.TempDir(), "colors.pdf")
	widgetPDF(t, path)
	b := mounted(t, nil)
	apply(t, b, 2, create(3, "file-preview"), prop(3, "path", path), insert(2, 3, 0))
	tt := ui.NewTester(b.View, 700, 500)
	var r ui.Rect
	widgetFileWait(t, tt, func() bool { var ok bool; r, ok = tt.Find("Preview page"); return ok })
	left := tt.Image().RGBAAt(int(r.X+r.W/4), int(r.Y+r.H/2))
	right := tt.Image().RGBAAt(int(r.X+r.W*3/4), int(r.Y+r.H/2))
	if left.R < 240 || left.B > 15 || right.B < 240 || right.R > 15 {
		t.Fatalf("PDF page colors were not rasterized: left=%+v right=%+v", left, right)
	}
	widgetTexts(t, tt, []string{"colors.pdf", "Page 1 of 1"}, nil)
}

func TestFilesPreviewMissingUnsupportedAndDisposal(t *testing.T) {
	for _, name := range []string{"missing.txt", "unsupported.bin"} {
		t.Run(name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), name)
			if strings.HasSuffix(name, ".bin") {
				if err := os.WriteFile(path, []byte{0, 255, 0, 1}, 0600); err != nil {
					t.Fatal(err)
				}
			}
			var events []Event
			b := mounted(t, func(e Event) error { events = append(events, e); return nil })
			apply(t, b, 2, create(3, "file-preview"), prop(3, "path", path), insert(2, 3, 0))
			tt := ui.NewTester(b.View, 700, 500)
			widgetFileWait(t, tt, func() bool { return tt.HasText("Cannot preview") })
			widgetTexts(t, tt, []string{"Close preview"}, nil)
			apply(t, b, 3, Operation{Op: "detach-subtree", ID: 3})
			tt.Frame()
			widgetTexts(t, tt, nil, []string{"Cannot preview", "Close preview"})
			if widgetCount(events, "dismiss", 3) != 0 {
				t.Fatal("disposal masqueraded as user dismissal")
			}
		})
	}
}
