package luimygo

import (
	"os"
	"testing"

	"github.com/egoist/mygo/ui"
)

// The eager library is intentionally a valid RED baseline: it loads normally
// but materializes every logical row instead of the requested host window.
func TestOCamlComponentsVirtualRowsStayBounded(t *testing.T) {
	path := os.Getenv("LUI_MYGO_COMPONENTS_LIBRARY")
	if path == "" {
		t.Skip("run against the real Components library")
	}
	b := New(Config{})
	defer b.Close()
	runtime, err := OpenRuntime(path, b)
	if err != nil {
		t.Fatal(err)
	}
	defer runtime.Close()
	tester := ui.NewTester(b.View, 1100, 820)
	initialNodes := len(b.nodes)
	t.Logf("idle nodes=%d states=%d", len(b.nodes), len(b.states))
	var load int64
	for id, n := range b.nodes {
		if n.String("text") == "Load 100k" {
			load = id
			break
		}
	}
	if load == 0 {
		t.Fatal("Gallery100k control missing")
	}
	if err := runtime.Dispatch(Event{Kind: "press", Node: load}); err != nil {
		t.Fatal(err)
	}
	tester.Frame()
	if len(b.nodes) > 2000 {
		t.Fatalf("100k business data eagerly materialized %d LUI nodes", len(b.nodes))
	}
	var list int64
	for id, n := range b.nodes {
		if n.Kind == "virtual-list" {
			if total, ok := integer(n.Props["virtual-total-count"]); ok && total == 100000 {
				list = id
				break
			}
		}
	}
	if list == 0 {
		t.Fatal("Gallery did not publish bounded source metadata")
	}
	s := b.states[list]
	if s == nil {
		t.Fatal("Gallery virtual viewport was not mounted")
	}
	t.Logf("loaded nodes=%d states=%d roots=%d", len(b.nodes), len(b.states), len(b.nodes[list].Children))
	s.collection.list.ScrollToEnd()
	for range 5 {
		tester.Frame()
	}
	if len(b.nodes) > 2000 || len(b.states) > 2000 {
		t.Fatalf("bottom jump grew nodes/states: %d/%d", len(b.nodes), len(b.states))
	}
	n := b.nodes[list]
	if len(n.Children) > 100 {
		t.Fatalf("bottom request retained %d row roots", len(n.Children))
	}
	first, last := s.collection.list.Visible()
	if first < 99900 || last != 99999 {
		t.Fatalf("logical bottom extent: %d..%d", first, last)
	}
	if err := runtime.Resync(); err != nil {
		t.Fatal(err)
	}
	for range 3 {
		tester.Frame()
	}
	if len(b.nodes) > 2000 {
		t.Fatal("snapshot eagerly restored all business rows")
	}
	t.Logf("bottom nodes=%d states=%d roots=%d range=%d..%d", len(b.nodes), len(b.states), len(b.nodes[list].Children), first, last)
	for cycle := 0; cycle < 2; cycle++ {
		var clear int64
		for id, n := range b.nodes {
			if n.String("text") == "Clear" {
				clear = id
				break
			}
		}
		if clear == 0 {
			t.Fatal("Gallery Clear control missing")
		}
		if err := runtime.Dispatch(Event{Kind: "press", Node: clear}); err != nil {
			t.Fatal(err)
		}
		for range 3 {
			tester.Frame()
		}
		if len(b.nodes) != initialNodes {
			t.Fatalf("Clear retained row graph: idle%d afterClear%d", initialNodes, len(b.nodes))
		}
		t.Logf("clear cycle%d nodes=%d states=%d", cycle, len(b.nodes), len(b.states))
		if cycle == 0 {
			if err := runtime.Dispatch(Event{Kind: "press", Node: load}); err != nil {
				t.Fatal(err)
			}
			for range 3 {
				tester.Frame()
			}
			if len(b.nodes) > 2000 || len(b.states) > 2000 {
				t.Fatal("repeated load grew mounted representation")
			}
			t.Logf("reload nodes=%d states=%d roots=%d", len(b.nodes), len(b.states), len(b.nodes[list].Children))
		}
	}
	if b.Err() != nil {
		t.Fatal(b.Err())
	}

}
