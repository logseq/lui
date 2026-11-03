package luimygo

import (
	"encoding/json"
	"fmt"
	"slices"
	"testing"

	"github.com/egoist/mygo/ui"
)

type sparseCollectionFixture struct {
	b          *Backend
	events     []Event
	generation int64
	nextID     int64
	total      int
	rows       map[int]int64
}

func newSparseCollectionFixture(t *testing.T, count int) *sparseCollectionFixture {
	t.Helper()
	f := &sparseCollectionFixture{generation: 1, nextID: 10, total: count, rows: map[int]int64{}}
	f.b = New(Config{})
	t.Cleanup(func() { f.b.Close() })
	f.b.config.Dispatch = func(e Event) error {
		f.events = append(f.events, e)
		if e.Kind == "virtual-window" && e.Generation == f.generation {
			return f.mount(int(e.First), int(e.Last), e.Pins)
		}
		return nil
	}
	ops := []Operation{create(1, "column"), prop(1, "cross", "start"), create(2, "virtual-list"), prop(2, "width", 300), prop(2, "height", 100), prop(2, "overscan", 2), prop(2, "item-extent", 20), prop(2, "virtual-total-count", count), prop(2, "virtual-generation", 1), prop(2, "virtual-indices", "[]"), insert(1, 2, 0)}
	apply(t, f.b, 1, ops...)
	if err := f.mount(0, min(count, 7), nil); err != nil {
		t.Fatal(err)
	}
	return f
}

func (f *sparseCollectionFixture) mount(first, last int, pins []int64) error {
	keep := map[int]bool{}
	for i := first; i < last && i < f.total; i++ {
		keep[i] = true
	}
	for i, id := range f.rows {
		if slices.Contains(pins, id) {
			keep[i] = true
		}
	}
	indices := make([]int, 0, len(keep))
	for i := range keep {
		indices = append(indices, i)
	}
	slices.Sort(indices)
	ops := []Operation{}
	for i, id := range f.rows {
		if !keep[i] {
			ops = append(ops, Operation{Op: "detach-subtree", ID: id})
			delete(f.rows, i)
		}
	}
	for position, index := range indices {
		id, exists := f.rows[index]
		if !exists {
			f.nextID++
			id = f.nextID
			f.rows[index] = id
			ops = append(ops, create(id, "list-item"), prop(id, "height", 20), prop(id, "text", fmt.Sprintf("Sparse row %d", index)), prop(id, "key", fmt.Sprintf("row-%d", index)), insert(2, id, position))
		} else {
			ops = append(ops, Operation{Op: "move-child", Parent: 2, Child: id, Index: position})
		}
	}
	encoded, _ := json.Marshal(indices)
	ops = append(ops, prop(2, "virtual-total-count", f.total), prop(2, "virtual-generation", f.generation), prop(2, "virtual-indices", string(encoded)))
	return f.b.ApplyBatch(Batch{Generation: f.b.generation + 1, Ops: ops})
}

func TestCollectionsSparseWindowFeedbackAndDistantScroll(t *testing.T) {
	f := newSparseCollectionFixture(t, 100000)
	tester := ui.NewTester(f.b.View, 400, 200)
	if len(layoutEvents(f.events, "virtual-window", 2)) == 0 {
		t.Fatal("sparse list never requested its real host window")
	}
	if !tester.HasText("Sparse row 0") {
		t.Fatal("initial sparse rows missing")
	}
	apply(t, f.b, f.b.generation+1, prop(2, "scroll-target", "row-99999"), prop(2, "virtual-scroll-index", 99999), prop(2, "scroll-token", 1), prop(2, "scroll-anchor", "bottom"), prop(2, "pointer-enabled", true), prop(2, "track-visible-range", true))
	for range 5 {
		tester.Frame()
	}
	if !tester.HasText("Sparse row 99999") {
		t.Fatalf("offscreen target never materialized: %v", tester.Texts())
	}
	if len(f.b.nodes) > 40 || len(f.b.states) > 40 || len(f.rows) > 20 {
		t.Fatalf("sparse target constructed whole source: nodes%d states%d rows%d", len(f.b.nodes), len(f.b.states), len(f.rows))
	}
	first, last := layoutRange(t, f.events, 2)
	if first != 99995 || last != 99999 {
		t.Fatalf("logical visible range replaced by sparse child positions: %d..%d", first, last)
	}
	layoutCompletion(t, f.events, 1, "succeeded")
}

func TestCollectionsSparseFeedbackIgnoresUserEventFlagsAndCoalesces(t *testing.T) {
	f := newSparseCollectionFixture(t, 100000)
	apply(t, f.b, f.b.generation+1, create(3, "box"), Operation{Op: "remove-child", Parent: 1, Child: 2}, insert(1, 3, 0), insert(3, 2, 0), prop(3, "inert", true))
	tester := ui.NewTester(f.b.View, 400, 200)
	requests := layoutEvents(f.events, "virtual-window", 2)
	if len(requests) == 0 {
		t.Fatal("internal maintenance depends on enabled/pointer/application event flags")
	}
	before := len(requests)
	for range 5 {
		tester.Frame()
	}
	if got := len(layoutEvents(f.events, "virtual-window", 2)); got != before {
		t.Fatalf("identical window redispatched every frame: %d -> %d", before, got)
	}
	f.generation++
	if err := f.mount(0, 7, nil); err != nil {
		t.Fatal(err)
	}
	tester.Frame()
	requests = layoutEvents(f.events, "virtual-window", 2)
	if requests[len(requests)-1].Generation != f.generation {
		t.Fatal("source generation did not invalidate window acknowledgement")
	}
}

func TestCollectionsSparseWheelConvergesAndEmptySourceClearsExtent(t *testing.T) {
	f := newSparseCollectionFixture(t, 100000)
	tester := ui.NewTester(f.b.View, 400, 200)
	tester.Scroll(100, 50, 0, 40000)
	for range 5 {
		tester.Frame()
	}
	requests := layoutEvents(f.events, "virtual-window", 2)
	if len(requests) == 0 || requests[len(requests)-1].First < 1000 {
		t.Fatalf("wheel used mounted extent instead of logical source: %+v", requests)
	}
	if len(f.b.nodes) > 40 {
		t.Fatal("scroll grew mounted representation")
	}
	f.total = 0
	f.generation++
	if err := f.mount(0, 0, nil); err != nil {
		t.Fatal(err)
	}
	tester.Frame()
	requests = layoutEvents(f.events, "virtual-window", 2)
	last := requests[len(requests)-1]
	if last.First != 0 || last.Last != 0 || len(last.Pins) != 0 {
		t.Fatalf("empty source window: %+v", last)
	}
	if len(f.b.nodes) != 2 {
		t.Fatalf("empty source retains %d nodes", len(f.b.nodes))
	}
}

func TestCollectionsSparseMissingTargetCompletesOnce(t *testing.T) {
	f := newSparseCollectionFixture(t, 100000)
	tester := ui.NewTester(f.b.View, 400, 200)
	apply(t, f.b, f.b.generation+1, prop(2, "scroll-target", "missing"), prop(2, "virtual-scroll-index", -1), prop(2, "scroll-token", 8), prop(2, "pointer-enabled", true))
	for range 5 {
		tester.Frame()
	}
	layoutCompletion(t, f.events, 8, "missing-target")
}

func TestVirtualWindowEventValidation(t *testing.T) {
	good := Event{Kind: "virtual-window", Node: 2, Generation: 9007199254740993, First: 0, Last: 10, Pins: []int64{5, 9007199254740995}}
	if err := validateEvent(good); err != nil {
		t.Fatalf("valid internal window rejected: %v", err)
	}
	for _, change := range []func(*Event){func(e *Event) { e.Generation = 0 }, func(e *Event) { e.Generation = -1 }, func(e *Event) { e.First = -1 }, func(e *Event) { e.Last = e.First - 1 }, func(e *Event) { e.Pins = []int64{0} }, func(e *Event) { e.Pins = []int64{-1} }, func(e *Event) { e.Pins = []int64{5, 5} }} {
		e := good
		change(&e)
		if err := validateEvent(e); err == nil {
			t.Fatalf("invalid window accepted: %+v", e)
		}
	}
}

func TestCollectionsSparsePinsRetainEditorCompositionAcrossDistantReorder(t *testing.T) {
	f := newSparseCollectionFixture(t, 100000)
	row := f.rows[2]
	apply(t, f.b, f.b.generation+1, create(900003, "text-field"), prop(900003, "placeholder", "sparse editor"), prop(900003, "text", "ab"), insert(row, 900003, 0))
	tester := ui.NewTester(f.b.View, 400, 200)
	if err := tester.Click("sparse editor"); err != nil {
		t.Fatal(err)
	}
	tester.Key(0, ui.KeyHome)
	tester.Key(0, ui.KeyRight)
	tester.Compose("你", 1)
	identity := f.b.states[900003].identity
	delete(f.rows, 2)
	f.rows[99999] = row
	f.generation++
	if err := f.mount(0, 7, []int64{row}); err != nil {
		t.Fatal(err)
	}
	for range 3 {
		tester.Frame()
	}
	if !tester.Focused("sparse editor") || f.b.states[900003].identity != identity {
		t.Fatal("source reorder disposed retained composition owner")
	}
	requests := layoutEvents(f.events, "virtual-window", 2)
	if len(requests) == 0 || !slices.Contains(requests[len(requests)-1].Pins, row) {
		t.Fatalf("pin did not follow wire row identity: %+v", requests)
	}
	tester.Type("你")
	changes := layoutEvents(f.events, "text-changed", 900003)
	if len(changes) == 0 || changes[len(changes)-1].Text != "a你b" {
		t.Fatalf("reorder lost caret/composition: %+v", changes)
	}
	if len(f.b.nodes) > 40 {
		t.Fatal("pin retained intervening rows")
	}
}

func TestCollectionsSparseExtensionRootsNeedNoStandardRowProperties(t *testing.T) {
	f := newSparseCollectionFixture(t, 100000)
	f.b.config.Extensions = map[string]Extension{"sparse-row": {Fingerprint: "v1", Render: func(c *ui.Context, n Node, children func(), emit func(Event)) {
		ui.Button(c, "Sparse extension row").Height(20).OnClick(func() { emit(Event{Kind: "extension-event", Identifier: "sparse-row", Name: "pressed"}) })
	}}}
	row := f.rows[2]
	apply(t, f.b, f.b.generation+1, Operation{Op: "detach-subtree", ID: row}, Operation{Op: "create-extension", ID: row, Identifier: "sparse-row", Fingerprint: "v1"}, insert(2, row, 2))
	tester := ui.NewTester(f.b.View, 400, 200)
	if err := tester.Click("Sparse extension row"); err != nil {
		t.Fatal(err)
	}
	if len(layoutEvents(f.events, "extension-event", row)) != 1 {
		t.Fatal("sparse extension root did not receive native action")
	}
	f.b.states[2].collection.list.ScrollToEnd()
	for range 5 {
		tester.Frame()
	}
	if len(f.b.nodes) > 40 {
		t.Fatal("extension root required eager source representation")
	}
}
