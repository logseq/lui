package luimygo

import (
	"reflect"
	"testing"

	"github.com/egoist/mygo/ui"
)

func backendMemoryTree(t testing.TB, count int) *Backend {
	t.Helper()
	ops := make([]Operation, 0, 1+count*4)
	ops = append(ops, create(1, "virtual-list"))
	for i := range count {
		id := int64(i + 2)
		ops = append(ops, create(id, "list-item"), prop(id, "text", "Retained row"), prop(id, "height", 28), insert(1, id, i))
	}
	b := New(Config{})
	if err := b.ApplyBatch(Batch{Generation: 1, Ops: ops}); err != nil {
		t.Fatal(err)
	}
	return b
}

func TestBackendMemoryMixedDeletionRollback(t *testing.T) {
	for _, scenario := range []struct {
		name string
		ops  []Operation
	}{
		{"delete then fail", []Operation{{Op: "detach-subtree", ID: 2}, prop(999, "text", "invalid")}},
		{"mutate then delete then fail", []Operation{prop(3, "text", "Changed"), {Op: "detach-subtree", ID: 2}, prop(999, "text", "invalid")}},
		{"delete recreate mutate then fail", []Operation{{Op: "detach-subtree", ID: 2}, create(2, "column"), prop(2, "gap", 99), insert(1, 2, 0), prop(999, "text", "invalid")}},
		{"mutate delete recreate final contract failure", []Operation{prop(3, "text", "Changed"), {Op: "detach-subtree", ID: 2}, create(2, "button"), insert(1, 2, 0)}},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			b := mounted(t, nil)
			apply(t, b, 2, create(3, "text"), prop(3, "text", "Original"), insert(2, 3, 0))
			defer b.Close()
			before := make(map[int64]Node)
			for _, id := range []int64{1, 2, 3} {
				before[id], _ = b.Node(id)
			}
			if err := b.ApplyBatch(Batch{Generation: 3, Ops: scenario.ops}); err == nil {
				t.Fatal("invalid transaction committed")
			}
			if b.Generation() != 2 {
				t.Fatal("failed transaction changed generation")
			}
			for id, want := range before {
				got, ok := b.Node(id)
				if !ok || !reflect.DeepEqual(got, want) {
					t.Fatalf("rollback changed node %d: got%+v want%+v", id, got, want)
				}
			}
			apply(t, b, 3, prop(3, "text", "Accepted"))
			got, _ := b.Node(3)
			if got.String("text") != "Accepted" {
				t.Fatal("rollback left the original property map unusable")
			}
		})
	}
}

func TestBackendMemoryMixedDeletionStartsNewIncarnation(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	defer b.Close()
	apply(t, b, 2, create(3, "button"), prop(3, "text", "Original"), prop(3, "press-enabled", true), prop(3, "appear-enabled", true), insert(2, 3, 0))
	tt := ui.NewTester(b.View, 320, 180)
	original := b.states[3].identity
	apply(t, b, 3, prop(3, "text", "Temporary"), Operation{Op: "detach-subtree", ID: 2}, create(2, "column"), insert(1, 2, 0), create(3, "button"), prop(3, "text", "Replacement"), prop(3, "press-enabled", true), prop(3, "appear-enabled", true), insert(2, 3, 0))
	b.emit(Event{Kind: "press", Node: 3, incarnation: original})
	tt.Frame()
	if b.states[3].identity == original {
		t.Fatal("replacement retained the removed node incarnation")
	}
	if err := tt.Click("Replacement"); err != nil {
		t.Fatal(err)
	}
	if len(eventRecords(events, "appear", 3)) != 2 || len(eventRecords(events, "press", 3)) != 1 {
		t.Fatalf("retirement repeated or misdirected an event: %+v", events)
	}
}

func TestBackendMemoryMixedDeletionCancelsOnlyCommittedService(t *testing.T) {
	service := &widgetFileService{calls: make(chan widgetFileCall, 4)}
	var events []Event
	b := widgetFileBackend(t, service, &events)
	defer b.Close()
	apply(t, b, 2, create(3, "file-picker"), prop(3, "request", "original"), insert(2, 3, 0))
	tt := ui.NewTester(b.View, 320, 180)
	old := widgetFileNext(t, tt, service)
	replacement := []Operation{prop(3, "request", "temporary"), {Op: "detach-subtree", ID: 3}, create(3, "file-picker"), prop(3, "request", "replacement"), insert(2, 3, 0)}
	rejected := append(append([]Operation{}, replacement...), prop(999, "text", "invalid"))
	if err := b.ApplyBatch(Batch{Generation: 3, Ops: rejected}); err == nil {
		t.Fatal("invalid retirement committed")
	}
	original, _ := b.Node(3)
	if old.ctx.Err() != nil || original.String("request") != "original" {
		t.Fatal("rollback cancelled or mutated the live service")
	}
	apply(t, b, 3, replacement...)
	if old.ctx.Err() == nil {
		t.Fatal("committed retirement did not cancel before another frame")
	}
	tt.Frame()
	next := widgetFileNext(t, tt, service)
	old.reply <- widgetFileReply{paths: []string{"/stale/result"}}
	next.reply <- widgetFileReply{}
	widgetFileWait(t, tt, func() bool { return widgetCount(events, "dismiss", 3) == 1 })
	if widgetCount(events, "picked", 3) != 0 {
		t.Fatal("disposed service result reached the replacement")
	}
}
