package luimygo

import (
	"os"
	"strings"
	"testing"
	"time"

	"github.com/egoist/mygo/ui"
)

func TestOCamlComponentsClockDrivesSimulatedUpload(t *testing.T) {
	path := os.Getenv("LUI_MYGO_COMPONENTS_LIBRARY")
	if path == "" {
		t.Skip("run tooling/test_mygo.sh for actual Gallery integration")
	}
	b := New(Config{})
	defer b.Close()
	runtime, err := OpenRuntime(path, b)
	if err != nil {
		t.Fatal(err)
	}
	defer runtime.Close()
	tt := ui.NewTester(b.View, 1000, 760)
	var upload int64
	for id, node := range b.nodes {
		if node.Kind == "button" && node.String("text") == "Simulate upload" {
			upload = id
		}
	}
	if upload == 0 {
		t.Fatal("actual Gallery upload trigger is missing")
	}
	progress := func() string {
		for _, node := range b.nodes {
			for _, value := range node.Props {
				if text, ok := value.(string); ok && strings.HasPrefix(text, "Progress fraction: ") {
					return strings.TrimPrefix(text, "Progress fraction: ")
				}
			}
		}
		t.Fatal("actual Gallery progress label is missing")
		return ""
	}

	// Real time: the wake timer invalidates the window and the next frame
	// ticks the OCaml clock, ten 300 ms steps in all.
	if err := runtime.Dispatch(Event{Kind: "press", Node: upload}); err != nil {
		t.Fatal(err)
	}
	if got := progress(); got != "0.0" {
		t.Fatalf("upload started at %s, want 0.0", got)
	}
	deadline := time.Now().Add(10 * time.Second)
	for progress() != "1.0" && time.Now().Before(deadline) {
		time.Sleep(20 * time.Millisecond)
		tt.Frame()
	}
	if got := progress(); got != "1.0" {
		t.Fatalf("upload stalled at %s", got)
	}
	if b.Err() != nil {
		t.Fatal(b.Err())
	}

	// Simulated time: a paused clock only moves through AdvanceClock.
	if err := runtime.SetClockPaused(true); err != nil {
		t.Fatal(err)
	}
	if err := runtime.Dispatch(Event{Kind: "press", Node: upload}); err != nil {
		t.Fatal(err)
	}
	time.Sleep(400 * time.Millisecond)
	tt.Frame()
	if got := progress(); got != "0.0" {
		t.Fatalf("paused clock advanced the upload to %s", got)
	}
	if err := runtime.AdvanceClock(900); err != nil {
		t.Fatal(err)
	}
	if got := progress(); got != "0.3" {
		t.Fatalf("advancing 900 ms reached %s, want 0.3", got)
	}
	if err := runtime.AdvanceClock(60_000); err != nil {
		t.Fatal(err)
	}
	if got := progress(); got != "1.0" {
		t.Fatalf("finished upload reached %s, want 1.0", got)
	}
}
