package luimygo

import (
	"math"
	"testing"

	"github.com/egoist/mygo/ui"
)

func widgetTesterBounds(b *Backend, width, height int) (*ui.Tester, func(int64) ui.Rect) {
	boxes := map[int64]ui.Rect{}
	tt := ui.NewTester(func(c *ui.Context) {
		b.View(c)
		c.AfterFrame(func() {
			for id, state := range b.states {
				boxes[id] = state.handle.Bounds(c)
			}
		})
	}, width, height)
	return tt, func(id int64) ui.Rect { return boxes[id] }
}

func TestOverlaysPopoverResolvesForwardAndBackwardAnchors(t *testing.T) {
	for _, forward := range []bool{false, true} {
		t.Run(map[bool]string{false: "backward", true: "forward"}[forward], func(t *testing.T) {
			b := mounted(t, nil)
			popupIndex, targetIndex := 1, 0
			if forward {
				popupIndex, targetIndex = 0, 1
			}
			apply(t, b, 2, create(3, "button"), prop(3, "text", "Anchor target"), prop(3, "accessibility-identifier", "target"), prop(3, "width", 120), prop(3, "height", 40),
				create(4, "popover"), prop(4, "anchor", "below"), prop(4, "anchor-target", "target"), prop(4, "anchor-alignment", "start"), prop(4, "anchor-offset", 6.0), prop(4, "width", 100), prop(4, "height", 50),
				create(5, "text"), prop(5, "text", "Popup body"), insert(4, 5, 0))
			if popupIndex < targetIndex {
				apply(t, b, 3, insert(2, 4, 0), insert(2, 3, 1))
			} else {
				apply(t, b, 3, insert(2, 3, 0), insert(2, 4, 1))
			}
			tt, box := widgetTesterBounds(b, 700, 500)
			target, ok := tt.Find("Anchor target")
			if !ok {
				t.Fatal("missing anchor")
			}
			popup := box(4)
			if popup.W == 0 {
				t.Fatal("missing anchored popup")
			}
			if popup.Y < target.Y+target.H || math.Abs(float64(popup.X-12)) > 2 {
				t.Fatalf("popover did not resolve target in either build order: target=%+v popup=%+v", target, popup)
			}
			apply(t, b, 4, prop(3, "height", 80))
			tt.Frame()
			moved := box(4)
			if moved.Y <= popup.Y+20 {
				t.Fatalf("anchor geometry update did not reposition popup: old=%+v new=%+v", popup, moved)
			}
			apply(t, b, 5, Operation{Op: "detach-subtree", ID: 3})
			tt.Frame()
			widgetTexts(t, tt, nil, []string{"Popup body"})
		})
	}
}

func TestOverlaysPopoverRectanglePointAndCollisionBounds(t *testing.T) {
	b := mounted(t, nil)
	apply(t, b, 2, create(3, "popover"), prop(3, "anchor", "below"), prop(3, "anchor-rect", "100 80 50 20"), prop(3, "anchor-alignment", "start"), prop(3, "anchor-offset", 6.0), prop(3, "width", 100), prop(3, "height", 50), insert(2, 3, 0), create(4, "text"), prop(4, "text", "Popup body"), insert(3, 4, 0))
	tt, box := widgetTesterBounds(b, 700, 500)
	r := box(3)
	if r.W == 0 {
		t.Fatal("missing rectangle-anchored popup")
	}
	if math.Abs(float64(r.X-100)) > 1 || math.Abs(float64(r.Y-106)) > 1 {
		t.Fatalf("frozen rectangle/offset lost: %+v", r)
	}
	apply(t, b, 3, Operation{Op: "remove-prop", ID: 3, Property: "anchor-rect"}, Operation{Op: "remove-prop", ID: 3, Property: "anchor"}, Operation{Op: "remove-prop", ID: 3, Property: "anchor-alignment"}, Operation{Op: "remove-prop", ID: 3, Property: "anchor-offset"}, prop(3, "x", 699.0), prop(3, "y", 499.0), prop(3, "collision-padding", 8.0))
	tt.Frame()
	r = box(3)
	if r.W == 0 {
		t.Fatal("missing point popup")
	}
	if r.X < 8 || r.Y < 8 || r.X+r.W > 692 || r.Y+r.H > 492 {
		t.Fatalf("popup escaped viewport collision padding: %+v", r)
	}
}

func TestOverlaysPopoverDismissalIsControlledAndExactlyOnce(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "button"), prop(3, "text", "Outside action"), prop(3, "press-enabled", true), insert(2, 3, 0), create(4, "popover"), prop(4, "x", 200.0), prop(4, "y", 100.0), insert(2, 4, 1), create(5, "button"), prop(5, "text", "Inside popup"), prop(5, "press-enabled", true), insert(4, 5, 0))
	tt := ui.NewTester(b.View, 700, 500)
	widgetClick(t, tt, "Inside popup")
	widgetLast(t, events, "press", 5)
	widgetClick(t, tt, "Outside action")
	widgetLast(t, events, "press", 3)
	if widgetCount(events, "dismiss", 4) != 1 {
		t.Fatalf("outside must propose dismissal once: %+v", events)
	}
	tt.Key(0, ui.KeyEscape)
	tt.Frame()
	if widgetCount(events, "dismiss", 4) != 1 {
		t.Fatal("same retained popup dismissed twice before reducer removal")
	}
	apply(t, b, 3, Operation{Op: "detach-subtree", ID: 4})
	tt.Frame()
	widgetTexts(t, tt, nil, []string{"Inside popup"})
}

func TestOverlaysDrawerKeepsMainAndControlledLeadingSidebar(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "drawer"), prop(3, "text", "Navigation"), prop(3, "selected", false), prop(3, "toggle-enabled", true), prop(3, "width", 600), prop(3, "height", 300), insert(2, 3, 0),
		create(4, "button"), prop(4, "text", "Main workspace"), prop(4, "press-enabled", true), insert(3, 4, 0), create(5, "button"), prop(5, "text", "Sidebar item"), prop(5, "press-enabled", true), insert(3, 5, 1))
	tt := ui.NewTester(b.View, 700, 500)
	widgetTexts(t, tt, []string{"Main workspace"}, []string{"Sidebar item"})
	apply(t, b, 3, prop(3, "selected", true))
	tt.Frame()
	widgetTexts(t, tt, []string{"Main workspace", "Sidebar item"}, nil)
	sidebar, _ := tt.Find("Sidebar item")
	main, _ := tt.Find("Main workspace")
	if sidebar.X >= main.X {
		t.Fatalf("sidebar must lead main content: sidebar=%+v main=%+v", sidebar, main)
	}
	widgetClick(t, tt, "Main workspace")
	tt.Key(0, ui.KeyEscape)
	if widgetLast(t, events, "toggle-changed", 3).Checked {
		t.Fatal("Escape must propose closing sidebar")
	}
	n, _ := b.Node(3)
	if !n.Bool("selected") {
		t.Fatal("drawer stole model-owned selection")
	}
	apply(t, b, 4, prop(3, "selected", false))
	tt.Frame()
	widgetTexts(t, tt, []string{"Main workspace"}, []string{"Sidebar item"})
}

func TestOverlaysSheetUsesBottomPresentationAndDetentHeight(t *testing.T) {
	b := mounted(t, nil)
	apply(t, b, 2, create(3, "sheet"), prop(3, "text", "Share sheet"), prop(3, "detents", "medium,large"), prop(3, "width", 400), insert(2, 3, 0), create(4, "text"), prop(4, "text", "Sheet body"), insert(3, 4, 0))
	tt := ui.NewTester(b.View, 700, 500)
	r, ok := tt.Find("Share sheet")
	if !ok {
		t.Fatal("missing sheet")
	}
	if r.Y < 250 || r.Y > 300 {
		t.Fatalf("medium sheet must occupy bottom half: %+v", r)
	}
	apply(t, b, 3, prop(3, "detents", "0.8"))
	tt.Frame()
	previousY := r.Y
	r, _ = tt.Find("Share sheet")
	if math.Abs(float64(previousY-r.Y-150)) > 2 {
		t.Fatalf("fractional detent was not applied: %+v", r)
	}
}

func TestOverlaysDialogTrapsAndRestoresFocus(t *testing.T) {
	b := mounted(t, nil)
	apply(t, b, 2, create(3, "button"), prop(3, "text", "Open dialog"), insert(2, 3, 0))
	tt := ui.NewTester(b.View, 700, 500)
	widgetClick(t, tt, "Open dialog")
	apply(t, b, 3, create(4, "dialog"), prop(4, "text", "Confirm operation"), insert(2, 4, 1), create(5, "button"), prop(5, "text", "Modal action"), insert(4, 5, 0))
	tt.Frame()
	if !tt.Focused("Modal action") {
		t.Fatal("dialog did not move focus inside")
	}
	tt.Key(0, ui.KeyTab)
	if !tt.Focused("Modal action") {
		t.Fatal("Tab escaped modal focus boundary")
	}
	apply(t, b, 4, Operation{Op: "detach-subtree", ID: 4})
	tt.Frame()
	if !tt.Focused("Open dialog") {
		t.Fatal("dialog disposal failed to restore opener focus")
	}
}

func TestOverlaysNestedEscapeDismissesTopBeforeOuter(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "dialog"), prop(3, "text", "Outer dialog"), insert(2, 3, 0), create(4, "button"), prop(4, "text", "Outer action"), insert(3, 4, 0), create(5, "popover"), prop(5, "x", 200.0), prop(5, "y", 150.0), insert(3, 5, 1), create(6, "button"), prop(6, "text", "Inner action"), insert(5, 6, 0))
	tt := ui.NewTester(b.View, 700, 500)
	widgetClick(t, tt, "Inner action")
	tt.Key(0, ui.KeyEscape)
	if widgetCount(events, "dismiss", 5) != 1 || widgetCount(events, "dismiss", 3) != 0 {
		t.Fatalf("Escape must reach top popup only: %+v", events)
	}
	tt.Key(0, ui.KeyEscape)
	if widgetCount(events, "dismiss", 5) != 1 || widgetCount(events, "dismiss", 3) != 0 {
		t.Fatalf("delayed reducer removal leaked Escape to outer modal: %+v", events)
	}
	apply(t, b, 3, Operation{Op: "detach-subtree", ID: 5})
	tt.Frame()
	tt.Key(0, ui.KeyEscape)
	if widgetCount(events, "dismiss", 3) != 1 {
		t.Fatalf("outer dialog did not dismiss after popup removal: %+v", events)
	}
}

func TestOverlaysForwardPopoverStretchMatchesAnchorWidth(t *testing.T) {
	b := mounted(t, nil)
	apply(t, b, 2, create(3, "popover"), prop(3, "anchor", "below"), prop(3, "anchor-target", "late"), prop(3, "anchor-alignment", "stretch"), insert(2, 3, 0), create(4, "text"), prop(4, "text", "Short"), insert(3, 4, 0),
		create(5, "button"), prop(5, "text", "Late anchor"), prop(5, "accessibility-identifier", "late"), prop(5, "width", 220), insert(2, 5, 1))
	tt, box := widgetTesterBounds(b, 700, 500)
	if math.Abs(float64(box(3).W-box(5).W)) > 1 {
		t.Fatalf("forward stretch width: popup=%+v target=%+v", box(3), box(5))
	}
	apply(t, b, 3, prop(5, "width", 160))
	tt.Frame()
	if math.Abs(float64(box(3).W-160)) > 1 {
		t.Fatalf("updated stretch width: %+v", box(3))
	}
}

func TestOverlaysSideAnchorsRespectCrossAlignment(t *testing.T) {
	for _, side := range []string{"left", "right"} {
		for _, alignment := range []string{"start", "center", "end"} {
			t.Run(side+"/"+alignment, func(t *testing.T) {
				b := mounted(t, nil)
				apply(t, b, 2, create(3, "popover"), prop(3, "anchor", side), prop(3, "anchor-rect", "300 120 80 100"), prop(3, "anchor-alignment", alignment), prop(3, "width", 100), prop(3, "height", 40), insert(2, 3, 0))
				_, box := widgetTesterBounds(b, 800, 500)
				r := box(3)
				wantY := float32(120)
				if alignment == "center" {
					wantY = 150
				}
				if alignment == "end" {
					wantY = 180
				}
				if math.Abs(float64(r.Y-wantY)) > 1 {
					t.Fatalf("side popup alignment %s: %+v want y%v", alignment, r, wantY)
				}
				if side == "left" && r.X+r.W > 301 || side == "right" && r.X < 379 {
					t.Fatalf("side popup placed on wrong side: %+v", r)
				}
			})
		}
	}
}
