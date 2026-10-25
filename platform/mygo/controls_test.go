package luimygo

import (
	"strings"
	"testing"

	"github.com/egoist/mygo/ui"
)

func widgetCount(events []Event, kind string, node int64) int {
	count := 0
	for _, e := range events {
		if e.Kind == kind && e.Node == node {
			count++
		}
	}
	return count
}
func widgetLast(t *testing.T, events []Event, kind string, node int64) Event {
	t.Helper()
	for i := len(events) - 1; i >= 0; i-- {
		if events[i].Kind == kind && events[i].Node == node {
			return events[i]
		}
	}
	t.Fatalf("missing %s for node %d: %+v", kind, node, events)
	return Event{}
}
func widgetClick(t *testing.T, tt *ui.Tester, text string) {
	t.Helper()
	if err := tt.Click(text); err != nil {
		t.Fatal(err)
	}
}
func widgetTexts(t *testing.T, tt *ui.Tester, visible, hidden []string) {
	t.Helper()
	for _, text := range visible {
		if !tt.HasText(text) {
			t.Fatalf("missing visible %q: %v", text, tt.Texts())
		}
	}
	for _, text := range hidden {
		if tt.HasText(text) {
			t.Fatalf("unexpected visible %q: %v", text, tt.Texts())
		}
	}
}

func TestControlsTabsRovingFocusPreservesModelSelection(t *testing.T) {
	for _, orientation := range []string{"horizontal", "vertical"} {
		t.Run(orientation, func(t *testing.T) {
			var events []Event
			b := mounted(t, func(e Event) error { events = append(events, e); return nil })
			apply(t, b, 2, create(3, "tabs"), prop(3, "accessibility-label", "Workspaces"), prop(3, "orientation", orientation), insert(2, 3, 0),
				create(4, "button"), prop(4, "text", "Overview"), prop(4, "selected", true), prop(4, "press-enabled", true), insert(3, 4, 0),
				create(5, "button"), prop(5, "text", "Unavailable"), prop(5, "enabled", false), prop(5, "press-enabled", true), insert(3, 5, 1),
				create(6, "button"), prop(6, "text", "Activity"), prop(6, "press-enabled", true), insert(3, 6, 2))
			tt := ui.NewTester(b.View, 500, 240)
			widgetClick(t, tt, "Overview")
			next := ui.KeyRight
			if orientation == "vertical" {
				next = ui.KeyDown
			}
			tt.Key(0, next)
			if !tt.Focused("Activity") {
				t.Fatalf("arrow must skip disabled tab: %v", tt.Texts())
			}
			widgetLast(t, events, "press", 6)
			tt.Key(0, ui.KeyHome)
			if !tt.Focused("Overview") {
				t.Fatal("Home must focus first tab")
			}
			tt.Key(0, ui.KeyEnd)
			if !tt.Focused("Activity") {
				t.Fatal("End must focus last tab")
			}
			tt.Key(0, ui.KeyEnter)
			widgetLast(t, events, "press", 6)
			if widgetCount(events, "press", 5) != 0 {
				t.Fatal("disabled tab activated")
			}
			n, _ := b.Node(4)
			if !n.Bool("selected") {
				t.Fatal("keyboard changed model-owned selection")
			}
		})
	}
}

func TestControlsBottomTabsShowOnlySelectedRetainedPage(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "bottom-tabs"), prop(3, "accessibility-label", "Destinations"), insert(2, 3, 0),
		create(4, "bottom-tab"), prop(4, "title", "Home"), prop(4, "selected", true), prop(4, "press-enabled", true), insert(3, 4, 0),
		create(5, "text-field"), prop(5, "text", "Draft"), prop(5, "placeholder", "Home editor"), insert(4, 5, 0),
		create(6, "bottom-tab"), prop(6, "title", "Search"), prop(6, "selected", false), prop(6, "press-enabled", true), insert(3, 6, 1),
		create(7, "text"), prop(7, "text", "Search results"), insert(6, 7, 0))
	tt := ui.NewTester(b.View, 500, 320)
	widgetTexts(t, tt, []string{"Home editor", "Home", "Search"}, []string{"Search results"})
	widgetClick(t, tt, "Search")
	widgetLast(t, events, "press", 6)
	widgetTexts(t, tt, []string{"Home editor"}, []string{"Search results"})
	apply(t, b, 3, prop(4, "selected", false), prop(6, "selected", true))
	tt.Frame()
	widgetTexts(t, tt, []string{"Search results"}, []string{"Home editor"})
	if _, ok := b.Node(5); !ok {
		t.Fatal("inactive page lost retained editor")
	}
	apply(t, b, 4, prop(4, "selected", true), prop(6, "selected", false))
	tt.Frame()
	widgetTexts(t, tt, []string{"Draft"}, []string{"Search results"})
}

func TestControlsTreeKeyboardProposesExpansionAndMovesFocus(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "tree"), prop(3, "accessibility-label", "Files"), insert(2, 3, 0),
		create(4, "list-item"), prop(4, "text", "Documents"), prop(4, "role", "treeitem"), prop(4, "tree-level", 1), prop(4, "expanded", false), prop(4, "toggle-enabled", true), prop(4, "press-enabled", true), insert(3, 4, 0),
		create(5, "list-item"), prop(5, "text", "Archive"), prop(5, "role", "treeitem"), prop(5, "tree-level", 1), prop(5, "press-enabled", true), insert(3, 5, 1))
	tt := ui.NewTester(b.View, 400, 220)
	widgetClick(t, tt, "Documents")
	tt.Key(0, ui.KeyRight)
	if !widgetLast(t, events, "toggle-changed", 4).Checked {
		t.Fatal("Right must propose expansion")
	}
	n, _ := b.Node(4)
	if n.Bool("expanded") {
		t.Fatal("tree mutated model expansion")
	}
	apply(t, b, 3, prop(4, "expanded", true))
	tt.Frame()
	tt.Key(0, ui.KeyLeft)
	if widgetLast(t, events, "toggle-changed", 4).Checked {
		t.Fatal("Left must propose collapse")
	}
	tt.Key(0, ui.KeyDown)
	if !tt.Focused("Archive") {
		t.Fatal("Down must move to next retained tree row")
	}
	tt.Key(0, ui.KeyEnter)
	widgetLast(t, events, "press", 5)
}

func TestControlsAccordionRejectedProposalRestoresClosedState(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "accordion"), prop(3, "text", "Details"), prop(3, "selected", false), prop(3, "toggle-enabled", true), insert(2, 3, 0), create(4, "text"), prop(4, "text", "Retained details"), insert(3, 4, 0))
	tt := ui.NewTester(b.View, 400, 220)
	tt.SetPreferences(ui.Preferences{ReduceMotion: true, TextScale: 1})
	widgetTexts(t, tt, []string{"Details"}, []string{"Retained details"})
	widgetClick(t, tt, "Details")
	if !widgetLast(t, events, "toggle-changed", 3).Checked {
		t.Fatal("missing expansion proposal")
	}
	apply(t, b, 3, prop(3, "selected", false))
	tt.Frame()
	widgetTexts(t, tt, []string{"Details"}, []string{"Retained details"})
	apply(t, b, 4, prop(3, "selected", true))
	tt.Frame()
	widgetTexts(t, tt, []string{"Retained details"}, nil)
	apply(t, b, 5, Operation{Op: "remove-prop", ID: 3, Property: "selected"})
	tt.Frame()
	widgetTexts(t, tt, nil, []string{"Retained details"})
}

func TestControlsCheckboxRejectedProposalDoesNotBecomeNextValue(t *testing.T) {
	for _, kind := range []string{"checkbox", "toggle", "switch", "toggle-button"} {
		t.Run(kind, func(t *testing.T) {
			var events []Event
			b := mounted(t, func(e Event) error { events = append(events, e); return nil })
			property := "checked"
			if kind == "toggle-button" {
				property = "selected"
			}
			apply(t, b, 2, create(3, kind), prop(3, "text", "Choice"), prop(3, "accessibility-label", "Choice"), prop(3, property, false), prop(3, "toggle-enabled", true), insert(2, 3, 0))
			tt := ui.NewTester(b.View, 400, 200)
			widgetClick(t, tt, "Choice")
			if !widgetLast(t, events, "toggle-changed", 3).Checked {
				t.Fatal("first click must propose true")
			}
			apply(t, b, 3, prop(3, property, false))
			tt.Frame()
			widgetClick(t, tt, "Choice")
			if !widgetLast(t, events, "toggle-changed", 3).Checked {
				t.Fatal("rejected click incorrectly became accepted state")
			}
			apply(t, b, 4, prop(3, "enabled", false))
			tt.Frame()
			before := len(events)
			widgetClick(t, tt, "Choice")
			tt.Key(0, ui.KeySpace)
			if len(events) != before {
				t.Fatal("disabled choice emitted interaction")
			}
		})
	}
}

func TestControlsTextInputNormalizationDisabledAndPropertyRemoval(t *testing.T) {
	for _, kind := range []string{"text-field", "secure-field", "input", "search-field", "textarea", "combobox"} {
		t.Run(kind, func(t *testing.T) {
			var events []Event
			b := mounted(t, func(e Event) error { events = append(events, e); return nil })
			apply(t, b, 2, create(3, kind), prop(3, "text", "seed"), prop(3, "placeholder", "Editor"), prop(3, "submit-enabled", true), insert(2, 3, 0))
			tt := ui.NewTester(b.View, 500, 260)
			widgetClick(t, tt, "Editor")
			tt.Key(ui.Ctrl, ui.KeyA)
			tt.Key(ui.Cmd, ui.KeyA)
			tt.Type("mixed")
			proposal := widgetLast(t, events, "text-changed", 3).Text
			if !strings.Contains(proposal, "mixed") {
				t.Fatalf("missing edit: %q", proposal)
			}
			apply(t, b, 3, prop(3, "text", "MIXED"))
			tt.Frame()
			tt.Key(0, ui.KeyEnd)
			tt.Type("!")
			if got := widgetLast(t, events, "text-changed", 3).Text; got != "MIXED!" {
				t.Fatalf("normalized reducer text lost: %q", got)
			}
			apply(t, b, 4, prop(3, "enabled", false))
			tt.Frame()
			before := len(events)
			tt.Type("bad")
			tt.Key(0, ui.KeyEnter)
			if len(events) != before {
				t.Fatal("disabled editor emitted events")
			}
			apply(t, b, 5, Operation{Op: "remove-prop", ID: 3, Property: "enabled"}, Operation{Op: "remove-prop", ID: 3, Property: "text"})
			tt.Frame()
			widgetClick(t, tt, "Editor")
			tt.Type("fresh")
			if got := widgetLast(t, events, "text-changed", 3).Text; got != "fresh" {
				t.Fatalf("removed text must reset editor: %q", got)
			}
		})
	}
}

func TestControlsNumberStepperRangeAndRejectedValue(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "number-stepper"), prop(3, "accessibility-label", "Quantity"), prop(3, "value", 8.0), prop(3, "min", 2.0), prop(3, "max", 10.0), prop(3, "step", 2.0), insert(2, 3, 0))
	tt := ui.NewTester(b.View, 400, 180)
	r, ok := tt.Find("Quantity")
	if !ok {
		t.Fatal("missing numeric editor")
	}
	tt.ClickAt(r.X+20, r.Y+r.H/2)
	tt.Key(0, ui.KeyUp)
	if got := widgetLast(t, events, "value-changed", 3).Value; got != 10 {
		t.Fatalf("step: %g", got)
	}
	apply(t, b, 3, prop(3, "value", 8.0))
	tt.Frame()
	tt.Key(0, ui.KeyDown)
	if got := widgetLast(t, events, "value-changed", 3).Value; got != 6 {
		t.Fatalf("rejected value persisted: %g", got)
	}
	apply(t, b, 4, prop(3, "value", 10.0))
	tt.Frame()
	tt.Key(0, ui.KeyUp)
	for _, e := range events {
		if e.Kind == "value-changed" && (e.Value < 2 || e.Value > 10) {
			t.Fatalf("out of range proposal: %+v", e)
		}
	}
}

func TestControlsRadioGroupKeyboardAndControlledSelection(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "radio-group"), prop(3, "accessibility-label", "Density"), insert(2, 3, 0),
		create(4, "radio"), prop(4, "text", "Comfortable"), prop(4, "checked", true), prop(4, "change-enabled", true), insert(3, 4, 0),
		create(5, "radio"), prop(5, "text", "Compact"), prop(5, "checked", false), prop(5, "change-enabled", true), insert(3, 5, 1))
	tt := ui.NewTester(b.View, 400, 200)
	widgetClick(t, tt, "Comfortable")
	tt.Key(0, ui.KeyDown)
	if !tt.Focused("Compact") {
		t.Fatal("radio arrows failed to move focus")
	}
	widgetLast(t, events, "change", 5)
	apply(t, b, 3, prop(4, "checked", true), prop(5, "checked", false))
	tt.Frame()
	widgetClick(t, tt, "Compact")
	widgetLast(t, events, "change", 5)
}

func TestControlsReadOnlyEditorsAllowFocusCopyAndResumeEditing(t *testing.T) {
	for _, kind := range []string{"text-field", "input", "search-field", "textarea", "combobox"} {
		t.Run(kind, func(t *testing.T) {
			var events []Event
			b := mounted(t, func(e Event) error { events = append(events, e); return nil })
			apply(t, b, 2, create(3, kind), prop(3, "text", "Copy me"), prop(3, "placeholder", "Read only editor"), prop(3, "read-only", true), insert(2, 3, 0))
			tt := ui.NewTester(b.View, 500, 240)
			widgetClick(t, tt, "Read only editor")
			if !tt.Focused("Read only editor") {
				t.Fatal("read-only editor must remain focusable")
			}
			tt.Key(ui.Ctrl, ui.KeyA)
			tt.Key(ui.Cmd, ui.KeyA)
			tt.Key(ui.Ctrl, ui.KeyC)
			tt.Key(ui.Cmd, ui.KeyC)
			if tt.Clipboard() != "Copy me" {
				t.Fatalf("read-only copy failed: %q", tt.Clipboard())
			}
			tt.Compose("forbidden composition", 10)
			tt.Type("forbidden")
			tt.Key(0, ui.KeyBackspace)
			if widgetCount(events, "text-changed", 3) != 0 {
				t.Fatalf("read-only input proposed mutation: %+v", events)
			}
			apply(t, b, 3, Operation{Op: "remove-prop", ID: 3, Property: "read-only"})
			tt.Frame()
			tt.Key(0, ui.KeyEnd)
			tt.Type("!")
			if got := widgetLast(t, events, "text-changed", 3).Text; got != "Copy me!" {
				t.Fatalf("editing did not resume: %q", got)
			}
		})
	}
}

func TestControlsSecureReadOnlyEditorSuppressesEditsAndClipboard(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "secure-field"), prop(3, "text", "secret"), prop(3, "placeholder", "Password"), prop(3, "read-only", true), insert(2, 3, 0))
	tt := ui.NewTester(b.View, 400, 200)
	widgetClick(t, tt, "Password")
	tt.SetClipboard("safe")
	tt.Key(ui.Ctrl, ui.KeyA)
	tt.Key(ui.Cmd, ui.KeyA)
	tt.Key(ui.Ctrl, ui.KeyC)
	tt.Key(ui.Cmd, ui.KeyC)
	tt.Type("bad")
	if tt.Clipboard() != "safe" {
		t.Fatal("secure editor exposed password to clipboard")
	}
	if widgetCount(events, "text-changed", 3) != 0 {
		t.Fatal("read-only password emitted mutation")
	}
}

func TestControlsSliderControlledKeyboardAndDisabled(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "slider"), prop(3, "value", 0.5), prop(3, "accessibility-label", "Volume"), insert(2, 3, 0))
	tt := ui.NewTester(b.View, 400, 200)
	widgetClick(t, tt, "Volume")
	tt.Key(0, ui.KeyRight)
	proposed := widgetLast(t, events, "value-changed", 3).Value
	if proposed <= 0.5 || proposed > 1 {
		t.Fatalf("invalid slider proposal: %g", proposed)
	}
	apply(t, b, 3, prop(3, "value", 0.0))
	tt.Frame()
	tt.Key(0, ui.KeyRight)
	proposed = widgetLast(t, events, "value-changed", 3).Value
	if proposed <= 0 || proposed >= 0.5 {
		t.Fatalf("reducer reset ignored: %g", proposed)
	}
	apply(t, b, 4, prop(3, "enabled", false))
	tt.Frame()
	before := len(events)
	tt.Key(0, ui.KeyRight)
	if len(events) != before {
		t.Fatal("disabled slider emitted proposal")
	}
}
