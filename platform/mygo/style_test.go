package luimygo

import (
	"encoding/json"
	"reflect"
	"testing"

	"github.com/egoist/mygo/ui"
)

func TestLayoutStyleViewportFractionsAndContainerFrameRemoval(t *testing.T) {
	b := layoutBackend(t, "column", nil, prop(2, "width", 200), prop(2, "height", 100), prop(2, "cross", "start"),
		create(3, "box"), prop(3, "width-viewport", .5), prop(3, "height-viewport", .25), prop(3, "accessibility-label", "viewport child"), insert(2, 3, 0))
	tester := ui.NewTester(b.View, 400, 200)
	r := layoutRect(t, tester, "viewport child")
	layoutNear(t, "viewport width", r.W, 200)
	layoutNear(t, "viewport height", r.H, 50)
	apply(t, b, 2, Operation{Op: "remove-prop", ID: 3, Property: "width-viewport"}, Operation{Op: "remove-prop", ID: 3, Property: "height-viewport"}, prop(3, "container-relative-frame", "both"))
	tester.Frame()
	r = layoutRect(t, tester, "viewport child")
	layoutNear(t, "container width", r.W, 200)
	layoutNear(t, "container height", r.H, 100)
	tester.SetSize(600, 300)
	r = layoutRect(t, tester, "viewport child")
	layoutNear(t, "frame follows local container", r.W, 200)
	apply(t, b, 3, prop(3, "container-relative-frame", "min-both"), prop(3, "container-relative-frame-inset", 20))
	tester.Frame()
	r = layoutRect(t, tester, "viewport child")
	layoutNear(t, "min frame inset width", r.W, 180)
	layoutNear(t, "min frame inset height", r.H, 80)
	apply(t, b, 4, Operation{Op: "remove-prop", ID: 3, Property: "container-relative-frame"}, prop(3, "width", 40), prop(3, "height", 20))
	tester.Frame()
	r = layoutRect(t, tester, "viewport child")
	layoutNear(t, "removed frame width", r.W, 40)
	layoutNear(t, "removed frame height", r.H, 20)
}

func TestLayoutStyleRelativeAbsoluteOffsetsAndRemoval(t *testing.T) {
	b := layoutBackend(t, "column", nil, prop(2, "width", 200), prop(2, "height", 100),
		create(3, "box"), prop(3, "width", 30), prop(3, "height", 20), prop(3, "position", "relative"), prop(3, "inset-left", 10.0), prop(3, "inset-top", 7.0), prop(3, "accessibility-label", "positioned"), insert(2, 3, 0),
		create(4, "box"), prop(4, "width", 20), prop(4, "height", 10), prop(4, "accessibility-label", "following"), insert(2, 4, 1))
	tester := ui.NewTester(b.View, 300, 200)
	r := layoutRect(t, tester, "positioned")
	layoutNear(t, "relative x", r.X, 10)
	layoutNear(t, "relative y", r.Y, 7)
	layoutNear(t, "relative preserves flow", layoutRect(t, tester, "following").Y, 20)
	apply(t, b, 2, prop(3, "position", "absolute"), Operation{Op: "remove-prop", ID: 3, Property: "inset-left"}, prop(3, "inset-right", 5.0), prop(3, "inset-top", 8.0))
	tester.Frame()
	r = layoutRect(t, tester, "positioned")
	layoutNear(t, "absolute right", r.X+r.W, 195)
	layoutNear(t, "absolute top", r.Y, 8)
	layoutNear(t, "absolute leaves flow", layoutRect(t, tester, "following").Y, 0)
	apply(t, b, 3, Operation{Op: "remove-prop", ID: 3, Property: "position"})
	tester.Frame()
	r = layoutRect(t, tester, "positioned")
	layoutNear(t, "static ignores offsets", r.X, 0)
	layoutNear(t, "static restores flow", layoutRect(t, tester, "following").Y, 20)
}

func TestLayoutStyleZOrderChangesPaintAndPressWithoutChangingLayout(t *testing.T) {
	var events []Event
	b := layoutBackend(t, "stack", &events,
		create(3, "box"), prop(3, "width", 80), prop(3, "height", 40), prop(3, "background", "#ff0000"), prop(3, "z-index", 10), prop(3, "press-enabled", true), prop(3, "accessibility-label", "red layer"), insert(2, 3, 0),
		create(4, "box"), prop(4, "width", 80), prop(4, "height", 40), prop(4, "background", "#0000ff"), prop(4, "press-enabled", true), prop(4, "accessibility-label", "blue layer"), insert(2, 4, 1))
	tester := ui.NewTester(b.View, 200, 120)
	layoutWantColor(t, tester, "red layer", .5, .5, layoutRed)
	tester.ClickAt(40, 20)
	if len(layoutEvents(events, "press", 3)) != 1 || len(layoutEvents(events, "press", 4)) != 0 {
		t.Fatalf("hit test ignored paint order: %+v", events)
	}
	apply(t, b, 2, Operation{Op: "remove-prop", ID: 3, Property: "z-index"})
	tester.Frame()
	layoutWantColor(t, tester, "blue layer", .5, .5, layoutBlue)
	tester.ClickAt(40, 20)
	if len(layoutEvents(events, "press", 4)) != 1 {
		t.Fatal("removed z-index did not restore retained sibling order")
	}
}

func TestLayoutStyleLogicalAndUnitlessLineHeightAndDecoration(t *testing.T) {
	b := layoutBackend(t, "column", nil, prop(2, "cross", "start"),
		create(3, "text"), prop(3, "text", "first\nsecond"), prop(3, "font-size", "20px"), prop(3, "line-height", "30px"), prop(3, "white-space", "pre-wrap"), insert(2, 3, 0))
	tester := ui.NewTester(b.View, 300, 200)
	absolute := layoutRect(t, tester, "first\nsecond")
	layoutNear(t, "fixed logical line height", absolute.H, 60)
	apply(t, b, 2, prop(3, "line-height", "1.5"))
	tester.Frame()
	layoutNear(t, "unitless line-height multiplier", layoutRect(t, tester, "first\nsecond").H, absolute.H)
	apply(t, b, 3, prop(3, "line-height", "2rem"))
	tester.Frame()
	layoutNear(t, "rem resolves logical units", layoutRect(t, tester, "first\nsecond").H, 64)
	before := append([]byte(nil), tester.Image().Pix...)
	apply(t, b, 4, prop(3, "text-decoration", "underline line-through"))
	tester.Frame()
	if reflect.DeepEqual(before, tester.Image().Pix) {
		t.Fatal("text decoration did not draw")
	}
	apply(t, b, 5, Operation{Op: "remove-prop", ID: 3, Property: "text-decoration"})
	tester.Frame()
	if !reflect.DeepEqual(before, tester.Image().Pix) {
		t.Fatal("removed decoration retained ink")
	}
}

func TestLayoutStyleWhiteSpaceModesHaveDistinctFlow(t *testing.T) {
	text := "alpha   beta\ngamma"
	b := layoutBackend(t, "column", nil, prop(2, "cross", "start"),
		create(3, "box"), prop(3, "accessibility-label", "flow bounds"), insert(2, 3, 0),
		create(4, "text"), prop(4, "text", text), prop(4, "font-size", "18px"), prop(4, "white-space", "normal"), insert(3, 4, 0))
	tester := ui.NewTester(b.View, 400, 200)
	normal := layoutRect(t, tester, "flow bounds")
	apply(t, b, 2, prop(4, "white-space", "pre-wrap"))
	tester.Frame()
	preserved := layoutRect(t, tester, "flow bounds")
	if preserved.H < normal.H*1.5 {
		t.Fatalf("normal mode failed to collapse hard newline: normal=%+v preserved=%+v", normal, preserved)
	}
	apply(t, b, 3, prop(4, "white-space", "pre-line"))
	tester.Frame()
	lines := layoutRect(t, tester, "flow bounds")
	layoutNear(t, "pre-line preserves lines", lines.H, preserved.H)
	if lines.W >= preserved.W-3 {
		t.Fatalf("pre-line failed to collapse spaces: pre=%+v line=%+v", preserved, lines)
	}
}

func TestLayoutStyleShadowOpacityStatesAndRemoval(t *testing.T) {
	b := layoutBackend(t, "column", nil, prop(2, "padding", 20), prop(2, "background", "#ffffff"),
		create(3, "button"), prop(3, "text", "ink"), prop(3, "accessibility-label", "shadow control"), prop(3, "width", 80), prop(3, "height", 40), prop(3, "background", "#ff0000"), prop(3, "shadow", "4px 4px 0px 0px #000000"), prop(3, "hover-opacity", .5), prop(3, "disabled-opacity", .25), insert(2, 3, 0))
	tester := ui.NewTester(b.View, 300, 200)
	tester.Move(250, 150)
	r := layoutRect(t, tester, "shadow control")
	pixel := tester.Image().RGBAAt(int(r.X+r.W+2), int(r.Y+r.H/2+4))
	if pixel.R > 20 || pixel.G > 20 || pixel.B > 20 {
		t.Fatalf("shadow missing outside box: %#v", pixel)
	}
	tester.Move(r.X+20, r.Y+20)
	hover := layoutColorAt(t, tester, "shadow control", .2, .5)
	if hover.G < 110 || hover.G > 150 {
		t.Fatalf("hover opacity not composited against parent: %#v", hover)
	}
	apply(t, b, 2, prop(3, "enabled", false))
	tester.Frame()
	disabled := layoutColorAt(t, tester, "shadow control", .2, .5)
	if disabled.G < 175 || disabled.G > 205 {
		t.Fatalf("disabled opacity precedence incorrect: %#v", disabled)
	}
	apply(t, b, 3, prop(3, "enabled", true), Operation{Op: "remove-prop", ID: 3, Property: "shadow"}, Operation{Op: "remove-prop", ID: 3, Property: "hover-opacity"})
	tester.Frame()
	layoutWantColor(t, tester, "shadow control", .2, .5, layoutRed)
	pixel = tester.Image().RGBAAt(int(r.X+r.W+2), int(r.Y+r.H/2+4))
	if pixel.R < 250 || pixel.G < 250 || pixel.B < 250 {
		t.Fatal("removed shadow remained painted")
	}
}

func TestLayoutStyleOverflowAutoScrollsAndHiddenClips(t *testing.T) {
	b := layoutBackend(t, "box", nil, prop(2, "width", 100), prop(2, "height", 60), prop(2, "overflow", "auto"),
		create(3, "box"), prop(3, "height", 50), prop(3, "min-height", 50), prop(3, "background", "#ff0000"), insert(2, 3, 0),
		create(4, "box"), prop(4, "height", 50), prop(4, "min-height", 50), prop(4, "background", "#0000ff"), prop(4, "accessibility-label", "overflow target"), insert(2, 4, 1))
	tester := ui.NewTester(b.View, 200, 150)
	tester.Scroll(40, 30, 0, 60)
	target := layoutRect(t, tester, "overflow target")
	if target.Y > 20 {
		t.Fatalf("overflow:auto did not scroll content: %+v", target)
	}
	apply(t, b, 2, prop(2, "overflow", "hidden"))
	tester.Frame()
	tester.Scroll(40, 30, 0, 60)
	target = layoutRect(t, tester, "overflow target")
	if target.Y < 49 {
		t.Fatalf("overflow:hidden retained scrolling: %+v", target)
	}
}

func TestLayoutStyleAdaptiveInteractionColorsAndRemoval(t *testing.T) {
	b := layoutBackend(t, "button", nil, prop(2, "text", "theme"), prop(2, "accessibility-label", "theme control"), prop(2, "width", 100), prop(2, "height", 40), prop(2, "theme", `{"primary":{"light":"#ff0000","dark":"#0000ff"}}`), prop(2, "hover-background", "primary"))
	tester := ui.NewTester(b.View, 240, 120)
	tester.Move(20, 20)
	layoutWantColor(t, tester, "theme control", .2, .5, layoutRed)
	tester.SetDark(true)
	layoutWantColor(t, tester, "theme control", .2, .5, layoutBlue)
	apply(t, b, 2, Operation{Op: "remove-prop", ID: 2, Property: "hover-background"})
	tester.Frame()
	if layoutSameColor(layoutColorAt(t, tester, "theme control", .2, .5), layoutBlue) {
		t.Fatal("removed adaptive interaction color remained cached")
	}
}

func TestLayoutStyleAccessibleHeadingAndNavigationSemantics(t *testing.T) {
	b := layoutBackend(t, "column", nil,
		create(3, "heading"), prop(3, "text", "Heading"), prop(3, "heading-level", 3), insert(2, 3, 0),
		create(4, "list-item"), prop(4, "text", "Navigation"), prop(4, "role", "navigation"), insert(2, 4, 1))
	tester := ui.NewTester(b.View, 300, 200)
	method := reflect.ValueOf(tester).MethodByName("Accessibility")
	if !method.IsValid() {
		t.Fatal("MyGo Tester must expose actual committed accessibility snapshot")
	}
	values := method.Call(nil)
	encoded, err := json.Marshal(values[0].Interface())
	if err != nil {
		t.Fatal(err)
	}
	var nodes []map[string]any
	if err := json.Unmarshal(encoded, &nodes); err != nil {
		t.Fatal(err)
	}
	heading, navigation := false, false
	for _, node := range nodes {
		if node["label"] == "Heading" {
			heading = node["role"] == float64(ui.RoleHeading) && node["level"] == float64(3)
		}
		if node["label"] == "Navigation" {
			navigation = navigation || node["role"] == float64(ui.RoleGroup)
		}
	}
	if !heading || !navigation {
		t.Fatalf("missing portable semantic roles in committed tree: %s", encoded)
	}
}

func TestLayoutStyleInertPreservesPixelsAndBlocksSubtreeInteraction(t *testing.T) {
	var events []Event
	b := layoutBackend(t, "box", &events, prop(2, "width", 100), prop(2, "height", 50), create(3, "button"), prop(3, "text", "activate"), prop(3, "width", 100), prop(3, "height", 50), prop(3, "background", "#ff0000"), prop(3, "press-enabled", true), insert(2, 3, 0))
	tester := ui.NewTester(b.View, 200, 100)
	tester.Move(150, 75)
	before := append([]byte(nil), tester.Image().Pix...)
	apply(t, b, 2, prop(2, "inert", true))
	tester.Frame()
	if !reflect.DeepEqual(before, tester.Image().Pix) {
		t.Fatal("inert subtree changed visual presentation")
	}
	tester.ClickAt(50, 25)
	if len(layoutEvents(events, "press", 3)) != 0 {
		t.Fatal("inert descendant received press")
	}
	apply(t, b, 3, Operation{Op: "remove-prop", ID: 2, Property: "inert"})
	tester.Frame()
	tester.ClickAt(50, 25)
	if len(layoutEvents(events, "press", 3)) != 1 {
		t.Fatal("removed inert did not restore interaction")
	}
}

func TestLayoutStyleExplicitNormalTypographyOverridesInheritedStyle(t *testing.T) {
	b := layoutBackend(t, "column", nil, prop(2, "cross", "start"), create(3, "text"), prop(3, "text", "Plain Typography"), prop(3, "font-size", "24px"), prop(3, "font-style", "normal"), prop(3, "text-decoration", "none"), insert(2, 3, 0))
	tester := ui.NewTester(b.View, 300, 120)
	before := append([]byte(nil), tester.Image().Pix...)
	apply(t, b, 2, prop(2, "font-style", "italic"), prop(2, "text-decoration", "underline line-through"))
	tester.Frame()
	if !reflect.DeepEqual(before, tester.Image().Pix) {
		t.Fatal("explicit normal/none failed to override inherited typography")
	}
	apply(t, b, 3, Operation{Op: "remove-prop", ID: 3, Property: "font-style"}, Operation{Op: "remove-prop", ID: 3, Property: "text-decoration"})
	tester.Frame()
	if reflect.DeepEqual(before, tester.Image().Pix) {
		t.Fatal("removed overrides failed to inherit ancestor typography")
	}
}

func TestLayoutStyleFunctionalAndNamedColorsAndSpacedShadow(t *testing.T) {
	for _, test := range []struct {
		name string
		want [3]uint8
	}{{"rgb(255, 0, 0)", [3]uint8{255, 0, 0}}, {"rgb(0% 0% 100%)", [3]uint8{0, 0, 255}}, {"rgba(255, 0, 0, 0.5)", [3]uint8{255, 127, 127}}, {"hsl(120 100% 50%)", [3]uint8{0, 255, 0}}, {"rebeccapurple", [3]uint8{102, 51, 153}}} {
		t.Run(test.name, func(t *testing.T) {
			b := layoutBackend(t, "box", nil, prop(2, "width", 60), prop(2, "height", 40), prop(2, "background", test.name), prop(2, "accessibility-label", "color sample"), prop(1, "background", "#ffffff"))
			tester := ui.NewTester(b.View, 120, 80)
			got := layoutColorAt(t, tester, "color sample", .5, .5)
			for i, v := range []uint8{got.R, got.G, got.B} {
				if d := int(v) - int(test.want[i]); d < -4 || d > 4 {
					t.Fatalf("functional color rendered %#v want %v", got, test.want)
				}
			}
		})
	}
	b := layoutBackend(t, "box", nil, prop(2, "width", 50), prop(2, "height", 30), prop(2, "margin", 10), prop(2, "background", "#ffffff"), prop(2, "shadow", "5px 0px 0px 0px rgba(255, 0, 0, 1)"), prop(2, "accessibility-label", "spaced shadow"), prop(1, "background", "#ffffff"))
	tester := ui.NewTester(b.View, 120, 80)
	r := layoutRect(t, tester, "spaced shadow")
	p := tester.Image().RGBAAt(int(r.X+r.W+2), int(r.Y+15))
	if p.R < 250 || p.G > 4 || p.B > 4 {
		t.Fatalf("shadow functional color with spaces rendered %#v", p)
	}
}

func TestLayoutStyleOverflowAutoAlsoScrollsHorizontalOverflow(t *testing.T) {
	b := layoutBackend(t, "box", nil, prop(2, "width", 100), prop(2, "height", 50), prop(2, "overflow", "auto"), prop(2, "accessibility-label", "scroll surface"),
		create(3, "row"), prop(3, "width", 200), prop(3, "height", 30), insert(2, 3, 0),
		create(4, "box"), prop(4, "width", 80), prop(4, "height", 30), prop(4, "background", "#ff0000"), insert(3, 4, 0),
		create(5, "box"), prop(5, "width", 120), prop(5, "height", 30), prop(5, "background", "#0000ff"), insert(3, 5, 1))
	tester := ui.NewTester(b.View, 250, 120)
	layoutWantColor(t, tester, "scroll surface", .5, .3, layoutRed)
	tester.Scroll(50, 20, 80, 0)
	layoutWantColor(t, tester, "scroll surface", .5, .3, layoutBlue)
	apply(t, b, 2, prop(2, "overflow", "visible"))
	tester.Frame()
	layoutWantColor(t, tester, "scroll surface", .5, .3, layoutRed)
}

func TestLayoutStylePortableSemanticTokensResolveNativeThemeSlots(t *testing.T) {
	theme := ui.LightTheme()
	for _, test := range []struct {
		name string
		want ui.Color
	}{{"card", theme.Background}, {"card-foreground", theme.Text}, {"secondary-foreground", theme.Text}, {"accent-foreground", theme.Text}, {"destructive-foreground", theme.AccentText}, {"error", theme.Danger.Alpha(.15).Over(theme.Background)}, {"error-foreground", theme.Danger}, {"success", theme.Success.Alpha(.15).Over(theme.Background)}, {"success-foreground", theme.Success}, {"warning", theme.Warning.Alpha(.15).Over(theme.Background)}, {"warning-foreground", theme.Warning}, {"input", theme.Border}, {"ring", theme.Focus.Over(theme.Background)}} {
		t.Run(test.name, func(t *testing.T) {
			b := layoutBackend(t, "box", nil, prop(2, "width", 60), prop(2, "height", 40), prop(2, "background", test.name), prop(2, "accessibility-label", "semantic sample"))
			tester := ui.NewTester(b.View, 120, 80)
			got := layoutColorAt(t, tester, "semantic sample", .5, .5)
			want := test.want
			for i, v := range []uint8{got.R, got.G, got.B} {
				w := []uint8{want.R, want.G, want.B}[i]
				if d := int(v) - int(w); d < -4 || d > 4 {
					t.Fatalf("semantic %s rendered %#v want %#v", test.name, got, want)
				}
			}
		})
	}
	b := layoutBackend(t, "button", nil, prop(2, "text", "aliased primary"), prop(2, "variant", "primary"), prop(2, "width", 120), prop(2, "height", 40), prop(2, "accessibility-label", "token control"), prop(2, "theme", `{"primary":"custom-accent","custom-accent":{"light":"rgb(255, 0, 0)","dark":"rgb(0, 0, 255)"}}`))
	tester := ui.NewTester(b.View, 240, 100)
	tester.Move(200, 80)
	layoutWantColor(t, tester, "token control", .1, .5, layoutRed)
	tester.SetDark(true)
	layoutWantColor(t, tester, "token control", .1, .5, layoutBlue)
	apply(t, b, 2, Operation{Op: "remove-prop", ID: 2, Property: "theme"})
	tester.Frame()
	if layoutSameColor(layoutColorAt(t, tester, "token control", .1, .5), layoutBlue) {
		t.Fatal("removed functional token aliases remained in native theme")
	}
}

func TestLayoutStyleOklchColorUsesNativeColorConversion(t *testing.T) {
	b := layoutBackend(t, "box", nil, prop(2, "width", 60), prop(2, "height", 40), prop(2, "background", "oklch(50% 0 0)"), prop(2, "accessibility-label", "oklch sample"))
	tester := ui.NewTester(b.View, 120, 80)
	got := layoutColorAt(t, tester, "oklch sample", .5, .5)
	want := ui.Oklch(.5, 0, 0)
	for i, v := range []uint8{got.R, got.G, got.B} {
		w := []uint8{want.R, want.G, want.B}[i]
		if d := int(v) - int(w); d < -3 || d > 3 {
			t.Fatalf("oklch rendered %#v want %#v", got, want)
		}
	}
}

func TestLayoutStyleUserSelectionCursorAndRemoval(t *testing.T) {
	b := layoutBackend(t, "box", nil, prop(2, "user-select", "text"), prop(2, "cursor", "pointer"), prop(2,"pressed-background","#00ff00"), create(3, "text"), prop(3, "text", "copy words"), prop(3, "font-size", "24px"), insert(2, 3, 0))
	tester := ui.NewTester(b.View, 300, 120)
	r := layoutRect(t, tester, "copy words")
	tester.Move(r.X+10, r.Y+r.H/2)
	if cursor := tester.Cursor(); cursor != ui.CursorPointer {
		t.Fatalf("explicit pointer cursor ignored: %v", cursor)
	}
	copyText := func() {
		r := layoutRect(t, tester, "copy words")
		tester.Press(r.X+1, r.Y+r.H/2)
		tester.Move(r.X+r.W-1, r.Y+r.H/2)
		tester.Release(r.X+r.W-1, r.Y+r.H/2)
		tester.Key(ui.Cmd, ui.KeyC)
		tester.Key(ui.Ctrl, ui.KeyC)
	}
	copyText()
	if got := tester.Clipboard(); got != "copy words" {
		t.Fatalf("selectable text did not copy: %q", got)
	}
	apply(t, b, 2, prop(3, "user-select", "none"), Operation{Op: "remove-prop", ID: 2, Property: "cursor"})
	tester.Frame()
	tester.SetClipboard("unchanged")
	copyText()
	if got := tester.Clipboard(); got != "unchanged" {
		t.Fatalf("excluded text still copied: %q", got)
	}
	apply(t, b, 3, Operation{Op: "remove-prop", ID: 3, Property: "user-select"})
	tester.Frame()
	copyText()
	if got := tester.Clipboard(); got != "copy words" {
		t.Fatalf("removed selection exclusion did not restore inheritance: %q", got)
	}
}

func TestLayoutStyleLineClampAndFlexWrapRemoval(t *testing.T) {
	b := layoutBackend(t, "column", nil, prop(2, "cross", "start"), create(3, "paragraph"), prop(3, "text", "one two three four five six seven eight"), prop(3, "width", 70), prop(3, "font-size", "20px"), prop(3, "line-height", "24px"), insert(2, 3, 0))
	tester := ui.NewTester(b.View, 300, 400)
	full := layoutRect(t, tester, "one two three four five six seven eight")
	apply(t, b, 2, prop(3, "line-clamp", 2))
	tester.Frame()
	layoutNear(t, "clamped two logical lines", layoutRect(t, tester, "one two three four five six seven eight").H, 48)
	apply(t, b, 3, Operation{Op: "remove-prop", ID: 3, Property: "line-clamp"})
	tester.Frame()
	layoutNear(t, "line clamp removal", layoutRect(t, tester, "one two three four five six seven eight").H, full.H)
	b = layoutBackend(t, "row", nil, prop(2, "width", 150), prop(2, "flex-wrap", "wrap"), create(3, "box"), prop(3, "width", 60), prop(3, "min-width", 60), prop(3, "height", 20), insert(2, 3, 0), create(4, "box"), prop(4, "width", 60), prop(4, "min-width", 60), prop(4, "height", 20), insert(2, 4, 1), create(5, "box"), prop(5, "width", 60), prop(5, "min-width", 60), prop(5, "height", 20), prop(5, "accessibility-label", "wrapped last"), insert(2, 5, 2))
	tester = ui.NewTester(b.View, 300, 100)
	layoutNear(t, "wrapped row creates another line", layoutRect(t, tester, "wrapped last").Y, 20)
	apply(t, b, 2, Operation{Op: "remove-prop", ID: 2, Property: "flex-wrap"})
	tester.Frame()
	layoutNear(t, "removed wrap returns to single line", layoutRect(t, tester, "wrapped last").Y, 0)
}

func TestLayoutStyleDividerOrientation(t *testing.T) {
	b := layoutBackend(t, "column", nil, prop(2, "width", 100), prop(2, "height", 40), create(3, "divider"), prop(3, "orientation", "vertical"), insert(2, 3, 0))
	var ctx *ui.Context
	tester := ui.NewTester(func(c *ui.Context) { ctx = c; b.View(c) }, 200, 120)
	rect := b.states[3].handle.Bounds(ctx)
	layoutNear(t, "explicit vertical divider width", rect.W, 1)
	layoutNear(t, "explicit vertical divider height", rect.H, 40)
	apply(t, b, 2, prop(3, "orientation", "horizontal"))
	tester.Frame()
	rect = b.states[3].handle.Bounds(ctx)
	layoutNear(t, "explicit horizontal divider width", rect.W, 100)
	layoutNear(t, "explicit horizontal divider height", rect.H, 1)
}

func TestLayoutStyleSpinnerSize(t *testing.T) {
	b := layoutBackend(t, "spinner", nil, prop(2, "size", "sm"), Operation{Op: "remove-child", Parent: 1, Child: 2}, create(3, "box"), prop(3, "accessibility-label", "sized spinner"), insert(1, 3, 0), insert(3, 2, 0))
	tester := ui.NewTester(b.View, 150, 100)
	layoutNear(t, "small spinner extent", layoutRect(t, tester, "sized spinner").W, 16)
	apply(t, b, 2, prop(2, "size", "lg"))
	tester.Frame()
	layoutNear(t, "large spinner extent", layoutRect(t, tester, "sized spinner").W, 24)
	apply(t, b, 3, Operation{Op: "remove-prop", ID: 2, Property: "size"})
	tester.Frame()
	layoutNear(t, "default spinner extent", layoutRect(t, tester, "sized spinner").W, 20)
}
