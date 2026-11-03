package luimygo

import (
	"encoding/json"
	"slices"
	"testing"

	"github.com/egoist/mygo/ui"
)

// The source answers actual host window requests without constructing rows
// outside that window. Empty rows must not make those requests grow forever.
type zeroExtentCollectionFixture struct {
	*sparseCollectionFixture
	extension bool
	height    int
}

func newZeroExtentCollectionFixture(t *testing.T, extension bool, height int) *zeroExtentCollectionFixture {
	t.Helper()
	f := &zeroExtentCollectionFixture{
		sparseCollectionFixture: &sparseCollectionFixture{
			generation: 1, nextID: 10, total: 2000, rows: map[int]int64{},
		},
		extension: extension, height: height,
	}
	f.b = New(Config{Extensions: map[string]Extension{
		"empty-row": {Fingerprint: "v1", Render: func(c *ui.Context, _ Node, _ func(), _ func(Event)) {
			ui.Column(c)
		}},
	}})
	t.Cleanup(func() { f.b.Close() })
	f.b.config.Dispatch = func(e Event) error {
		f.events = append(f.events, e)
		if e.Kind == "virtual-window" && e.Generation == f.generation {
			return f.mount(int(e.First), int(e.Last), e.Pins)
		}
		return nil
	}
	apply(t, f.b, 1, create(1, "column"), prop(1, "cross", "start"),
		create(2, "virtual-list"), prop(2, "width", 300), prop(2, "height", 100),
		prop(2, "overscan", 2), prop(2, "item-extent", 20),
		prop(2, "virtual-total-count", f.total), prop(2, "virtual-generation", 1),
		prop(2, "virtual-indices", "[]"), insert(1, 2, 0))
	if err := f.mount(0, 7, nil); err != nil {
		t.Fatal(err)
	}
	return f
}

func (f *zeroExtentCollectionFixture) mount(first, last int, pins []int64) error {
	keep := map[int]bool{}
	for index := first; index < last && index < f.total; index++ {
		keep[index] = true
	}
	for index, id := range f.rows {
		if slices.Contains(pins, id) {
			keep[index] = true
		}
	}
	indices := make([]int, 0, len(keep))
	for index := range keep {
		indices = append(indices, index)
	}
	slices.Sort(indices)
	var ops []Operation
	for index, id := range f.rows {
		if !keep[index] {
			ops = append(ops, Operation{Op: "detach-subtree", ID: id})
			delete(f.rows, index)
		}
	}
	for position, index := range indices {
		id, exists := f.rows[index]
		if !exists {
			f.nextID++
			id = f.nextID
			f.rows[index] = id
			if f.extension {
				ops = append(ops, Operation{Op: "create-extension", ID: id, Identifier: "empty-row", Fingerprint: "v1"})
			} else {
				ops = append(ops, create(id, "column"))
				if f.height > 0 {
					ops = append(ops, prop(id, "height", f.height))
				}
			}
			ops = append(ops, insert(2, id, position))
		} else {
			ops = append(ops, Operation{Op: "move-child", Parent: 2, Child: id, Index: position})
		}
	}
	encoded, _ := json.Marshal(indices)
	ops = append(ops, prop(2, "virtual-total-count", f.total),
		prop(2, "virtual-generation", f.generation), prop(2, "virtual-indices", string(encoded)))
	return f.b.ApplyBatch(Batch{Generation: f.b.generation + 1, Ops: ops})
}

func TestCollectionsSparseZeroExtentRowsRemainBounded(t *testing.T) {
	for _, tc := range []struct {
		name      string
		extension bool
		initial   int
	}{
		{name: "empty standard columns"},
		{name: "empty extension roots", extension: true},
		{name: "rows become empty", initial: 20},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := newZeroExtentCollectionFixture(t, tc.extension, tc.initial)
			tester := ui.NewTester(f.b.View, 400, 200)
			if tc.initial > 0 {
				f.height = 0
				var ops []Operation
				for _, id := range f.rows {
					ops = append(ops, Operation{Op: "remove-prop", ID: id, Property: "height"})
				}
				apply(t, f.b, f.b.generation+1, ops...)
			}
			for frame := range 128 {
				tester.Frame()
				// Even a one-pixel minimum slot would need only 100 visible
				// rows here; allow ample headroom for native overscan/layout.
				if len(f.rows) > 256 || len(f.b.nodes) > 258 || len(f.b.states) > 258 {
					requests := layoutEvents(f.events, "virtual-window", 2)
					t.Fatalf("zero-height rows expanded beyond the viewport at frame %d: rows=%d nodes=%d states=%d last request=%+v",
						frame, len(f.rows), len(f.b.nodes), len(f.b.states), requests[len(requests)-1])
				}
			}
			if len(layoutEvents(f.events, "virtual-window", 2)) == 0 {
				t.Fatal("real layout never requested source rows")
			}
		})
	}
}

func TestCollectionsSparsePositiveRowsKeepTheirMeasuredExtent(t *testing.T) {
	f := newZeroExtentCollectionFixture(t, false, 4)
	tester := ui.NewTester(f.b.View, 400, 200)
	for range 12 {
		tester.Frame()
	}
	requests := layoutEvents(f.events, "virtual-window", 2)
	if len(requests) == 0 {
		t.Fatal("real layout never requested source rows")
	}
	last := requests[len(requests)-1]
	if last.First != 0 || last.Last < 25 || last.Last > 32 {
		t.Fatalf("positive measured rows lost their compact geometry: %+v", last)
	}
}
