package luimygo

import (
	"encoding/json"
	"testing"

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
