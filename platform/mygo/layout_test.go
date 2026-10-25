package luimygo

import (
	"encoding/json"
	"math"
	"testing"

	"github.com/egoist/mygo/ui"
)

func layoutBackend(t *testing.T, kind string, events *[]Event, ops ...Operation) *Backend {
	t.Helper()
	config := Config{}
	if events != nil {
		config.Dispatch = func(e Event) error { *events = append(*events, e); return nil }
	}
	b := New(config)
	base := []Operation{create(1, "root"), prop(1, "cross", "start"), create(2, kind), insert(1, 2, 0)}
	apply(t, b, 1, append(base, ops...)...)
	return b
}

func layoutRect(t *testing.T, tester *ui.Tester, label string) ui.Rect {
	t.Helper()
	r, ok := tester.Find(label)
	if !ok {
		t.Fatalf("missing rendered element %q in %v", label, tester.Texts())
	}
	return r
}

func layoutNear(t *testing.T, description string, got, want float32) {
	t.Helper()
	if math.Abs(float64(got-want)) > 1 {
		t.Fatalf("%s: got %g, want %g", description, got, want)
	}
}

func layoutEventMap(t *testing.T, e Event) map[string]any {
	t.Helper()
	data, err := json.Marshal(e)
	if err != nil {
		t.Fatal(err)
	}
	var result map[string]any
	if err := json.Unmarshal(data, &result); err != nil {
		t.Fatal(err)
	}
	return result
}

func layoutEvents(events []Event, kind string, node int64) []Event {
	var result []Event
	for _, e := range events {
		if e.Kind == kind && e.Node == node {
			result = append(result, e)
		}
	}
	return result
}

func TestLayoutStackUsesLargestIntrinsicChildAndRetainsOrder(t *testing.T) {
	var events []Event
	b := layoutBackend(t, "stack", &events,
		prop(2, "accessibility-label", "layers"),
		create(3, "box"), prop(3, "width", 60), prop(3, "height", 20), prop(3, "background", "#ff0000"), prop(3, "accessibility-label", "small layer"), insert(2, 3, 0),
		create(4, "box"), prop(4, "width", 90), prop(4, "height", 70), prop(4, "background", "#0000ff"), prop(4, "accessibility-label", "large layer"), prop(4, "press-enabled", true), insert(2, 4, 1))
	tester := ui.NewTester(b.View, 400, 200)
	parent := layoutRect(t, tester, "layers")
	layoutNear(t, "intrinsic stack width", parent.W, 90)
	layoutNear(t, "intrinsic stack height", parent.H, 70)
	first, second := layoutRect(t, tester, "small layer"), layoutRect(t, tester, "large layer")
	if first.Y+first.H <= second.Y || second.Y+second.H <= first.Y {
		t.Fatal("stack children were laid out sequentially")
	}
	if err := tester.Click("large layer"); err != nil {
		t.Fatal(err)
	}
	if len(layoutEvents(events, "press", 4)) != 1 {
		t.Fatalf("top layer did not receive press: %+v", events)
	}
	apply(t, b, 2, Operation{Op: "detach-subtree", ID: 4})
	tester.Frame()
	parent = layoutRect(t, tester, "layers")
	layoutNear(t, "stack shrinks after removal", parent.H, 20)
	layoutNear(t, "stack shrinks horizontally after removal", parent.W, 60)
}

func TestLayoutOverlayUsesFirstChildSizeAndLocalAlignment(t *testing.T) {
	b := layoutBackend(t, "column", nil,
		create(3, "overlay"), prop(3, "accessibility-label", "local overlay"), prop(3, "alignment", "bottom-trailing"), insert(2, 3, 0),
		create(4, "box"), prop(4, "width", 120), prop(4, "height", 60), prop(4, "accessibility-label", "base"), insert(3, 4, 0),
		create(5, "box"), prop(5, "width", 300), prop(5, "height", 100), prop(5, "accessibility-label", "oversized overlay"), insert(3, 5, 1),
		create(6, "button"), prop(6, "text", "badge"), prop(6, "width", 40), prop(6, "height", 20), insert(3, 6, 2),
		create(7, "box"), prop(7, "width", 10), prop(7, "height", 10), prop(7, "accessibility-label", "following sibling"), insert(2, 7, 1))
	tester := ui.NewTester(b.View, 500, 300)
	parent, base, badge := layoutRect(t, tester, "local overlay"), layoutRect(t, tester, "base"), layoutRect(t, tester, "badge")
	layoutNear(t, "overlay width follows first child", parent.W, 120)
	layoutNear(t, "overlay height follows first child", parent.H, 60)
	layoutNear(t, "trailing alignment is local", badge.X+badge.W, base.X+base.W)
	layoutNear(t, "bottom alignment is local", badge.Y+badge.H, base.Y+base.H)
	layoutNear(t, "overlay does not consume sibling space", layoutRect(t, tester, "following sibling").Y, base.Y+60)
	apply(t, b, 2, prop(6, "alignment", "top-leading"))
	tester.Frame()
	badge = layoutRect(t, tester, "badge")
	layoutNear(t, "child alignment overrides parent", badge.X, base.X)
	layoutNear(t, "child alignment top", badge.Y, base.Y)
}

func TestLayoutEdgeInsetIncludesEveryPinnedChildAndVisibility(t *testing.T) {
	for _, edge := range []string{"top", "bottom", "leading", "trailing"} {
		t.Run(edge, func(t *testing.T) {
			b := layoutBackend(t, "edge-inset", nil,
				prop(2, "edge", edge), prop(2, "width", 200), prop(2, "height", 120), prop(2, "gap", 4),
				create(3, "box"), prop(3, "grow", 1), prop(3, "accessibility-label", "content"), insert(2, 3, 0),
				create(4, "box"), prop(4, "width", 20), prop(4, "height", 15), prop(4, "accessibility-label", "pinned one"), insert(2, 4, 1),
				create(5, "box"), prop(5, "width", 30), prop(5, "height", 25), prop(5, "accessibility-label", "pinned two"), insert(2, 5, 2))
			tester := ui.NewTester(b.View, 400, 300)
			a, z, content := layoutRect(t, tester, "pinned one"), layoutRect(t, tester, "pinned two"), layoutRect(t, tester, "content")
			if edge == "top" || edge == "bottom" {
				layoutNear(t, "pinned children stack along vertical edge", z.Y, a.Y+a.H)
				layoutNear(t, "content excludes full pinned region and gap", content.H, 76)
				if edge == "top" {
					layoutNear(t, "top inset offset", content.Y, z.Y+z.H+4)
				} else {
					layoutNear(t, "bottom inset offset", a.Y, content.Y+content.H+4)
				}
			} else {
				layoutNear(t, "pinned children stack along side edge", z.X, a.X+a.W)
				layoutNear(t, "content excludes full side region and gap", content.W, 146)
				if edge == "leading" {
					layoutNear(t, "leading inset offset", content.X, z.X+z.W+4)
				} else {
					layoutNear(t, "trailing inset offset", a.X, content.X+content.W+4)
				}
			}
			apply(t, b, 2, prop(2, "visible", false))
			tester.Frame()
			if _, ok := tester.Find("pinned one"); ok {
				t.Fatal("hidden pinned region remained visible")
			}
			content = layoutRect(t, tester, "content")
			layoutNear(t, "hidden inset restores content width", content.W, 200)
			layoutNear(t, "hidden inset restores content height", content.H, 120)
			apply(t, b, 3, Operation{Op: "remove-prop", ID: 2, Property: "visible"})
			tester.Frame()
			layoutRect(t, tester, "pinned two")
		})
	}
}

func TestLayoutViewThatFitsMeasuresLocalAxisWithoutCandidateEffects(t *testing.T) {
	var events []Event
	b := layoutBackend(t, "column", &events,
		prop(2, "width", 100),
		create(3, "view-that-fits"), prop(3, "width", 100), prop(3, "height", 50), insert(2, 3, 0),
		create(4, "text-field"), prop(4, "placeholder", "rejected wide editor"), prop(4, "width", 300), prop(4, "autofocus", true), prop(4, "appear-enabled", true), insert(3, 4, 0),
		create(5, "button"), prop(5, "text", "compact candidate"), prop(5, "width", 80), prop(5, "height", 40), prop(5, "appear-enabled", true), insert(3, 5, 1),
		create(6, "text-field"), prop(6, "placeholder", "stable editor"), insert(2, 6, 1))
	tester := ui.NewTester(b.View, 600, 300)
	if tester.HasText("rejected wide editor") || !tester.HasText("compact candidate") {
		t.Fatalf("selected candidate ignored local constraints: %v", tester.Texts())
	}
	if tester.Focused("rejected wide editor") || len(layoutEvents(events, "appear", 4)) != 0 {
		t.Fatalf("measurement activated rejected candidate: %+v", events)
	}
	if len(layoutEvents(events, "appear", 5)) != 1 {
		t.Fatalf("selected candidate appearance count: %+v", events)
	}
	if err := tester.Click("stable editor"); err != nil {
		t.Fatal(err)
	}
	tester.Frame()
	if !tester.Focused("stable editor") {
		t.Fatal("subsequent candidate probe stole focus")
	}
	apply(t, b, 2, prop(2, "width", 350), prop(3, "width", 350))
	tester.Frame()
	if !tester.HasText("rejected wide editor") || tester.HasText("compact candidate") {
		t.Fatal(tester.Texts())
	}
	if len(layoutEvents(events, "appear", 4)) != 1 {
		t.Fatalf("selected replacement appeared incorrectly: %+v", events)
	}
}

func TestLayoutViewThatFitsOnlyConstrainsSelectedAxisAndFallsBack(t *testing.T) {
	for _, vertical := range []bool{false, true} {
		t.Run(map[bool]string{false: "horizontal", true: "vertical"}[vertical], func(t *testing.T) {
			width, height := 80, 200
			orientation := "horizontal"
			if vertical {
				width, height, orientation = 200, 40, "vertical"
			}
			b := layoutBackend(t, "view-that-fits", nil,
				prop(2, "width", 100), prop(2, "height", 50), prop(2, "orientation", orientation),
				create(3, "box"), prop(3, "width", width), prop(3, "height", height), prop(3, "accessibility-label", "first candidate"), insert(2, 3, 0),
				create(4, "box"), prop(4, "width", 30), prop(4, "height", 20), prop(4, "accessibility-label", "last candidate"), insert(2, 4, 1))
			tester := ui.NewTester(b.View, 400, 300)
			layoutRect(t, tester, "first candidate")
			if _, ok := tester.Find("last candidate"); ok {
				t.Fatal("fitting first candidate was rejected for the other axis")
			}
			apply(t, b, 2, prop(3, "width", 200), prop(3, "height", 200), prop(4, "width", 150), prop(4, "height", 150))
			tester.Frame()
			layoutRect(t, tester, "last candidate")
			if _, ok := tester.Find("first candidate"); ok {
				t.Fatal("no-fit fallback must choose only last candidate")
			}
		})
	}
}

func TestLayoutSharedTypographyAndSpacingRestoreInheritedValues(t *testing.T) {
	b := layoutBackend(t, "column", nil,
		prop(2, "font-size", "24px"), prop(2, "foreground", "#0000ff"), prop(2, "gap", 10),
		create(3, "text"), prop(3, "text", "MMMM"), prop(3, "font-size", "12px"), prop(3, "letter-spacing", 8.0), insert(2, 3, 0),
		create(4, "text"), prop(4, "text", "following"), insert(2, 4, 1))
	tester := ui.NewTester(b.View, 400, 300)
	before := layoutRect(t, tester, "MMMM")
	apply(t, b, 2, Operation{Op: "remove-prop", ID: 3, Property: "letter-spacing"})
	tester.Frame()
	compact := layoutRect(t, tester, "MMMM")
	if compact.W >= before.W-12 {
		t.Fatalf("removing letter spacing did not reduce glyph advance: before=%+v after=%+v", before, compact)
	}
	apply(t, b, 3, Operation{Op: "remove-prop", ID: 3, Property: "font-size"}, Operation{Op: "remove-prop", ID: 2, Property: "gap"})
	tester.Frame()
	inherited := layoutRect(t, tester, "MMMM")
	if inherited.H <= compact.H*1.5 {
		t.Fatalf("removed font size did not restore inheritance: before=%+v after=%+v", compact, inherited)
	}
	layoutNear(t, "removed gap restores default spacing", layoutRect(t, tester, "following").Y, inherited.Y+inherited.H)
}

func TestLayoutGridSpansAndPropertyRemovalChangeGeometry(t *testing.T) {
	b := layoutBackend(t, "grid", nil,
		prop(2, "width", 200), prop(2, "columns", 2), prop(2, "gap", 0),
		create(3, "box"), prop(3, "height", 20), prop(3, "grid-column-span", 2), prop(3, "accessibility-label", "spanning"), insert(2, 3, 0),
		create(4, "box"), prop(4, "height", 20), prop(4, "accessibility-label", "next row"), insert(2, 4, 1))
	tester := ui.NewTester(b.View, 400, 200)
	first, second := layoutRect(t, tester, "spanning"), layoutRect(t, tester, "next row")
	layoutNear(t, "spanning width", first.W, 200)
	layoutNear(t, "next row starts below spanning child", second.Y, first.Y+20)
	apply(t, b, 2, Operation{Op: "remove-prop", ID: 3, Property: "grid-column-span"})
	tester.Frame()
	first, second = layoutRect(t, tester, "spanning"), layoutRect(t, tester, "next row")
	layoutNear(t, "removed span restores single column", first.W, 100)
	layoutNear(t, "next child returns to same row", second.Y, first.Y)
}

func TestLayoutSplitFractionPixelModesAndControlledResize(t *testing.T) {
	for _, pixelMode := range []bool{false, true} {
		t.Run(map[bool]string{false: "fraction", true: "pixels"}[pixelMode], func(t *testing.T) {
			var events []Event
			mode, initial := "value", 0.25
			if pixelMode {
				mode, initial = "first-pane-width", 100
			}
			b := layoutBackend(t, "split", &events,
				prop(2, "width", 408), prop(2, "height", 100), prop(2, "gap", 8), prop(2, mode, initial), prop(2, "resize-handle-width", 8), prop(2, "change-enabled", true),
				create(3, "box"), prop(3, "accessibility-label", "first pane"), insert(2, 3, 0),
				create(4, "box"), prop(4, "accessibility-label", "second pane"), insert(2, 4, 1))
			tester := ui.NewTester(b.View, 500, 200)
			first, second := layoutRect(t, tester, "first pane"), layoutRect(t, tester, "second pane")
			layoutNear(t, "first pane width", first.W, 100)
			layoutNear(t, "second pane width", second.W, 300)
			tester.Press(first.X+first.W+4, first.Y+50)
			tester.Move(first.X+first.W+84, first.Y+50)
			tester.Release(first.X+first.W+84, first.Y+50)
			changes := layoutEvents(events, "value-changed", 2)
			if len(changes) == 0 {
				t.Fatalf("drag did not dispatch resize proposal: %+v", events)
			}
			proposal := changes[len(changes)-1].Value
			if pixelMode {
				if proposal <= 150 || proposal >= 210 {
					t.Fatalf("resize value must use pixels, got %g", proposal)
				}
			} else if proposal <= .38 || proposal >= .55 {
				t.Fatalf("resize value must use a fraction, got %g", proposal)
			}
			accepted := 0.5
			if pixelMode {
				accepted = 200
			}
			apply(t, b, 2, prop(2, mode, accepted))
			tester.Frame()
			layoutNear(t, "accepted reducer width", layoutRect(t, tester, "first pane").W, 200)
			apply(t, b, 3, prop(2, "resize-handle-width", 0))
			tester.Frame()
			count := len(layoutEvents(events, "value-changed", 2))
			tester.Press(204, 50)
			tester.Move(300, 50)
			tester.Release(300, 50)
			if len(layoutEvents(events, "value-changed", 2)) != count {
				t.Fatal("zero-width handle still accepted resize input")
			}
		})
	}
}

func TestLayoutResizableWidthAndRemoval(t *testing.T) {
	b := layoutBackend(t, "column", nil,
		create(3, "resizable"), prop(3, "width", 130), prop(3, "accessibility-label", "resizable panel"), insert(2, 3, 0),
		create(4, "box"), prop(4, "width", 40), prop(4, "height", 20), insert(3, 4, 0))
	tester := ui.NewTester(b.View, 400, 200)
	layoutNear(t, "resizable explicit width", layoutRect(t, tester, "resizable panel").W, 130)
	apply(t, b, 2, prop(3, "width", 180))
	tester.Frame()
	layoutNear(t, "resizable updated width", layoutRect(t, tester, "resizable panel").W, 180)
	apply(t, b, 3, Operation{Op: "detach-subtree", ID: 3})
	tester.Frame()
	if _, ok := tester.Find("resizable panel"); ok {
		t.Fatal("disposed resizable remained rendered")
	}
}

func TestLayoutSharedTextWrappingAndClampRemoval(t *testing.T) {
	b := layoutBackend(t, "column", nil,
		create(3, "text"), prop(3, "text", "one two three four five six seven eight"), prop(3, "width", 90), prop(3, "font-size", "18px"), prop(3, "white-space", "normal"), insert(2, 3, 0))
	tester := ui.NewTester(b.View, 300, 300)
	wrapped := layoutRect(t, tester, "one two three four five six seven eight")
	apply(t, b, 2, prop(3, "white-space", "nowrap"), prop(3, "text-overflow", "ellipsis"))
	tester.Frame()
	single := layoutRect(t, tester, "one two three four five six seven eight")
	if wrapped.H <= single.H*1.5 {
		t.Fatalf("nowrap did not collapse wrapped lines: wrapped=%+v single=%+v", wrapped, single)
	}
	apply(t, b, 3, Operation{Op: "remove-prop", ID: 3, Property: "white-space"}, Operation{Op: "remove-prop", ID: 3, Property: "text-overflow"})
	tester.Frame()
	layoutNear(t, "removed text flow restores wrapping", layoutRect(t, tester, "one two three four five six seven eight").H, wrapped.H)
}

func TestLayoutInteractionBackgroundsAndRemovalAffectPixels(t *testing.T) {
	b := layoutBackend(t, "button", nil,
		prop(2, "text", "X"), prop(2, "width", 100), prop(2, "height", 40), prop(2, "background", "#ff0000"), prop(2, "hover-background", "#0000ff"), prop(2, "pressed-background", "#00ff00"))
	tester := ui.NewTester(b.View, 300, 200)
	tester.Move(250, 150)
	layoutWantColor(t, tester, "X", .2, .5, layoutRed)
	r := layoutRect(t, tester, "X")
	tester.Move(r.X+r.W*.5, r.Y+r.H*.5)
	layoutWantColor(t, tester, "X", .2, .5, layoutBlue)
	tester.Press(r.X+r.W*.5, r.Y+r.H*.5)
	layoutWantColor(t, tester, "X", .2, .5, layoutGreen)
	tester.Release(r.X+r.W*.5, r.Y+r.H*.5)
	apply(t, b, 2, Operation{Op: "remove-prop", ID: 2, Property: "hover-background"}, Operation{Op: "remove-prop", ID: 2, Property: "pressed-background"})
	tester.Frame()
	layoutWantColor(t, tester, "X", .2, .5, layoutRed)
	tester.Press(r.X+r.W*.5, r.Y+r.H*.5)
	layoutWantColor(t, tester, "X", .2, .5, layoutRed)
	tester.Release(r.X+r.W*.5, r.Y+r.H*.5)
}
