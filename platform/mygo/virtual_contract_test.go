package luimygo

import "testing"

func TestVirtualSourceContractIsAtomic(t *testing.T) {
	for _, tc := range []struct {
		name string
		ops  []Operation
	}{
		{"missing count", []Operation{{Op: "remove-prop", ID: 1, Property: "virtual-total-count"}}},
		{"missing generation", []Operation{{Op: "remove-prop", ID: 1, Property: "virtual-generation"}}},
		{"missing indices", []Operation{{Op: "remove-prop", ID: 1, Property: "virtual-indices"}}},
		{"wrong child count", []Operation{prop(1, "virtual-indices", "[0]")}},
		{"out of range", []Operation{prop(1, "virtual-indices", "[0,100000]")}},
		{"duplicate index", []Operation{prop(1, "virtual-indices", "[0,0]")}},
		{"unordered indices", []Operation{prop(1, "virtual-indices", "[99999,0]")}},
		{"noncanonical spacing", []Operation{prop(1, "virtual-indices", "[0, 99999]")}},
		{"fractional index", []Operation{prop(1, "virtual-indices", "[0,99999.0]")}},
		{"negative index", []Operation{prop(1, "virtual-indices", "[-1,99999]")}},
		{"null indices", []Operation{prop(1, "virtual-indices", "null")}},
		{"zero generation", []Operation{prop(1, "virtual-generation", 0)}},
		{"negative count", []Operation{prop(1, "virtual-total-count", -1)}},
		{"target out of range", []Operation{prop(1, "virtual-scroll-index", 100000)}},
		{"invalid missing sentinel", []Operation{prop(1, "virtual-scroll-index", -2)}},
		{"unmapped inserted child", []Operation{create(4, "list-item"), prop(4, "text", "unmapped"), insert(1, 4, 2)}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			b := New(Config{})
			defer b.Close()
			apply(t, b, 1, create(1, "virtual-list"), create(2, "list-item"), prop(2, "text", "first"),
				create(3, "list-item"), prop(3, "text", "last"), insert(1, 2, 0), insert(1, 3, 1),
				prop(1, "virtual-total-count", 100000), prop(1, "virtual-generation", 1),
				prop(1, "virtual-indices", "[0,99999]"), prop(1, "virtual-scroll-index", 99999))
			ops := append([]Operation{prop(2, "text", "must roll back")}, tc.ops...)
			if err := b.ApplyBatch(Batch{Generation: 2, Ops: ops}); err == nil {
				t.Fatal("accepted an inconsistent sparse tree")
			}
			if b.Generation() != 1 {
				t.Fatal("invalid sparse metadata advanced generation")
			}
			if n, _ := b.Node(2); n.String("text") != "first" {
				t.Fatal("invalid sparse metadata left a preceding mutation committed")
			}
			if _, exists := b.Node(4); exists {
				t.Fatal("invalid sparse metadata left a newly inserted node")
			}
		})
	}
}

func TestVirtualSourceEmptyAndEagerTransitions(t *testing.T) {
	b := New(Config{})
	defer b.Close()
	apply(t, b, 1, create(1, "virtual-list"), prop(1, "virtual-total-count", 0),
		prop(1, "virtual-generation", 1), prop(1, "virtual-indices", "[]"), prop(1, "virtual-scroll-index", -1))
	apply(t, b, 2, prop(1, "virtual-total-count", 100000), prop(1, "virtual-generation", 2),
		prop(1, "virtual-indices", "[99999]"), create(2, "list-item"), prop(2, "text", "last"), insert(1, 2, 0))
	apply(t, b, 3, Operation{Op: "remove-prop", ID: 1, Property: "virtual-total-count"},
		Operation{Op: "remove-prop", ID: 1, Property: "virtual-generation"},
		Operation{Op: "remove-prop", ID: 1, Property: "virtual-indices"},
		Operation{Op: "remove-prop", ID: 1, Property: "virtual-scroll-index"})
	if n, _ := b.Node(1); len(n.Children) != 1 || b.Generation() != 3 {
		t.Fatal("returning to the eager contract lost retained children")
	}
}
