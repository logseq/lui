package luimygo

import (
	"fmt"
	"testing"

	"github.com/egoist/mygo/ui"
)

func TestPressPhysicalModifiers(t *testing.T) {
	// Alt is not part of LUI's modifier mask; bit eight is the secondary
	// pointer button. A platform shortcut alias must not turn Ctrl into Meta.
	for mask := 0; mask < 16; mask++ {
		t.Run(fmt.Sprint(mask), func(t *testing.T) {
			var mods ui.Modifiers
			for bit, modifier := range []ui.Modifiers{ui.Ctrl, ui.Shift, ui.Super, ui.Alt} {
				if mask&(1<<bit) != 0 {
					mods |= modifier
				}
			}
			var events []Event
			b := mounted(t, func(e Event) error { events = append(events, e); return nil })
			apply(t, b, 2, create(3, "button"), prop(3, "text", "Physical modifiers"), prop(3, "press-enabled", true), prop(3, "pointer-enabled", true), insert(2, 3, 0))
			tester := ui.NewTester(b.View, 300, 120)
			if err := tester.ClickWith(mods, "Physical modifiers"); err != nil {
				t.Fatal(err)
			}
			want := int32(mask & 7)
			pressKind := "press"
			if want != 0 {
				pressKind = "press-modifiers"
			}
			seen := make(map[string]int)
			for _, event := range events {
				switch event.Kind {
				case "pointer-down", "pointer-up", "press-detail", pressKind:
					seen[event.Kind]++
					if event.Modifiers != want {
						t.Errorf("%s physical modifiers %d: got %d, want %d", event.Kind, mask, event.Modifiers, want)
					}
				}
			}
			for _, kind := range []string{"pointer-down", "pointer-up", "press-detail", pressKind} {
				if seen[kind] != 1 {
					t.Errorf("got %d %s events, want one: %+v", seen[kind], kind, events)
				}
			}
		})
	}
}
