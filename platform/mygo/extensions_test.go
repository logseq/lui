package luimygo

import (
	"encoding/json"
	"fmt"
	"github.com/egoist/mygo/ui"
	"os"
	"slices"
	"testing"
)

func TestExtensions(t *testing.T) {
	extension := Extension{Fingerprint: "v1", Defaults: map[string]any{"title": "Default"}, Render: func(c *ui.Context, n Node, children func(), emit func(Event)) {
		ui.Column(c).Children(func() { ui.Text(c, n.String("title")); children() })
	}}
	b := New(Config{Extensions: map[string]Extension{"example": extension}})
	apply(t, b, 1, Operation{Op: "create-extension", ID: 1, Identifier: "example", Fingerprint: "v1"}, create(2, "text"), prop(2, "text", "child"), insert(1, 2, 0))
	tester := ui.NewTester(b.View, 300, 200)
	if !tester.HasText("Default") || !tester.HasText("child") {
		t.Fatal(tester.Texts())
	}
	apply(t, b, 2, Operation{Op: "set-extension-prop", ID: 1, Property: "title", Value: "Changed"})
	tester.Frame()
	if !tester.HasText("Changed") {
		t.Fatal(tester.Texts())
	}
	apply(t, b, 3, Operation{Op: "remove-extension-prop", ID: 1, Property: "title"})
	tester.Frame()
	if !tester.HasText("Default") {
		t.Fatal(tester.Texts())
	}
	apply(t, b, 4, Operation{Op: "create-extension", ID: 3, Identifier: "example"})
	n, _ := b.Node(3)
	if n.Fingerprint != "v1" {
		t.Fatal("fingerprint dedupe failed")
	}
	for _, op := range []Operation{
		{Op: "create-extension", ID: 4, Identifier: "missing"},
		{Op: "create-extension", ID: 4, Identifier: "example", Fingerprint: "bad"},
		{Op: "set-extension-prop", ID: 2, Property: "title", Value: "wrong node"},
		{Op: "set-prop", ID: 1, Property: "text", Value: "wrong namespace"},
	} {
		if b.ApplyBatch(Batch{Generation: 5, Ops: []Operation{op}}) == nil {
			t.Fatalf("accepted %+v", op)
		}
	}
}
func TestAppearAndEventGates(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "button"), prop(3, "text", "Gated"), prop(3, "appear-enabled", true), insert(2, 3, 0))
	tester := ui.NewTester(b.View, 250, 150)
	tester.Frame()
	_ = tester.Click("Gated")
	if len(events) != 1 || events[0].Kind != "appear" {
		t.Fatalf("events: %+v", events)
	}
	apply(t, b, 3, prop(3, "press-enabled", true))
	tester.Frame()
	_ = tester.Click("Gated")
	if events[len(events)-1].Kind != "press" {
		t.Fatal(events)
	}
	apply(t, b, 4, Operation{Op: "detach-subtree", ID: 3}, create(3, "button"), prop(3, "text", "Recreated"), prop(3, "appear-enabled", true), insert(2, 3, 0))
	tester.Frame()
	if events[len(events)-1].Kind != "appear" {
		t.Fatal("recreated node did not appear")
	}
}
func TestAllSupportedKindsRender(t *testing.T) {
	data, err := os.ReadFile("../../schema/mygo-manifest.json")
	if err != nil {
		t.Fatal(err)
	}
	var canonical struct {
		Kinds map[string]struct {
			Baseline map[string]oracleValue `json:"baseline"`
		} `json:"kinds"`
	}
	if err := json.Unmarshal(data, &canonical); err != nil {
		t.Fatal(err)
	}
	if len(SupportedKinds()) != len(canonical.Kinds) {
		t.Fatal("built-in kinds differ from the canonical schema")
	}
	for kind := range canonical.Kinds {
		if !supportedKind(kind) {
			t.Fatalf("canonical kind %q lacks a built-in adapter", kind)
		}
	}

	for _, kind := range SupportedKinds() {
		t.Run(kind, func(t *testing.T) {
			b := New(Config{})
			ops := []Operation{create(1, kind)}
			names := make([]string, 0, len(canonical.Kinds[kind].Baseline))
			for name := range canonical.Kinds[kind].Baseline {
				names = append(names, name)
			}
			slices.Sort(names)
			for _, name := range names {
				ops = append(ops, prop(1, name, canonical.Kinds[kind].Baseline[name].raw()))
			}

			apply(t, b, 1, ops...)
			tester := ui.NewTester(b.View, 320, 240)
			if tester.Image() == nil {
				t.Fatal("no frame")
			}
		})
	}
}
func TestLayoutGeometry(t *testing.T) {
	for _, kind := range []string{"row", "column", "grid"} {
		t.Run(kind, func(t *testing.T) {
			b := New(Config{})
			ops := []Operation{create(1, kind), prop(1, "padding", 10), prop(1, "gap", 8)}
			if kind == "grid" {
				ops = append(ops, prop(1, "columns", 2))
			}
			for i := int64(2); i <= 3; i++ {
				ops = append(ops, create(i, "button"), prop(i, "text", fmt.Sprint(i)), prop(i, "width", 60), prop(i, "height", 30), insert(1, i, int(i-2)))
			}
			apply(t, b, 1, ops...)
			tester := ui.NewTester(b.View, 300, 200)
			a, ok := tester.Find("2")
			if !ok {
				t.Fatal(tester.Texts())
			}
			z, _ := tester.Find("3")
			if kind == "column" && z.Y <= a.Y {
				t.Fatal("column did not stack vertically")
			}
			if kind != "column" && z.X <= a.X {
				t.Fatal("row/grid did not stack horizontally")
			}
		})
	}
}

func TestModelOwnedPickerAndCombobox(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "select"), prop(3, "text", "Production"), prop(3, "press-enabled", true), insert(2, 3, 0), create(4, "combobox"), prop(4, "placeholder", "Environment"), prop(4, "submit-enabled", true), insert(2, 4, 1))
	tester := ui.NewTester(b.View, 400, 240)
	if err := tester.Click("Production"); err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 || events[0].Kind != "press" || events[0].Node != 3 {
		t.Fatalf("select must let the OCaml model open its retained menu: %+v", events)
	}
	if err := tester.Click("Environment"); err != nil {
		t.Fatal(err)
	}
	tester.Type("Staging")
	tester.Key(0, ui.KeyEnter)
	if len(events) != 3 || events[1].Kind != "text-changed" || events[1].Text != "Staging" || events[2].Kind != "submit" {
		t.Fatal(events)
	}
}
func TestThemeScopeAndMode(t *testing.T) {
	b := New(Config{})
	apply(t, b, 1, create(1, "root"), prop(1, "theme", `{"primary":"#00ff00"}`), create(2, "column"), prop(2, "theme", `{"primary":{"light":"#ff0000","dark":"#0000ff"}}`), prop(2, "background", "primary"), prop(2, "height", 50), prop(2, "width", 100), insert(1, 2, 0), create(3, "column"), prop(3, "background", "primary"), prop(3, "height", 50), prop(3, "width", 100), insert(1, 3, 1))
	tester := ui.NewTester(b.View, 200, 120)
	rgb := func(x, y int) (uint32, uint32, uint32) { r, g, b, _ := tester.Image().At(x, y).RGBA(); return r, g, b }
	if r, g, z := rgb(20, 20); r != 65535 || g != 0 || z != 0 {
		t.Fatalf("light theme: %d %d %d", r, g, z)
	}
	if r, g, z := rgb(20, 70); r != 0 || g != 65535 || z != 0 {
		t.Fatalf("nested theme leaked to sibling: %d %d %d", r, g, z)
	}
	apply(t, b, 2, prop(2, "theme-mode", "dark"))
	tester.Frame()
	if r, g, z := rgb(20, 20); r != 0 || g != 0 || z != 65535 {
		t.Fatalf("dark theme: %d %d %d", r, g, z)
	}
	apply(t, b, 3, prop(1, "theme-mode", "dark"), prop(2, "theme-mode", "system"))
	tester.Frame()
	if r, g, z := rgb(20, 20); r != 65535 || g != 0 || z != 0 {
		t.Fatalf("system mode inherited forced parent mode: %d %d %d", r, g, z)
	}
	tester.SetDark(true)
	if r, g, z := rgb(20, 20); r != 0 || g != 0 || z != 65535 {
		t.Fatalf("system mode did not follow system appearance: %d %d %d", r, g, z)
	}

}
func TestModalDismissAndDisabledInheritance(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "dialog"), prop(3, "text", "Confirm"), insert(2, 3, 0), create(4, "button"), prop(4, "text", "Save"), prop(4, "press-enabled", true), insert(3, 4, 0))
	tester := ui.NewTester(b.View, 400, 300)
	if !tester.HasText("Save") {
		t.Fatal(tester.Texts())
	}
	tester.Key(0, ui.KeyEscape)
	if len(events) != 1 || events[0].Kind != "dismiss" || events[0].Node != 3 {
		t.Fatal(events)
	}
	apply(t, b, 3, Operation{Op: "detach-subtree", ID: 3}, create(5, "box"), prop(5, "inert", true), insert(2, 5, 0), create(6, "button"), prop(6, "text", "Disabled child"), prop(6, "press-enabled", true), insert(5, 6, 0))
	tester.Frame()
	_ = tester.Click("Disabled child")
	if len(events) != 1 {
		t.Fatal("disabled parent allowed child interaction")
	}
}
func TestNumericControlsAndToggle(t *testing.T) {
	var events []Event
	var b *Backend
	b = mounted(t, func(e Event) error {
		events = append(events, e)
		var op Operation
		switch e.Kind {
		case "value-changed":
			op = prop(e.Node, "value", e.Value)
		case "toggle-changed":
			op = prop(e.Node, "selected", e.Checked)
		default:
			return nil
		}
		return b.ApplyBatch(Batch{Generation: b.Generation() + 1, Ops: []Operation{op}})
	})
	apply(t, b, 2, create(3, "slider"), prop(3, "value", 0.0), prop(3, "accessibility-label", "Volume"), insert(2, 3, 0), create(4, "toggle-button"), prop(4, "text", "Bold"), prop(4, "toggle-enabled", true), insert(2, 4, 1))
	tester := ui.NewTester(b.View, 400, 200)
	_ = tester.Click("Volume")
	tester.Key(0, ui.KeyRight)
	if len(events) == 0 || events[len(events)-1].Kind != "value-changed" || events[len(events)-1].Value <= 0 {
		t.Fatal(events)
	}
	_ = tester.Click("Bold")
	_ = tester.Click("Bold")
	if len(events) < 3 || events[len(events)-2].Kind != "toggle-changed" || !events[len(events)-2].Checked || events[len(events)-1].Checked {
		t.Fatalf("toggle state: %+v", events)
	}
}
func TestCustomRendererEventsAreDeliveredAfterBuild(t *testing.T) {
	building := false
	emitted := false
	count := 0
	b := New(Config{Dispatch: func(e Event) error {
		if building {
			t.Fatal("dispatch reentered an unfinished build")
		}
		if e.Kind != "pointer-enter" || e.Node != 1 {
			t.Fatalf("wrong admitted event: %+v", e)
		}
		count++
		return nil
	}, Renderers: map[string]Renderer{"icon": func(c *ui.Context, n Node, children func(), emit func(Event)) {
		building = true
		ui.Text(c, "custom icon")
		if !emitted {
			emitted = true
			emit(Event{Kind: "pointer-enter", Node: n.ID})
		}
		building = false
	}}})
	apply(t, b, 1, create(1, "icon"), prop(1, "name", "check"), prop(1, "pointer-enabled", true))
	tester := ui.NewTester(b.View, 200, 100)
	if !tester.HasText("custom icon") {
		t.Fatal(tester.Texts())
	}
	if count != 1 {
		t.Fatalf("admitted callbacks = %d, want 1", count)
	}
}
