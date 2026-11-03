package luimygo

import (
	"testing"

	"github.com/egoist/mygo/ui"
)

func TestPointerPolicyPreservesRetainedOverlayActivation(t *testing.T) {
	var events []Event
	b := New(Config{Dispatch: func(e Event) error { events = append(events, e); return nil }})
	apply(t, b, 1,
		create(1, "stack"), create(2, "column"), insert(1, 2, 0),
		create(3, "button"), prop(3, "text", "Underlying"), prop(3, "width", 240), prop(3, "height", 40), prop(3, "press-enabled", true), insert(2, 3, 0),
		create(4, "overlay"), prop(4, "pointer-enabled", false), prop(4, "width-viewport", 1), prop(4, "height-viewport", 1), prop(4, "data-attrs", "data-overlay-layer\x1ftrue"), insert(1, 4, 1),
		create(5, "column"), insert(4, 5, 0), create(7, "button"), prop(7, "text", "Suppressed caption"), prop(7, "width", 240), prop(7, "height", 40), prop(7, "press-enabled", true), insert(5, 7, 0),
		create(6, "button"), prop(6, "text", "Opted in"), prop(6, "pointer-enabled", true), prop(6, "press-enabled", true), insert(4, 6, 1))
	tt, bounds := widgetTesterBounds(b, 400, 240)
	click := func(id int64) {
		r := bounds(id)
		if r.W <= 0 || r.H <= 0 {
			t.Fatalf("missing committed bounds for %d: %+v", id, r)
		}
		tt.ClickAt(r.X+r.W/2, r.Y+r.H/2)
	}
	click(3)
	click(6)
	if widgetCount(events, "press", 3) != 1 || widgetCount(events, "press", 7) != 0 || widgetCount(events, "press", 6) != 1 {
		t.Fatalf("retained pointer policy did not reach native hit testing: %+v", events)
	}
	apply(t, b, 2, create(8, "popover"), prop(8, "width", 100), prop(8, "height", 50), insert(4, 8, 2),
		create(9, "button"), prop(9, "text", "Presented"), prop(9, "press-enabled", true), insert(8, 9, 0))
	tt.Frame()
	click(9)
	if widgetCount(events, "press", 9) != 1 {
		t.Fatalf("presented overlay did not opt in below disabled layer: %+v", events)
	}
}

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
