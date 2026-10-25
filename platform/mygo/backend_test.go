package luimygo

import (
	"encoding/json"
	"fmt"
	"math"
	"reflect"
	"strings"
	"testing"

	"github.com/egoist/mygo/ui"
)

func apply(t *testing.T, b *Backend, generation int64, ops ...Operation) {
	t.Helper()
	if err := b.ApplyBatch(Batch{Generation: generation, Ops: ops}); err != nil {
		t.Fatal(err)
	}
}
func create(id int64, kind string) Operation { return Operation{Op: "create-node", ID: id, Kind: kind} }
func prop(id int64, name string, value any) Operation {
	return Operation{Op: "set-prop", ID: id, Property: name, Value: value}
}
func insert(parent, child int64, index int) Operation {
	return Operation{Op: "insert-child", Parent: parent, Child: child, Index: index}
}
func mounted(t *testing.T, dispatch func(Event) error) *Backend {
	t.Helper()
	b := New(Config{Dispatch: dispatch})
	apply(t, b, 1, create(1, "root"), create(2, "column"), insert(1, 2, 0), prop(2, "gap", 12), prop(2, "padding", 12))
	return b
}
func TestWireAndTreeLifecycle(t *testing.T) {
	b := New(Config{})
	err := b.ApplyJSON([]byte(`{"generation":1,"ops":[{"op":"create-node","id":9007199254740993,"kind":"column"},{"op":"create-node","id":2,"kind":"text"},{"op":"set-prop","id":2,"property":"text","value":"你好 👋\\\""},{"op":"insert-child","parent":9007199254740993,"child":2,"index":0}]}`), false)
	if err != nil {
		t.Fatal(err)
	}
	n, ok := b.Node(9007199254740993)
	if !ok || !reflect.DeepEqual(n.Children, []int64{2}) {
		t.Fatalf("tree: %+v", n)
	}
	// Public snapshots cannot mutate the retained tree.
	n.Children[0] = 99
	n.Props["text"] = "bad"
	n, _ = b.Node(9007199254740993)
	if n.Children[0] != 2 {
		t.Fatal("mutable snapshot")
	}
	apply(t, b, 2, create(3, "text"), prop(3, "text", "second"), insert(n.ID, 3, 1), Operation{Op: "move-child", Parent: n.ID, Child: 3, Index: 0})
	n, _ = b.Node(n.ID)
	if !reflect.DeepEqual(n.Children, []int64{3, 2}) {
		t.Fatal(n.Children)
	}
	apply(t, b, 3, Operation{Op: "remove-child", Parent: n.ID, Child: 2}, Operation{Op: "drop-node", ID: 2}, Operation{Op: "remove-prop", ID: 3, Property: "text"})
	if _, ok = b.Node(2); ok {
		t.Fatal("node survived drop")
	}
	apply(t, b, 4, Operation{Op: "detach-subtree", ID: n.ID})
	if len(b.Roots()) != 0 {
		t.Fatal(b.Roots())
	}
	if _, ok = b.Node(3); ok {
		t.Fatal("descendant survived detach")
	}
}
func TestRejectBatchAtomically(t *testing.T) {
	cases := map[string][]Operation{
		"duplicate":           {create(2, "text")},
		"unknown kind":        {create(3, "invented")},
		"unknown node":        {prop(99, "text", "x")},
		"unknown property":    {prop(2, "typo", true)},
		"wrong scalar":        {prop(2, "gap", "wide")},
		"null":                {prop(2, "gap", nil)},
		"object":              {prop(2, "gap", map[string]any{"x": 1})},
		"negative index":      {create(3, "text"), insert(2, 3, -1)},
		"large index":         {create(3, "text"), insert(2, 3, 9)},
		"attached child":      {insert(1, 2, 0)},
		"self cycle":          {insert(2, 2, 0)},
		"ancestor cycle":      {insert(2, 1, 0)},
		"wrong parent remove": {{Op: "remove-child", Parent: 2, Child: 1}},
		"wrong parent move":   {{Op: "move-child", Parent: 2, Child: 1, Index: 0}},
		"attached drop":       {{Op: "drop-node", ID: 2}},
		"missing detach":      {{Op: "detach-subtree", ID: 99}},
		"unknown op":          {{Op: "teleport", ID: 2}},
		"leaf child":          {create(3, "slider"), create(4, "text"), insert(3, 4, 0)},
	}
	for name, ops := range cases {
		t.Run(name, func(t *testing.T) {
			b := mounted(t, nil)
			before, _ := b.Node(2)
			ops = append([]Operation{prop(2, "gap", 100)}, ops...)
			if err := b.ApplyBatch(Batch{Generation: 2, Ops: ops}); err == nil {
				t.Fatal("accepted invalid batch")
			}
			after, _ := b.Node(2)
			if b.Generation() != 1 || !reflect.DeepEqual(before, after) {
				t.Fatalf("partially committed: %+v", after)
			}
			if _, ok := b.Node(3); ok {
				t.Fatal("leaked created node")
			}
			apply(t, b, 2, prop(2, "gap", 20))
		})
	}
}
func TestGenerationAndSnapshot(t *testing.T) {
	b := mounted(t, nil)
	for _, g := range []int64{-1, 0, 1, 3} {
		if b.ApplyBatch(Batch{Generation: g}) == nil {
			t.Fatalf("accepted generation %d", g)
		}
	}
	if err := b.ApplySnapshot(Batch{Generation: 20, Ops: []Operation{create(7, "text"), prop(7, "text", "restored")}}); err != nil {
		t.Fatal(err)
	}
	if _, ok := b.Node(1); ok {
		t.Fatal("old tree survived snapshot")
	}
	if b.Generation() != 20 {
		t.Fatal(b.Generation())
	}
	if b.ApplySnapshot(Batch{Generation: 21, Ops: []Operation{create(8, "invented")}}) == nil {
		t.Fatal("accepted bad snapshot")
	}
	if _, ok := b.Node(7); !ok || b.Generation() != 20 {
		t.Fatal("bad snapshot replaced tree")
	}
	apply(t, b, 21, prop(7, "text", "updated"))
}
func TestRemovedLineBreakKind(t *testing.T) {
	for _, snapshot := range []bool{false, true} {
		name := "delta"
		if snapshot {
			name = "snapshot"
		}
		t.Run(name, func(t *testing.T) {
			b := New(Config{Renderers: map[string]Renderer{
				"br": func(c *ui.Context, _ Node, _ func(), _ func(Event)) {
					ui.Text(c, "legacy line break")
				},
			}})
			apply(t, b, 1, create(1, "root"))
			payload := []byte(`{"generation":2,"ops":[{"op":"create-node","id":3,"kind":"column"},{"op":"create-node","id":4,"kind":"br"},{"op":"insert-child","parent":3,"child":4,"index":0}]}`)
			if err := b.ApplyJSON(payload, snapshot); err == nil {
				t.Fatal("renderer registration revived a removed standard kind")
			}
			if _, ok := b.Node(1); !ok || b.Generation() != 1 {
				t.Fatal("rejected batch changed the existing tree")
			}
			if _, ok := b.Node(3); ok {
				t.Fatal("rejected batch leaked a node")
			}
		})
	}
}

func TestMalformedWire(t *testing.T) {
	for _, s := range []string{
		`{}`, `null`, `[]`, `{"generation":1}`, `{"generation":1,"ops":null}`, `{"generation":1.5,"ops":[]}`,
		`{"generation":1,"ops":[{"op":"create-node","kind":"text"}]}`,
		`{"generation":1,"ops":[{"op":"create-node","id":1,"kind":"text"},{"op":"set-prop","id":1,"property":"text"}]}`,
		`{"generation":1,"ops":[{"op":"insert-child","parent":1,"child":2}]}`,
		`{"generation":1,"ops":[{"op":"drop-node","id":"1"}]}`,
		`{"generation":1,"ops":[]} trailing`,
	} {
		t.Run(s, func(t *testing.T) {
			if New(Config{}).ApplyJSON([]byte(s), false) == nil {
				t.Fatal("accepted malformed JSON")
			}
		})
	}
}
func TestRenderAndEvents(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "text"), prop(3, "text", "Count: 0"), insert(2, 3, 0), create(4, "button"), prop(4, "text", "Add"), prop(4, "press-enabled", true), insert(2, 4, 1), create(5, "checkbox"), prop(5, "text", "Done"), prop(5, "checked", false), prop(5, "toggle-enabled", true), insert(2, 5, 2), create(6, "text-field"), prop(6, "text", ""), prop(6, "placeholder", "Draft"), prop(6, "submit-enabled", true), insert(2, 6, 3))
	tester := ui.NewTester(b.View, 400, 300)
	if !tester.HasText("Count: 0") {
		t.Fatal(tester.Texts())
	}
	if err := tester.Click("Add"); err != nil {
		t.Fatal(err)
	}
	if err := tester.Click("Done"); err != nil {
		t.Fatal(err)
	}
	if err := tester.Click("Draft"); err != nil {
		t.Fatal(err)
	}
	tester.Type("你好 🌍")
	tester.Key(0, ui.KeyEnter)
	found := func(kind string, id int64) Event {
		for _, e := range events {
			if e.Kind == kind && e.Node == id {
				return e
			}
		}
		t.Fatalf("missing %s/%d in %+v", kind, id, events)
		return Event{}
	}
	found("press", 4)
	if !found("toggle-changed", 5).Checked {
		t.Fatal("toggle payload")
	}
	if found("text-changed", 6).Text != "你好 🌍" {
		t.Fatal("text payload")
	}
	found("submit", 6)
	apply(t, b, 3, prop(3, "text", "Count: 1"), prop(4, "enabled", false), prop(6, "text", "server"))
	tester.Frame()
	if !tester.HasText("Count: 1") {
		t.Fatal(tester.Texts())
	}
	tester.Key(0, ui.KeyEnd)
	tester.Type("!")
	if events[len(events)-1].Kind != "text-changed" || events[len(events)-1].Text != "server!" {
		t.Fatalf("server value did not reach editor: %+v", events)
	}
	count := len(events)
	_ = tester.Click("Add")
	if len(events) != count {
		t.Fatal("disabled button dispatched")
	}
	if tester.Image().Bounds().Dx() != 400 {
		t.Fatal("missing rendered image")
	}
}
func TestRenderReorderDetachAndIdentity(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "text-field"), prop(3, "placeholder", "First"), create(4, "text-field"), prop(4, "placeholder", "Second"), insert(2, 3, 0), insert(2, 4, 1))
	tester := ui.NewTester(b.View, 400, 300)
	_ = tester.Click("First")
	tester.Type("retained")
	apply(t, b, 3, Operation{Op: "move-child", Parent: 2, Child: 3, Index: 1})
	tester.Frame()
	if !tester.Focused("First") {
		t.Fatal("move lost focus/identity")
	}
	tester.Type("!")
	if events[len(events)-1].Text != "retained!" {
		t.Fatal("move lost editor state")
	}
	apply(t, b, 4, Operation{Op: "detach-subtree", ID: 3})
	tester.Frame()
	if _, ok := tester.Find("First"); ok {
		t.Fatal("detached node still rendered")
	}
}
func TestDispatchError(t *testing.T) {
	b := mounted(t, func(Event) error { return fmt.Errorf("runtime failed") })
	apply(t, b, 2, create(3, "button"), prop(3, "text", "Fail"), prop(3, "press-enabled", true), insert(2, 3, 0))
	tester := ui.NewTester(b.View, 200, 100)
	_ = tester.Click("Fail")
	if b.Err() == nil || !strings.Contains(b.Err().Error(), "runtime failed") {
		t.Fatal("lost dispatch failure")
	}
}
func TestLargeTree(t *testing.T) {
	if testing.Short() {
		t.Skip("large retained tree")
	}
	b := New(Config{})
	ops := []Operation{create(1, "column")}
	for i := int64(2); i < 10002; i++ {
		ops = append(ops, create(i, "text"), insert(1, i, int(i-2)))
	}
	apply(t, b, 1, ops...)
	apply(t, b, 2, Operation{Op: "detach-subtree", ID: 1})
	if len(b.Roots()) != 0 {
		t.Fatal("incomplete subtree deletion")
	}
}
func FuzzApplyJSON(f *testing.F) {
	for _, s := range []string{`{"generation":1,"ops":[]}`, `{"generation":1,"ops":[{"op":"create-node","id":1,"kind":"text"}]}`, `null`, `{}`} {
		f.Add(s)
	}
	f.Fuzz(func(t *testing.T, s string) {
		b := New(Config{})
		err := b.ApplyJSON([]byte(s), false)
		if err != nil && b.Generation() != 0 {
			t.Fatal("failed JSON changed generation")
		}
		if err == nil {
			for _, id := range b.Roots() {
				if _, ok := b.Node(id); !ok {
					t.Fatal("invalid root")
				}
			}
		}
	})
}
func TestEventJSON(t *testing.T) {
	encoded, err := json.Marshal(Event{Kind: "text-changed", Node: 7, Text: "a\x00你好"})
	if err != nil {
		t.Fatal(err)
	}
	if !json.Valid(encoded) {
		t.Fatal(string(encoded))
	}
}

func TestBatchJSONRoundTrip(t *testing.T) {
	for _, batch := range []Batch{
		{Generation: 1, Ops: []Operation{create(1, "column"), create(2, "text"), insert(1, 2, 0), prop(2, "text", "hi")}},
		{Generation: 1, Ops: []Operation{{Op: "create-extension", ID: 1, Identifier: "example", Fingerprint: ""}}},
	} {
		encoded, err := json.Marshal(batch)
		if err != nil {
			t.Fatal(err)
		}
		decoded, err := DecodeBatch(encoded)
		if err != nil {
			t.Fatal(err)
		}
		if len(decoded.Ops) != len(batch.Ops) {
			t.Fatal("lost operation")
		}
	}
}
func TestPressModifiers(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "button"), prop(3, "text", "Modified"), prop(3, "press-enabled", true), insert(2, 3, 0))
	tester := ui.NewTester(b.View, 250, 120)
	if err := tester.ClickWith(ui.Ctrl|ui.Shift, "Modified"); err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 || events[0].Kind != "press-modifiers" || events[0].Modifiers != 3 {
		t.Fatal(events)
	}
}
func TestPropertyValidationAndAtomicTheme(t *testing.T) {
	cases := []Operation{
		prop(2, "background", "#badhex"), prop(2, "theme", `{"primary":"#12"}`), prop(2, "gap", -1), prop(2, "width", -1), prop(2, "opacity", 2.0), prop(2, "opacity", -0.1), prop(2, "step", 0.0),
		prop(2, "theme", "not json"), prop(2, "theme", "[]"), prop(2, "theme", `{"primary":12}`), prop(2, "theme", `{"primary":{"light":"#ffffff"}}`), prop(2, "theme-mode", "sepia"), prop(2, "theme", `{"primary":""}`),
	}
	for _, op := range cases {
		t.Run(op.Property+fmt.Sprint(op.Value), func(t *testing.T) {
			b := mounted(t, nil)
			if b.ApplyBatch(Batch{Generation: 2, Ops: []Operation{prop(2, "gap", 99), op}}) == nil {
				t.Fatal("accepted invalid value")
			}
			n, _ := b.Node(2)
			if n.Number("gap", 0) != 12 {
				t.Fatal("failed property batch leaked changes")
			}
		})
	}
}
func TestMoveToSameIndexAndDetachedReparent(t *testing.T) {
	b := mounted(t, nil)
	apply(t, b, 2, create(3, "text"), prop(3, "text", "live"), insert(2, 3, 0), Operation{Op: "move-child", Parent: 2, Child: 3, Index: 0})
	apply(t, b, 3, Operation{Op: "remove-child", Parent: 2, Child: 3}, insert(1, 3, 1))
	n, _ := b.Node(3)
	if n.Parent != 1 {
		t.Fatal(n)
	}
	apply(t, b, 4, Operation{Op: "detach-subtree", ID: 3})
	root, _ := b.Node(1)
	if !reflect.DeepEqual(root.Children, []int64{2}) {
		t.Fatal(root)
	}
}
func TestExtensionPayload(t *testing.T) {
	for _, values := range []map[string]any{nil, {"x": "a\x00你好", "number": 1.5, "ok": true}} {
		encoded, err := extensionPayload(Event{Kind: "extension-event", Identifier: "example", Name: "changed", Values: values})
		if err != nil || !json.Valid([]byte(encoded)) {
			t.Fatalf("%s: %v", encoded, err)
		}
	}
	for _, e := range []Event{{Kind: "extension-event"}, {Kind: "extension-event", Identifier: "example", Name: "changed", Values: map[string]any{"x": []int{1}}}} {
		if _, err := extensionPayload(e); err == nil {
			t.Fatal("accepted invalid extension event")
		}
	}
}

func TestUnrenderableNumbersAreRejected(t *testing.T) {
	for _, value := range []any{math.NaN(), math.Inf(1), 1e300, json.Number("1e300"), json.Number("9223372036854775808"), json.Number("1.5")} {
		b := mounted(t, nil)
		if b.ApplyBatch(Batch{Generation: 2, Ops: []Operation{prop(2, "width", value)}}) == nil {
			t.Fatalf("accepted unrenderable width %v", value)
		}
	}
	// Font strings are a cross-platform property. Invalid CSS lengths must not
	// turn into infinities when handed to MyGo's layout engine.
	b := New(Config{})
	apply(t, b, 1, create(1, "text"), prop(1, "text", "safe"), prop(1, "font-size", "1e300px"))
	tester := ui.NewTester(b.View, 200, 100)
	if !tester.HasText("safe") {
		t.Fatal(tester.Texts())
	}
}
func TestExtensionDefaultsRequireScalars(t *testing.T) {
	b := New(Config{Extensions: map[string]Extension{"example": {Fingerprint: "v1", Defaults: map[string]any{"bad": map[string]any{"x": 1}}, Render: func(*ui.Context, Node, func(), func(Event)) {}}}})
	if b.ApplyBatch(Batch{Generation: 1, Ops: []Operation{{Op: "create-extension", ID: 1, Identifier: "example", Fingerprint: "v1"}}}) == nil {
		t.Fatal("accepted non-scalar extension default")
	}
}
