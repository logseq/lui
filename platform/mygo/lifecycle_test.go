package luimygo

import (
	"github.com/egoist/mygo/ui"
	"testing"
)

func TestLifecycleAppearanceDisabledAndNewIncarnation(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "button"), prop(3, "text", "Visible disabled"), prop(3, "enabled", false), prop(3, "appear-enabled", true), insert(2, 3, 0))
	tester := ui.NewTester(b.View, 360, 240)
	if len(eventRecords(events, "appear", 3)) != 1 {
		t.Fatalf("disabled visible node must appear: %+v", events)
	}
	tester.Frame()
	apply(t, b, 3, Operation{Op: "move-child", Parent: 2, Child: 3, Index: 0})
	tester.Frame()
	if len(eventRecords(events, "appear", 3)) != 1 {
		t.Fatal("rebuild/move repeated appearance")
	}
	apply(t, b, 4, Operation{Op: "detach-subtree", ID: 3}, create(3, "button"), prop(3, "text", "New incarnation"), prop(3, "appear-enabled", true), insert(2, 3, 0))
	tester.Frame()
	if len(eventRecords(events, "appear", 3)) != 2 {
		t.Fatal("new incarnation did not appear", events)
	}
}

func TestLifecycleQueuedEventsCannotReachReplacementNode(t *testing.T) {
	var events []Event
	var b *Backend
	b = mounted(t, func(e Event) error {
		events = append(events, e)
		if e.Kind == "appear" && e.Node == 3 {
			apply(t, b, b.Generation()+1, Operation{Op: "detach-subtree", ID: 4}, create(4, "text"), prop(4, "text", "Replacement"), prop(4, "appear-enabled", true), insert(2, 4, 1))
		}
		return nil
	})
	apply(t, b, 2, create(3, "text"), prop(3, "text", "First"), prop(3, "appear-enabled", true), insert(2, 3, 0), create(4, "text"), prop(4, "text", "Old"), prop(4, "appear-enabled", true), insert(2, 4, 1))
	_ = ui.NewTester(b.View, 360, 240)
	if len(eventRecords(events, "appear", 4)) != 1 {
		t.Fatalf("stale old-frame appearance reached replacement: %+v", events)
	}
}

func TestLifecycleRejectedBatchPreservesFocusedEditor(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "text-field"), prop(3, "text", "kept"), prop(3, "placeholder", "Retained"), insert(2, 3, 0))
	tester := ui.NewTester(b.View, 360, 240)
	_ = tester.Click("Retained")
	if err := b.ApplyBatch(Batch{Generation: 3, Ops: []Operation{{Op: "detach-subtree", ID: 3}, create(3, "text-field"), prop(3, "text", "wrong"), prop(3, "unknown", true)}}); err == nil {
		t.Fatal("invalid batch accepted")
	}
	tester.Frame()
	if !tester.Focused("Retained") {
		t.Fatal("rejected batch replaced toolkit state", tester.Texts())
	}
	tester.Key(0, ui.KeyEnd)
	tester.Type("!")
	if len(events) != 1 || events[0].Text != "kept!" {
		t.Fatal("rejected batch lost the editor value", events)
	}
}
