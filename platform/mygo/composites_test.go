package luimygo

import (
	"bytes"
	"testing"

	"github.com/egoist/mygo/ui"
)

func TestCompositesStepperShowsSequenceAndUpdatesActiveStep(t *testing.T) {
	b := mounted(t, nil)
	apply(t, b, 2, create(3, "stepper"), prop(3, "active", 0), prop(3, "accessibility-label", "Checkout"), insert(2, 3, 0),
		create(4, "step"), prop(4, "text", "Address"), insert(3, 4, 0), create(5, "step"), prop(5, "text", "Payment"), insert(3, 5, 1), create(6, "step"), prop(6, "text", "Confirm"), insert(3, 6, 2))
	tt := ui.NewTester(b.View, 700, 250)
	widgetTexts(t, tt, []string{"Address", "Payment", "Confirm"}, nil)
	before := append([]byte(nil), tt.Image().Pix...)
	apply(t, b, 3, prop(3, "active", 1))
	tt.Frame()
	widgetTexts(t, tt, []string{"Address", "Payment", "Confirm"}, nil)
	if bytes.Equal(before, tt.Image().Pix) {
		t.Fatal("active step has no rendered distinction")
	}
	apply(t, b, 4, Operation{Op: "detach-subtree", ID: 5})
	tt.Frame()
	widgetTexts(t, tt, []string{"Address", "Confirm"}, []string{"Payment"})
}

func TestCompositesTimelineRendersActivityFieldsAndRoutesPress(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "timeline"), prop(3, "accessibility-label", "Activity"), insert(2, 3, 0),
		create(4, "timeline-item"), prop(4, "title", "Release published"), prop(4, "description", "Version one"), prop(4, "meta", "Yesterday"), prop(4, "indicator", "1"), prop(4, "connector", true), prop(4, "press-enabled", true), insert(3, 4, 0),
		create(5, "timeline-item"), prop(5, "title", "Build finished"), prop(5, "meta", "Today"), prop(5, "connector", false), insert(3, 5, 1))
	tt := ui.NewTester(b.View, 600, 320)
	widgetTexts(t, tt, []string{"Release published", "Version one", "Yesterday", "Build finished", "Today"}, nil)
	widgetClick(t, tt, "Release published")
	if widgetCount(events, "press", 4) != 1 {
		t.Fatal("timeline activity did not activate once")
	}
	apply(t, b, 3, prop(4, "description", "Version two"), Operation{Op: "remove-prop", ID: 4, Property: "meta"}, Operation{Op: "move-child", Parent: 3, Child: 5, Index: 0})
	tt.Frame()
	widgetTexts(t, tt, []string{"Version two", "Build finished"}, []string{"Version one", "Yesterday"})
	apply(t, b, 4, Operation{Op: "detach-subtree", ID: 3})
	tt.Frame()
	widgetTexts(t, tt, nil, []string{"Release published", "Build finished"})
}

func TestCompositesToolbarRovingFocusSkipsDisabledAndPreservesInputKeys(t *testing.T) {
	for _, orientation := range []string{"horizontal", "vertical"} {
		t.Run(orientation, func(t *testing.T) {
			var events []Event
			b := mounted(t, func(e Event) error { events = append(events, e); return nil })
			apply(t, b, 2, create(3, "toolbar"), prop(3, "accessibility-label", "Formatting"), prop(3, "orientation", orientation), insert(2, 3, 0),
				create(4, "button"), prop(4, "text", "Bold"), prop(4, "press-enabled", true), insert(3, 4, 0),
				create(5, "button"), prop(5, "text", "Disabled"), prop(5, "enabled", false), prop(5, "press-enabled", true), insert(3, 5, 1),
				create(6, "button"), prop(6, "text", "More"), prop(6, "press-enabled", true), insert(3, 6, 2),
				create(7, "input"), prop(7, "text", "ab"), prop(7, "placeholder", "Format input"), insert(3, 7, 3))
			tt := ui.NewTester(b.View, 700, 320)
			widgetClick(t, tt, "Bold")
			next := ui.KeyRight
			if orientation == "vertical" {
				next = ui.KeyDown
			}
			tt.Key(0, next)
			if !tt.Focused("More") {
				t.Fatal("toolbar arrow did not skip disabled control")
			}
			widgetClick(t, tt, "Format input")
			tt.Key(0, ui.KeyHome)
			tt.Key(0, ui.KeyRight)
			tt.Type("X")
			if !tt.Focused("Format input") {
				t.Fatal("toolbar stole editor arrow key")
			}
			if got := widgetLast(t, events, "text-changed", 7).Text; got != "aXb" {
				t.Fatalf("editor navigation failed: %q", got)
			}
		})
	}
}

func TestCompositesInputGroupRetainsEditorAndActionSlots(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "input-group"), insert(2, 3, 0), create(4, "textarea"), prop(4, "text", "Draft"), prop(4, "placeholder", "Message"), prop(4, "height", 80), insert(3, 4, 0),
		create(5, "input-group-actions"), insert(3, 5, 1), create(6, "button"), prop(6, "text", "Send message"), prop(6, "press-enabled", true), insert(5, 6, 0))
	tt := ui.NewTester(b.View, 600, 320)
	editor, ok := tt.Find("Message")
	if !ok {
		t.Fatal("missing textarea slot")
	}
	action, ok := tt.Find("Send message")
	if !ok {
		t.Fatal("missing actions slot")
	}
	if action.Y < editor.Y+editor.H {
		t.Fatalf("input-group actions must sit below textarea: editor=%+v action=%+v", editor, action)
	}
	widgetClick(t, tt, "Message")
	tt.Key(0, ui.KeyEnd)
	tt.Type("!")
	if got := widgetLast(t, events, "text-changed", 4).Text; got != "Draft!" {
		t.Fatalf("group editing: %q", got)
	}
	widgetClick(t, tt, "Send message")
	widgetLast(t, events, "press", 6)
	apply(t, b, 3, prop(6, "enabled", false))
	tt.Frame()
	before := len(events)
	widgetClick(t, tt, "Send message")
	if len(events) != before {
		t.Fatal("disabled input-group action dispatched")
	}
	apply(t, b, 4, Operation{Op: "detach-subtree", ID: 5})
	tt.Frame()
	widgetTexts(t, tt, []string{"Message"}, []string{"Send message"})
}

func TestCompositesBreadcrumbAndPaginationRetainModelOwnedButtons(t *testing.T) {
	for _, kind := range []string{"breadcrumb", "pagination", "button-group", "toggle-group"} {
		t.Run(kind, func(t *testing.T) {
			var events []Event
			b := mounted(t, func(e Event) error { events = append(events, e); return nil })
			apply(t, b, 2, create(3, kind), prop(3, "accessibility-label", "Navigation"), insert(2, 3, 0),
				create(4, "button"), prop(4, "text", "Previous"), prop(4, "selected", true), prop(4, "press-enabled", true), insert(3, 4, 0),
				create(5, "button"), prop(5, "text", "Next"), prop(5, "press-enabled", true), insert(3, 5, 1))
			tt := ui.NewTester(b.View, 500, 220)
			widgetClick(t, tt, "Next")
			widgetLast(t, events, "press", 5)
			n, _ := b.Node(4)
			if !n.Bool("selected") {
				t.Fatal("group stole model-owned selection")
			}
			apply(t, b, 3, prop(4, "selected", false), prop(5, "selected", true), prop(4, "text", "First"))
			tt.Frame()
			widgetTexts(t, tt, []string{"First", "Next"}, []string{"Previous"})
			apply(t, b, 4, Operation{Op: "move-child", Parent: 3, Child: 5, Index: 0})
			tt.Frame()
			a, ok := tt.Find("Next")
			if !ok {
				t.Fatal("missing moved child")
			}
			z, ok := tt.Find("First")
			if !ok {
				t.Fatal("missing first child")
			}
			if a.X >= z.X {
				t.Fatal("group failed to reorder retained controls")
			}
		})
	}
}

func TestCompositesStatusBarUpdatesAndRemovesText(t *testing.T) {
	b := mounted(t, nil)
	apply(t, b, 2, create(3, "status-bar"), prop(3, "text", "Saving"), insert(2, 3, 0))
	tt := ui.NewTester(b.View, 400, 200)
	widgetTexts(t, tt, []string{"Saving"}, nil)
	apply(t, b, 3, prop(3, "text", "Saved"))
	tt.Frame()
	widgetTexts(t, tt, []string{"Saved"}, []string{"Saving"})
	apply(t, b, 4, Operation{Op: "remove-prop", ID: 3, Property: "text"})
	tt.Frame()
	widgetTexts(t, tt, nil, []string{"Saved"})
}

func TestCompositesRowActionsHaveKeyboardAccessibleDesktopPath(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "list"), insert(2, 3, 0), create(4, "list-item"), prop(4, "text", "Draft document"), prop(4, "press-enabled", true), insert(3, 4, 0),
		create(5, "swipe-actions"), insert(4, 5, 0), create(6, "swipe-action"), prop(6, "text", "Delete draft"), prop(6, "variant", "destructive"), prop(6, "edge", "trailing"), prop(6, "press-enabled", true), insert(5, 6, 0),
		create(7, "swipe-action"), prop(7, "text", "Unavailable action"), prop(7, "enabled", false), prop(7, "edge", "trailing"), prop(7, "press-enabled", true), insert(5, 7, 1))
	tt := ui.NewTester(b.View, 600, 320)
	widgetClick(t, tt, "Draft document")
	tt.Key(ui.Shift, ui.KeyF10)
	if !widgetMenuHas(tt, "Delete draft") {
		t.Fatalf("row actions have no keyboard-discoverable desktop path: %v", tt.Texts())
	}
	widgetMenuChoose(t, tt, "Delete draft")
	if widgetCount(events, "press", 6) != 1 {
		t.Fatal("row action must target retained action exactly once")
	}
	if widgetCount(events, "press", 7) != 0 {
		t.Fatal("disabled row action dispatched")
	}
	apply(t, b, 3, Operation{Op: "detach-subtree", ID: 5})
	tt.Frame()
	tt.Key(ui.Shift, ui.KeyF10)
	if widgetMenuHas(tt, "Delete draft") {
		t.Fatal("removed row action remained active")
	}
}
