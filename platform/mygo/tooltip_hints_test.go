package luimygo

import (
	"testing"
	"time"

	"github.com/egoist/mygo/ui"
)

func TestMenusNativeTooltipIncludesShortcutAndUpdates(t *testing.T) {
	b := mounted(t, nil)
	apply(t, b, 2, create(3, "button"), prop(3, "text", "Find"), prop(3, "tooltip", "Search"), prop(3, "tooltip-keys", "Ctrl+K"), insert(2, 3, 0))
	tester := ui.NewTester(b.View, 400, 240)
	r, _ := tester.Find("Find")
	tester.Move(r.X+r.W/2, r.Y+r.H/2)
	tester.Advance(650 * time.Millisecond)
	if !tester.HasText("Search (Ctrl+K)") {
		t.Fatal("native tooltip omitted its key hint", tester.Texts())
	}
	apply(t, b, 3, prop(3, "tooltip-keys", "Cmd+F"))
	tester.Frame()
	if !tester.HasText("Search (Cmd+F)") {
		t.Fatal("tooltip hint did not update", tester.Texts())
	}
	apply(t, b, 4, Operation{Op: "remove-prop", ID: 3, Property: "tooltip-keys"})
	tester.Frame()
	if !tester.HasText("Search") || tester.HasText("Search (Cmd+F)") {
		t.Fatal("removed tooltip hint survived", tester.Texts())
	}
}
