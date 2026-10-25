package luimygo

import (
	"testing"

	"github.com/egoist/mygo/ui"
)

func TestSpacerPreservesNativeActivation(t *testing.T) {
	var events []Event
	b := New(Config{Dispatch: func(e Event) error { events = append(events, e); return nil }})
	apply(t, b, 1,
		create(1, "stack"), create(2, "column"), prop(2, "padding", 12), insert(1, 2, 0),
		create(3, "button"), prop(3, "text", "Underlying"), prop(3, "press-enabled", true), insert(2, 3, 0),
		create(4, "spacer"), prop(4, "width-viewport", 1), prop(4, "height-viewport", 1), insert(1, 4, 1),
		create(6, "button"), prop(6, "text", "Overlay action"), prop(6, "margin-top", 80), prop(6, "press-enabled", true), prop(6, "pointer-enabled", true), insert(1, 6, 2))
	var underlying, action ui.Rect
	var targets []int64
	prevent := false
	tt := ui.NewTester(func(c *ui.Context) {
		b.View(c)
		c.CaptureInput(func(ev ui.InputEvent, target ui.InputTarget) bool {
			if ev.Kind != ui.InputClick {
				return false
			}
			n, ok := b.InputNode(target)
			if !ok || !n.Current() {
				t.Fatal("click did not resolve a current retained node")
			}
			targets = append(targets, n.Node.ID)
			return prevent
		})
		c.AfterFrame(func() {
			underlying, _ = b.Bounds(c, 3)
			action, _ = b.Bounds(c, 6)
		})
	}, 400, 240)
	tt.Frame()
	click := func(r ui.Rect) {
		if r.W <= 0 || r.H <= 0 {
			t.Fatalf("missing committed control bounds: %+v", r)
		}
		tt.ClickAt(r.X+r.W/2, r.Y+r.H/2)
	}
	click(underlying)
	if widgetCount(events, "press", 3) != 1 {
		t.Fatalf("transparent cover swallowed underlying press: %+v", events)
	}
	click(action)
	if widgetCount(events, "press", 6) != 1 {
		t.Fatalf("explicit pointer-enabled child did not activate: %+v", events)
	}
	if len(targets) != 2 || targets[0] != 3 || targets[1] != 6 {
		t.Fatalf("capture resolved incorrect retained owners: %v", targets)
	}
	prevent = true
	click(underlying)
	if widgetCount(events, "press", 3) != 1 {
		t.Fatal("default-prevented click still activated underlying button")
	}
}
