package luimygo

import (
	"testing"

	"github.com/egoist/mygo/ui"
)

// Native menus and retained custom-content menus are both valid host routes.
func widgetMenuChoose(t *testing.T, tt *ui.Tester, path ...string) {
	t.Helper()
	if len(tt.Menu()) > 0 {
		if err := tt.ChooseMenuItem(path...); err != nil {
			t.Fatal(err)
		}
		return
	}
	for _, text := range path {
		widgetClick(t, tt, text)
	}
}
func widgetMenuHas(tt *ui.Tester, text string) bool {
	if tt.HasText(text) {
		return true
	}
	for _, label := range tt.Menu() {
		if label == text {
			return true
		}
	}
	return false
}

func TestMenusDropdownRetainedItemsAndDismissal(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "dropdown-menu"), prop(3, "x", 30.0), prop(3, "y", 40.0), insert(2, 3, 0),
		create(4, "menu-item"), prop(4, "text", "Production"), prop(4, "selected", true), prop(4, "press-enabled", true), insert(3, 4, 0),
		create(5, "menu-item"), prop(5, "text", "Development"), prop(5, "enabled", false), prop(5, "press-enabled", true), insert(3, 5, 1))
	tt := ui.NewTester(b.View, 500, 300)
	if !widgetMenuHas(tt, "Production") {
		t.Fatalf("retained menu did not appear: %v", tt.Texts())
	}
	widgetMenuChoose(t, tt, "Production")
	widgetLast(t, events, "press", 4)
	apply(t, b, 3, prop(4, "text", "Staging"))
	tt.Frame()
	if !widgetMenuHas(tt, "Staging") {
		t.Fatal("menu failed to apply retained item update")
	}
	tt.Key(0, ui.KeyEscape)
	if widgetCount(events, "dismiss", 3) != 1 {
		t.Fatalf("Escape must dismiss once: %+v", events)
	}
	apply(t, b, 4, Operation{Op: "detach-subtree", ID: 3})
	tt.Frame()
	if widgetMenuHas(tt, "Staging") {
		t.Fatal("detached menu is still displayed")
	}
	before := len(events)
	tt.Key(0, ui.KeyEscape)
	if len(events) != before {
		t.Fatal("disposed menu dispatched dismissal")
	}
}

func TestMenusDropdownKeyboardSkipsDisabledItems(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "dropdown-menu"), prop(3, "x", 20.0), prop(3, "y", 20.0), insert(2, 3, 0),
		create(4, "menu-item"), prop(4, "text", "First action"), prop(4, "press-enabled", true), insert(3, 4, 0),
		create(5, "menu-item"), prop(5, "text", "Disabled action"), prop(5, "enabled", false), prop(5, "press-enabled", true), insert(3, 5, 1),
		create(6, "menu-item"), prop(6, "text", "Last action"), prop(6, "press-enabled", true), insert(3, 6, 2))
	tt := ui.NewTester(b.View, 500, 300)
	tt.Key(0, ui.KeyHome)
	tt.Key(0, ui.KeyDown)
	tt.Key(0, ui.KeyEnter)
	widgetLast(t, events, "press", 6)
	if widgetCount(events, "press", 5) != 0 {
		t.Fatal("disabled menu item activated")
	}
}

func TestMenusContextMenuOnLeafHostRoutesPerItem(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "text-field"), prop(3, "text", "Document"), prop(3, "placeholder", "Document editor"), insert(2, 3, 0),
		create(4, "context-menu"), insert(3, 4, 0), create(5, "menu-item"), prop(5, "text", "Inspect document"), prop(5, "press-enabled", true), insert(4, 5, 0))
	tt := ui.NewTester(b.View, 500, 300)
	if widgetMenuHas(tt, "Inspect document") {
		t.Fatal("context menu appeared before context request")
	}
	if err := tt.RightClick("Document editor"); err != nil {
		t.Fatal(err)
	}
	if !widgetMenuHas(tt, "Inspect document") {
		t.Fatal("context request failed to show retained child menu")
	}
	widgetMenuChoose(t, tt, "Inspect document")
	widgetLast(t, events, "press", 5)
	if widgetCount(events, "press", 3) != 0 {
		t.Fatal("menu selection leaked a parent activation")
	}
}

func TestMenusSubmenuUsesRetainedTriggerAndChildHandlers(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "dropdown-menu"), prop(3, "x", 20.0), prop(3, "y", 20.0), insert(2, 3, 0),
		create(4, "menu-trigger"), prop(4, "text", "More environments"), insert(3, 4, 0), create(5, "dropdown-menu"), insert(4, 5, 0),
		create(6, "menu-item"), prop(6, "text", "Production region"), prop(6, "press-enabled", true), insert(5, 6, 0))
	tt := ui.NewTester(b.View, 600, 400)
	widgetMenuChoose(t, tt, "More environments", "Production region")
	if widgetCount(events, "press", 6) != 1 {
		t.Fatalf("submenu failed to route child exactly once: %+v", events)
	}
	apply(t, b, 3, Operation{Op: "detach-subtree", ID: 4})
	tt.Frame()
	if widgetMenuHas(tt, "Production region") {
		t.Fatal("removed submenu survived")
	}
}

func TestMenusSelectAndComboboxKeepModelOwnedMenuLifecycle(t *testing.T) {
	for _, kind := range []string{"select", "combobox"} {
		t.Run(kind, func(t *testing.T) {
			var events []Event
			b := mounted(t, func(e Event) error { events = append(events, e); return nil })
			apply(t, b, 2, create(3, kind), prop(3, "text", "Production"), prop(3, "placeholder", "Environment"), prop(3, "press-enabled", true), prop(3, "submit-enabled", true), insert(2, 3, 0))
			tt := ui.NewTester(b.View, 500, 320)
			target := "Production"
			if kind == "combobox" {
				target = "Environment"
			}
			widgetClick(t, tt, target)
			widgetLast(t, events, "press", 3)
			apply(t, b, 3, create(4, "dropdown-menu"), prop(4, "x", 20.0), prop(4, "y", 70.0), insert(2, 4, 1), create(5, "menu-item"), prop(5, "text", "Staging"), prop(5, "press-enabled", true), insert(4, 5, 0))
			tt.Frame()
			widgetMenuChoose(t, tt, "Staging")
			widgetLast(t, events, "press", 5)
			n, _ := b.Node(3)
			if n.String("text") != "Production" {
				t.Fatal("host stole model-owned selection")
			}
			apply(t, b, 4, prop(3, "text", "Staging"), Operation{Op: "detach-subtree", ID: 4})
			tt.Frame()
			widgetTexts(t, tt, []string{"Staging"}, nil)
		})
	}
}

func TestMenusTooltipStaticAndAnchoredLifecycle(t *testing.T) {
	b := mounted(t, nil)
	apply(t, b, 2, create(3, "column"), insert(2, 3, 0), create(4, "button"), prop(4, "text", "Edit document"), insert(3, 4, 0),
		create(5, "tooltip"), prop(5, "text", "Edit help"), prop(5, "anchor", "above"), prop(5, "tooltip-delay", 0), insert(3, 5, 1),
		create(6, "tooltip"), prop(6, "text", "Saved status"), insert(2, 6, 1))
	tt := ui.NewTester(b.View, 500, 320)
	widgetTexts(t, tt, []string{"Saved status"}, []string{"Edit help"})
	r, ok := tt.Find("Edit document")
	if !ok {
		t.Fatal("missing tooltip anchor")
	}
	tt.Move(r.X+r.W/2, r.Y+r.H/2)
	tt.Frame()
	widgetTexts(t, tt, []string{"Edit help"}, nil)
	apply(t, b, 3, prop(5, "text", "Updated help"))
	tt.Frame()
	widgetTexts(t, tt, []string{"Updated help"}, []string{"Edit help"})
	apply(t, b, 4, Operation{Op: "detach-subtree", ID: 4}, Operation{Op: "detach-subtree", ID: 5})
	tt.Frame()
	widgetTexts(t, tt, []string{"Saved status"}, []string{"Updated help"})
}

func TestMenusToastContentUpdateActionsAndDisposal(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "toast"), prop(3, "duration", 0), prop(3, "accessibility-label", "Draft saved"), insert(2, 3, 0),
		create(4, "text"), prop(4, "text", "Saved draft"), insert(3, 4, 0),
		create(5, "button"), prop(5, "text", "Undo save"), prop(5, "press-enabled", true), insert(3, 5, 1))
	tt := ui.NewTester(b.View, 640, 400)
	widgetTexts(t, tt, []string{"Saved draft", "Undo save"}, nil)
	widgetClick(t, tt, "Undo save")
	if widgetCount(events, "press", 5) != 1 {
		t.Fatal("toast action did not route retained child handler")
	}
	apply(t, b, 3, prop(4, "text", "Draft restored"))
	tt.Frame()
	widgetTexts(t, tt, []string{"Draft restored"}, []string{"Saved draft"})
	apply(t, b, 4, Operation{Op: "detach-subtree", ID: 3})
	tt.Frame()
	widgetTexts(t, tt, nil, []string{"Draft restored", "Undo save"})
	before := len(events)
	tt.Frame()
	if len(events) != before {
		t.Fatal("disposed notification emitted event")
	}
}
