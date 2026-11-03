package luimygo

import (
	"os"
	"testing"
	"time"

	"github.com/egoist/mygo/ui"
)

func TestOCamlComponentsGallerySingleToastLifecycle(t *testing.T) {
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
	tt.SetFocused(true)
	var trigger int64
	for id, node := range b.nodes {
		if node.Kind == "button" && (node.String("text") == "Show notification" || node.String("text") == "Show notifications") {
			trigger = id
		}
	}
	if trigger == 0 {
		t.Fatal("actual Gallery notification trigger is missing")
	}
	show := func() {
		t.Helper()
		n, _ := b.Node(trigger)
		visible := func() bool {
			r, found := tt.Find(n.String("text"))
			return found && r.Y >= 80 && r.Y+r.H < 360
		}
		if !visible() {
			tt.Scroll(950, 700, 0, -100000)
			for attempt := 0; attempt < 100 && !visible(); attempt++ {
				tt.Scroll(950, 700, 0, 200)
			}
		}
		if !visible() {
			t.Fatal("actual Gallery notification trigger cannot be reached")
		}
		widgetClick(t, tt, n.String("text"))
		tt.Frame()
	}
	toasts := func(want int) int64 {
		t.Helper()
		var draft int64
		count := 0
		for id, node := range b.nodes {
			if node.Kind == "toast" {
				count++
				if node.String("accessibility-label") == "Draft saved" {
					draft = id
				}
			}
		}
		if count != want {
			t.Errorf("actual Gallery mounted %d notifications, want %d", count, want)
		}
		if b.Err() != nil {
			t.Fatal(b.Err())
		}
		return draft
	}
	toasts(0)
	show()
	first := toasts(1)
	if first == 0 {
		t.Fatal("missing actual retained draft notification")
	}
	firstIdentity := b.states[first].identity
	n, _ := b.Node(trigger)
	if n.String("text") != "Show notification" || n.Props["enabled"] != false {
		t.Errorf("visible notification must disable its singular trigger: %+v", n.Props)
	}
	// A second actual pointer activation cannot create another toast or reset it.
	widgetClick(t, tt, n.String("text"))
	if got := toasts(1); got != first {
		t.Errorf("repeated trigger replaced retained notification: %d -> %d", first, got)
	}
	widgetClick(t, tt, "Update notification")
	if got := toasts(1); got != first || !tt.HasText("Updated") || !tt.HasText("Draft remains the same retained toast") {
		t.Fatal("actual Gallery update did not preserve and update its notification")
	}
	widgetClick(t, tt, "Close")
	tt.Frame()
	toasts(0)
	show()
	second := toasts(1)
	if second == 0 || b.states[second].identity == firstIdentity || !tt.HasText("Saved") {
		t.Fatal("manual close/reopen did not create a fresh saved notification")
	}
	// No hover or child focus can pause the timer for this timing assertion.
	tt.Move(5, 5)
	tt.ClickAt(5, 5)
	tt.Advance(3999 * time.Millisecond)
	toasts(1)
	tt.Advance(time.Millisecond)
	tt.Frame()
	toasts(0)
	show()
	toasts(1)
	widgetClick(t, tt, "Update notification")
	tt.Move(5, 5)
	tt.Advance(5 * time.Second)
	toasts(1) // Keyboard focus inside the toast pauses its timer.
	tt.Key(0, ui.KeyEscape)
	tt.Frame()
	toasts(0)
	show()
	toasts(1)
	widgetClick(t, tt, "Close")
	tt.Frame()
	toasts(0)
}
