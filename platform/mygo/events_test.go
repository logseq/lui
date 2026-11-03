package luimygo

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/egoist/mygo/ui"
)

func eventRecords(events []Event, kind string, node int64) []map[string]any {
	var records []map[string]any
	for _, event := range events {
		if event.Kind == kind && event.Node == node {
			encoded, _ := json.Marshal(event)
			var record map[string]any
			_ = json.Unmarshal(encoded, &record)
			records = append(records, record)
		}
	}
	return records
}

func TestEventsTimedGesturesAndCancellation(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "list-item"), prop(3, "text", "Gestures"), prop(3, "press-enabled", true), prop(3, "long-press-enabled", true), prop(3, "double-press-enabled", true), insert(2, 3, 0))
	tester := ui.NewTester(b.View, 360, 240)
	r, _ := tester.Find("Gestures")
	x, y := r.X+r.W/2, r.Y+r.H/2
	tester.Press(x, y)
	tester.Advance(349 * time.Millisecond)
	if len(events) != 0 {
		t.Fatal("long press fired early", events)
	}
	tester.Advance(time.Millisecond)
	if len(eventRecords(events, "long-press", 3)) != 1 {
		t.Fatal("missing long press", events)
	}
	tester.Advance(time.Second)
	tester.Release(x, y)
	if len(eventRecords(events, "long-press", 3)) != 1 || len(eventRecords(events, "press", 3)) != 0 {
		t.Fatal("held gesture repeated or release activated", events)
	}
	events = nil
	tester.Advance(time.Second)
	_ = tester.Click("Gestures")
	tester.Advance(50 * time.Millisecond)
	_ = tester.Click("Gestures")
	if len(eventRecords(events, "double-press", 3)) != 1 {
		t.Fatal("double gesture missing", events)
	}
	events = nil
	tester.Advance(time.Second)
	tester.Press(x, y)
	tester.Release(350, 230)
	tester.Advance(time.Second)
	if len(eventRecords(events, "long-press", 3)) != 0 {
		t.Fatal("cancelled gesture fired", events)
	}
	tester.Press(x, y)
	apply(t, b, 3, Operation{Op: "detach-subtree", ID: 3})
	tester.Frame()
	tester.Advance(time.Second)
	if len(eventRecords(events, "long-press", 3)) != 0 {
		t.Fatal("detached gesture fired", events)
	}
}

func TestEventsPointerPayloadAndHover(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "button"), prop(3, "text", "Pointer target"), prop(3, "pointer-enabled", true), prop(3, "press-enabled", true), insert(2, 3, 0))
	tester := ui.NewTester(b.View, 360, 240)
	r, ok := tester.Find("Pointer target")
	if !ok {
		t.Fatal(tester.Texts())
	}
	x, y := r.X+r.W/2, r.Y+r.H/2
	tester.Move(350, 230)
	tester.Move(x, y)
	tester.Press(x, y)
	tester.Release(x, y)
	tester.Move(350, 230)
	for _, kind := range []string{"pointer-enter", "pointer-down", "pointer-up", "press-detail", "pointer-leave"} {
		records := eventRecords(events, kind, 3)
		if len(records) != 1 {
			t.Errorf("%s delivered %d times: %+v", kind, len(records), events)
			continue
		}
		if kind == "pointer-enter" || kind == "pointer-leave" {
			continue
		}
		if records[0]["x"] != float64(x) || records[0]["y"] != float64(y) {
			t.Errorf("%s lost window coordinates: %+v", kind, records[0])
		}
		if v, exists := records[0]["button"]; exists && v != float64(0) {
			t.Errorf("primary button convention: %+v", records[0])
		}
	}
	if len(eventRecords(events, "press", 3)) != 1 {
		t.Error("pointer subscription changed ordinary press delivery")
	}
	events = nil
	apply(t, b, 3, prop(3, "pointer-enabled", false))
	tester.Frame()
	_ = tester.Click("Pointer target")
	if len(eventRecords(events, "pointer-down", 3)) != 0 || len(eventRecords(events, "press-detail", 3)) != 0 {
		t.Fatal("unsubscribed pointer event delivered")
	}
}

func TestEventsCapturedPointerCancel(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "row"), prop(3, "pointer-enabled", true), prop(3, "pointer-capture", true), prop(3, "press-enabled", true), insert(2, 3, 0), create(4, "text"), prop(4, "text", "Resize grip"), insert(3, 4, 0))
	tester := ui.NewTester(b.View, 360, 240)
	r, ok := tester.Find("Resize grip")
	if !ok {
		t.Fatal(tester.Texts())
	}
	x, y := r.X+r.W/2, r.Y+r.H/2
	tester.Press(x, y)
	tester.Move(350, 230)
	tester.Release(350, 230)
	if len(eventRecords(events, "pointer-down", 3)) != 1 || len(eventRecords(events, "pointer-move", 3)) == 0 || len(eventRecords(events, "pointer-up", 3)) != 1 || len(eventRecords(events, "pointer-cancel", 3)) != 0 || len(eventRecords(events, "press", 3)) != 0 || len(eventRecords(events, "press-detail", 3)) != 0 {
		t.Fatalf("normal captured release: %+v", events)
	}
	events = nil
	tester.Press(x, y)
	tester.Key(0, ui.KeyEscape)
	tester.Release(350, 230)
	if len(eventRecords(events, "pointer-down", 3)) != 1 || len(eventRecords(events, "pointer-cancel", 3)) != 1 || len(eventRecords(events, "pointer-up", 3)) != 0 || len(eventRecords(events, "press", 3)) != 0 {
		t.Fatalf("canceled capture became release or press: %+v", events)
	}
	for _, ending := range []string{"blur", "disabled", "removed"} {
		t.Run(ending, func(t *testing.T) {
			var events []Event
			b := mounted(t, func(e Event) error { events = append(events, e); return nil })
			apply(t, b, 2, create(3, "box"), prop(3, "pointer-enabled", true), prop(3, "pointer-capture", true), insert(2, 3, 0), create(4, "text"), prop(4, "text", "Resize grip"), insert(3, 4, 0))
			tt := ui.NewTester(b.View, 360, 240)
			r, ok := tt.Find("Resize grip")
			if !ok {
				t.Fatal(tt.Texts())
			}
			tt.Press(r.X+r.W/2, r.Y+r.H/2)
			switch ending {
			case "blur":
				tt.SetFocused(false)
			case "disabled":
				apply(t, b, 3, prop(3, "inert", true))
				tt.Frame()
			case "removed":
				apply(t, b, 3, Operation{Op: "detach-subtree", ID: 3})
				tt.Frame()
			}
			tt.Release(350, 230)
			if len(eventRecords(events, "pointer-cancel", 3)) != 1 || len(eventRecords(events, "pointer-up", 3)) != 0 || len(eventRecords(events, "press", 3)) != 0 {
				t.Fatalf("capture lifetime: %+v", events)
			}
		})
	}
}

func TestEventsNavigationSubscriptionAndDisabled(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "text-field"), prop(3, "placeholder", "Navigate"), prop(3, "navigate-enabled", true), insert(2, 3, 0))
	tester := ui.NewTester(b.View, 360, 240)
	_ = tester.Click("Navigate")
	tester.Key(0, ui.KeyUp)
	tester.Key(0, ui.KeyDown)
	if len(eventRecords(events, "navigate-previous", 3)) != 1 || len(eventRecords(events, "navigate-next", 3)) != 1 {
		t.Fatalf("navigation events missing: %+v", events)
	}
	events = nil
	apply(t, b, 3, prop(3, "navigate-enabled", false))
	tester.Frame()
	tester.Key(0, ui.KeyUp)
	if len(events) != 0 {
		t.Fatal(events)
	}
	apply(t, b, 4, prop(3, "navigate-enabled", true), prop(3, "enabled", false))
	tester.Frame()
	tester.Key(0, ui.KeyDown)
	if len(events) != 0 {
		t.Fatal("disabled editor navigated", events)
	}
}
