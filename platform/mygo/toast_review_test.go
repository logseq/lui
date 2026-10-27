package luimygo

import (
	"testing"
	"time"

	"github.com/egoist/mygo/ui"
)

func TestMenusToastFocusPauseEscapeAndRemountLifetime(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	mount := func(generation int64) {
		apply(t, b, generation, create(3, "toast"), prop(3, "duration", 1000), prop(3, "accessibility-label", "Saved"), insert(2, 3, 0),
			create(4, "text"), prop(4, "text", "Focus notification"), insert(3, 4, 0),
			create(5, "button"), prop(5, "text", "Notification action"), prop(5, "press-enabled", true), insert(3, 5, 1))
	}
	mount(2)
	tt := ui.NewTester(b.View, 600, 400)
	tt.SetFocused(true)
	tt.Advance(400 * time.Millisecond)
	widgetClick(t, tt, "Notification action")
	tt.Move(0, 0)
	tt.Advance(2 * time.Second)
	widgetTexts(t, tt, []string{"Focus notification"}, nil)
	if widgetCount(events, "dismiss", 3) != 0 || !tt.Focused("Notification action") {
		t.Fatal("keyboard focus failed to pause the retained toast")
	}
	tt.Key(0, ui.KeyEscape)
	tt.Frame()
	widgetTexts(t, tt, nil, []string{"Focus notification"})
	if widgetCount(events, "dismiss", 3) != 1 {
		t.Fatalf("Escape must dismiss the focused toast exactly once: %+v", events)
	}
	apply(t, b, 3, Operation{Op: "detach-subtree", ID: 3})
	mount(4)
	tt.Frame()
	tt.ClickAt(0, 0)
	tt.Advance(999 * time.Millisecond)
	widgetTexts(t, tt, []string{"Focus notification"}, nil)
	tt.Advance(time.Millisecond)
	widgetTexts(t, tt, nil, []string{"Focus notification"})
	if widgetCount(events, "dismiss", 3) != 2 {
		t.Fatalf("fresh incarnation did not get its own timeout: %+v", events)
	}
}

func TestMenusMultipleToastsKeepIndependentLifetimes(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2,
		create(3, "toast"), prop(3, "duration", 1000), prop(3, "accessibility-label", "Short notification"), insert(2, 3, 0),
		create(4, "text"), prop(4, "text", "Short notification body"), insert(3, 4, 0),
		create(5, "toast"), prop(5, "duration", 0), prop(5, "accessibility-label", "Persistent notification"), insert(2, 5, 1),
		create(6, "text"), prop(6, "text", "Persistent notification body"), insert(5, 6, 0))
	tt := ui.NewTester(b.View, 600, 400)
	tt.SetFocused(true)
	tt.Frame()
	widgetTexts(t, tt, []string{"Short notification body", "Persistent notification body"}, nil)
	tt.Advance(time.Second)
	widgetTexts(t, tt, []string{"Persistent notification body"}, []string{"Short notification body"})
	if widgetCount(events, "dismiss", 3) != 1 || widgetCount(events, "dismiss", 5) != 0 {
		t.Fatalf("one timer dismissed its sibling: %+v", events)
	}
	apply(t, b, 3, Operation{Op: "detach-subtree", ID: 3})
	tt.Frame()
	tt.Advance(10 * time.Second)
	widgetTexts(t, tt, []string{"Persistent notification body"}, nil)
	apply(t, b, 4, Operation{Op: "detach-subtree", ID: 5})
	tt.Frame()
	if widgetCount(events, "dismiss", 3) != 1 || widgetCount(events, "dismiss", 5) != 0 {
		t.Fatal("application disposal emitted a late user dismissal")
	}
}

func TestMenusToastNewNodeReplacementKeepsIndependentDeadlines(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2,
		create(3, "toast"), prop(3, "duration", 500), insert(2, 3, 0), create(4, "text"), prop(4, "text", "Original notification"), insert(3, 4, 0),
		create(5, "toast"), prop(5, "duration", 800), insert(2, 5, 1), create(6, "text"), prop(6, "text", "Unrelated notification"), insert(5, 6, 0))
	tt := ui.NewTester(b.View, 600, 400)
	tt.SetFocused(true)
	tt.Advance(200 * time.Millisecond)
	apply(t, b, 3, Operation{Op: "detach-subtree", ID: 3}, create(7, "toast"), prop(7, "duration", 1000), insert(2, 7, 0),
		create(8, "text"), prop(8, "text", "Replacement notification"), insert(7, 8, 0))
	tt.Frame()
	tt.Advance(300 * time.Millisecond)
	widgetTexts(t, tt, []string{"Replacement notification", "Unrelated notification"}, []string{"Original notification"})
	if widgetCount(events, "dismiss", 3) != 0 || widgetCount(events, "dismiss", 7) != 0 {
		t.Fatalf("old timer dismissed a replacement: %+v", events)
	}
	tt.Advance(300 * time.Millisecond)
	widgetTexts(t, tt, []string{"Replacement notification"}, []string{"Unrelated notification"})
	if widgetCount(events, "dismiss", 5) != 1 {
		t.Fatal("replacement restarted the unrelated timer")
	}
	tt.Advance(400 * time.Millisecond)
	widgetTexts(t, tt, nil, []string{"Replacement notification"})
	if widgetCount(events, "dismiss", 7) != 1 || widgetCount(events, "dismiss", 3) != 0 {
		t.Fatalf("replacement must own exactly one new deadline: %+v", events)
	}
}
