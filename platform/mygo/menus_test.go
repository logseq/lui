package luimygo

import (
	"testing"
	"time"

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
	press, dismiss := -1, -1
	for i, event := range events {
		if event.Kind == "press" && event.Node == 5 {
			press = i
		}
		if event.Kind == "dismiss" && event.Node == 4 {
			dismiss = i
		}
	}
	if press < 0 || dismiss <= press {
		t.Fatalf("native choice must dispatch press before dismissal: %+v", events)
	}
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
			apply(t, b, 2, create(3, kind), prop(3, "text", "Production"), prop(3, "placeholder", "Environment"), prop(3, "press-enabled", true), insert(2, 3, 0))
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
			if kind == "combobox" {
				widgetClick(t, tt, "Environment")
				tt.Key(0, ui.KeyEnd)
				tt.Type("!")
				if got := widgetLast(t, events, "text-changed", 3).Text; got != "Staging!" {
					t.Fatalf("combobox failed to reconcile choice: %q", got)
				}
			} else {
				widgetTexts(t, tt, []string{"Staging"}, nil)
			}
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

func TestMenusTooltipDelayUpdateEscapeAndAnchorRemoval(t *testing.T) {
	b := mounted(t, nil)
	apply(t, b, 2, create(3, "column"), insert(2, 3, 0), create(4, "button"), prop(4, "text", "Edit document"), insert(3, 4, 0), create(5, "tooltip"), prop(5, "text", "Original help"), prop(5, "anchor", "above"), prop(5, "tooltip-delay", 250), insert(3, 5, 1))
	tt := ui.NewTester(b.View, 500, 320)
	r, _ := tt.Find("Edit document")
	tt.Move(r.X+r.W/2, r.Y+r.H/2)
	tt.Advance(125 * time.Millisecond)
	widgetTexts(t, tt, nil, []string{"Original help"})
	apply(t, b, 3, prop(5, "text", "Updated help"))
	tt.Frame()
	tt.Advance(124 * time.Millisecond)
	widgetTexts(t, tt, nil, []string{"Updated help"})
	tt.Advance(time.Millisecond)
	widgetTexts(t, tt, []string{"Updated help"}, []string{"Original help"})
	tt.Key(0, ui.KeyEscape)
	tt.Frame()
	widgetTexts(t, tt, nil, []string{"Updated help"})
	tt.Advance(time.Second)
	widgetTexts(t, tt, nil, []string{"Updated help"})
	tt.Move(490, 310)
	tt.Move(r.X+r.W/2, r.Y+r.H/2)
	tt.Advance(250 * time.Millisecond)
	widgetTexts(t, tt, []string{"Updated help"}, nil)
	apply(t, b, 4, Operation{Op: "detach-subtree", ID: 4})
	tt.Frame()
	widgetTexts(t, tt, nil, []string{"Updated help"})
}

func TestMenusToastTimeoutDoesNotRestartOnContentUpdate(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "toast"), prop(3, "duration", 1000), prop(3, "accessibility-label", "Draft saved"), insert(2, 3, 0), create(4, "text"), prop(4, "text", "Original notification"), insert(3, 4, 0))
	tt := ui.NewTester(b.View, 600, 400)
	tt.SetFocused(true)
	tt.Advance(400 * time.Millisecond)
	apply(t, b, 3, prop(4, "text", "Updated notification"), prop(3, "duration", 1000))
	tt.Frame()
	tt.Advance(599 * time.Millisecond)
	widgetTexts(t, tt, []string{"Updated notification"}, []string{"Original notification"})
	tt.Advance(time.Millisecond)
	if widgetCount(events, "dismiss", 3) != 1 {
		t.Fatalf("timeout must dismiss once at original deadline: %+v", events)
	}
	widgetTexts(t, tt, nil, []string{"Updated notification"})
	tt.Advance(time.Second)
	tt.Frame()
	if widgetCount(events, "dismiss", 3) != 1 {
		t.Fatal("retained expired toast rearmed itself")
	}
}

func TestMenusToastPausesForPointerAndDisposesWithoutLateDismiss(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "toast"), prop(3, "duration", 1000), prop(3, "accessibility-label", "Saved"), insert(2, 3, 0), create(4, "text"), prop(4, "text", "Pause this notification"), insert(3, 4, 0))
	tt := ui.NewTester(b.View, 600, 400)
	tt.SetFocused(true)
	r, ok := tt.Find("Pause this notification")
	if !ok {
		t.Fatal("missing notification")
	}
	tt.Move(r.X+r.W/2, r.Y+r.H/2)
	tt.Advance(2 * time.Second)
	widgetTexts(t, tt, []string{"Pause this notification"}, nil)
	if widgetCount(events, "dismiss", 3) != 0 {
		t.Fatal("hovered notification expired")
	}
	apply(t, b, 3, Operation{Op: "detach-subtree", ID: 3})
	tt.Frame()
	tt.Move(0, 0)
	tt.Advance(2 * time.Second)
	widgetTexts(t, tt, nil, []string{"Pause this notification"})
	if widgetCount(events, "dismiss", 3) != 0 {
		t.Fatal("disposed notification dispatched stale timer")
	}
}

func TestMenusNativeChoiceIgnoresReplacedRetainedItem(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "button"), prop(3, "text", "Document"), insert(2, 3, 0), create(4, "context-menu"), insert(3, 4, 0), create(5, "menu-item"), prop(5, "text", "Inspect"), prop(5, "press-enabled", true), insert(4, 5, 0))
	tt := ui.NewTester(b.View, 500, 300)
	if err := tt.RightClick("Document"); err != nil {
		t.Fatal(err)
	}
	apply(t, b, 3, Operation{Op: "detach-subtree", ID: 5}, create(5, "menu-item"), prop(5, "text", "Inspect"), prop(5, "press-enabled", true), insert(4, 5, 0))
	tt.Frame()
	if err := tt.ChooseMenuItem("Inspect"); err != nil {
		t.Fatal(err)
	}
	if widgetCount(events, "press", 5) != 0 {
		t.Fatalf("stale native choice activated replacement node: %+v", events)
	}
}

func TestMenusCheckedSelectionPlacement(t *testing.T) {
	b := mounted(t, nil)
	apply(t, b, 2, create(3, "menu-item"), prop(3, "text", "Selected action"), prop(3, "selected", true), prop(3, "selection-placement", "leading"), insert(2, 3, 0))
	tt := ui.NewTester(b.View, 600, 300)
	leading, ok := tt.Find("✓")
	if !ok {
		t.Fatal("selected menu item has no visible selection indicator")
	}
	apply(t, b, 3, prop(3, "selection-placement", "trailing"))
	tt.Frame()
	trailing, ok := tt.Find("✓")
	if !ok || trailing.X < leading.X+40 {
		t.Fatalf("selection mark did not move across its label: leading=%+v trailing=%+v", leading, trailing)
	}
}

func TestMenusNativeContextUsesInlineIconSnapshot(t *testing.T) {
	b := mounted(t, nil)
	apply(t, b, 2, create(3, "button"), prop(3, "text", "Document"), insert(2, 3, 0), create(4, "context-menu"), insert(3, 4, 0), create(5, "menu-item"), prop(5, "text", "Inspect"), prop(5, "icon", "folder"), prop(5, "press-enabled", true), insert(4, 5, 0))
	tt := ui.NewTester(b.View, 500, 300)
	if err := tt.RightClick("Document"); err != nil {
		t.Fatal(err)
	}
	if tt.MenuImage("Inspect") == nil {
		t.Fatal("native context menu ignored portable inline icon")
	}
	tt.CloseMenu()
	apply(t, b, 3, Operation{Op: "remove-prop", ID: 5, Property: "icon"})
	tt.Frame()
	tt.RightClick("Document")
	if tt.MenuImage("Inspect") != nil {
		t.Fatal("native context icon was retained after prop removal")
	}
}

func TestMenusContextPortableAppearanceUsesRetainedBehavior(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "button"), prop(3, "text", "Context host"), insert(2, 3, 0), create(4, "context-menu"), insert(3, 4, 0),
		create(5, "menu-item"), prop(5, "text", "Selected command"), prop(5, "selected", true), prop(5, "selection-placement", "trailing"), prop(5, "size", "lg"), prop(5, "font-size", "20px"), prop(5, "press-enabled", true), insert(4, 5, 0),
		create(6, "menu-item"), prop(6, "text", "Disabled command"), prop(6, "enabled", false), insert(4, 6, 1), create(7, "menu-item"), prop(7, "text", "Next command"), prop(7, "press-enabled", true), insert(4, 7, 2))
	tt, box := widgetTesterBounds(b, 600, 400)
	if err := tt.RightClick("Context host"); err != nil {
		t.Fatal(err)
	}
	check, ok := tt.Find("✓")
	if !ok {
		t.Fatal("portable native-menu presentation did not render custom check")
	}
	label, ok := tt.Find("Selected command")
	if !ok || check.X <= box(5).X+box(5).W*0.75 {
		t.Fatalf("trailing selection ignored: check=%+v label=%+v", check, label)
	}
	if box(5).H < 40 || label.H < 20 {
		t.Fatalf("native menu size/font ignored: item=%+v text=%+v", box(5), label)
	}
	tt.Key(0, ui.KeyDown)
	if !tt.Focused("Next command") {
		t.Fatal("custom context behavior did not skip disabled command")
	}
	tt.Key(0, ui.KeyEnter)
	widgetLast(t, events, "press", 7)
	if widgetCount(events, "dismiss", 4) != 1 {
		t.Fatalf("custom menu did not dismiss exactly once: %+v", events)
	}
	if tt.HasText("Selected command") {
		t.Fatal("custom menu remained after choice")
	}
	widgetClick(t, tt, "Context host")
	tt.Key(ui.Shift, ui.KeyF10)
	if !tt.HasText("Selected command") {
		t.Fatal("keyboard context path did not reopen retained presentation")
	}
	tt.Key(0, ui.KeyEscape)
	if widgetCount(events, "dismiss", 4) != 2 {
		t.Fatal("Escape did not dismiss reopened custom menu")
	}
}

func TestMenusRetainedContextClampsWindowAndUpdatesWhileOpen(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, prop(2, "height", 380), prop(2, "main", "end"), prop(2, "cross", "end"), create(3, "button"), prop(3, "text", "Corner host"), insert(2, 3, 0), create(4, "context-menu"), insert(3, 4, 0),
		create(5, "menu-item"), prop(5, "text", "Large portable command"), prop(5, "font-size", "24px"), insert(4, 5, 0), create(6, "menu-item"), prop(6, "text", "Last portable command"), insert(4, 6, 1))
	tt, box := widgetTesterBounds(b, 600, 400)
	tt.RightClick("Corner host")
	last := box(6)
	first := box(5)
	if first.X < 8 || last.X+last.W > 592 || last.Y+last.H > 392 {
		t.Fatalf("retained context escaped window: first=%+v last=%+v", first, last)
	}
	apply(t, b, 3, Operation{Op: "remove-prop", ID: 5, Property: "font-size"}, prop(5, "text", "Updated command"))
	tt.Frame()
	if !tt.HasText("Updated command") {
		t.Fatal("removing final custom prop lost the open retained presentation")
	}
	tt.ClickAt(20, 20)
	if widgetCount(events, "dismiss", 4) != 1 {
		t.Fatal("outside press did not dismiss exactly once")
	}
	tt.Frame()
	if widgetCount(events, "dismiss", 4) != 1 {
		t.Fatal("dismiss replayed")
	}
}

func TestMenusRetainedContextResetsSubmenusAcrossOpenings(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "button"), prop(3, "text", "Context submenu host"), insert(2, 3, 0), create(4, "context-menu"), insert(3, 4, 0),
		create(5, "menu-item"), prop(5, "text", "More portable commands"), insert(4, 5, 0), create(6, "dropdown-menu"), insert(5, 6, 0), create(7, "menu-item"), prop(7, "text", "Nested choice"), prop(7, "font-size", "20px"), prop(7, "press-enabled", true), insert(6, 7, 0))
	tt := ui.NewTester(b.View, 600, 400)
	tt.RightClick("Context submenu host")
	widgetClick(t, tt, "More portable commands")
	if !tt.HasText("Nested choice") {
		t.Fatal("retained context submenu did not open")
	}
	tt.Key(0, ui.KeyEscape)
	if tt.HasText("Nested choice") || !tt.HasText("More portable commands") {
		t.Fatal("nested Escape did not close only the submenu")
	}
	widgetClick(t, tt, "More portable commands")
	widgetClick(t, tt, "Nested choice")
	widgetLast(t, events, "press", 7)
	if widgetCount(events, "dismiss", 4) != 1 {
		t.Fatal("nested context selection did not dismiss owner")
	}
	tt.RightClick("Context submenu host")
	if tt.HasText("Nested choice") {
		t.Fatal("submenu reopened from stale presentation state")
	}
	apply(t, b, 3, Operation{Op: "detach-subtree", ID: 3})
	tt.Frame()
	tt.Key(0, ui.KeyEscape)
	if widgetCount(events, "dismiss", 4) != 1 {
		t.Fatal("retired custom menu produced stale dismissal")
	}
}

func TestMenusNativeContextMenuItemDropdownIsSubmenu(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "button"), prop(3, "text", "Native submenu host"), insert(2, 3, 0), create(4, "context-menu"), insert(3, 4, 0), create(5, "menu-item"), prop(5, "text", "More native commands"), insert(4, 5, 0), create(6, "dropdown-menu"), insert(5, 6, 0), create(7, "menu-item"), prop(7, "text", "Native nested choice"), prop(7, "press-enabled", true), insert(6, 7, 0))
	tt := ui.NewTester(b.View, 600, 400)
	tt.RightClick("Native submenu host")
	if err := tt.ChooseMenuItem("More native commands", "Native nested choice"); err != nil {
		t.Fatal(err)
	}
	widgetLast(t, events, "press", 7)
	if widgetCount(events, "dismiss", 4) != 1 {
		t.Fatal("native nested selection did not dismiss owner")
	}
}
