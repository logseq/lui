package luimygo

import (
	"github.com/egoist/mygo/ui"
	"os"
	"testing"
)

// This suite runs in its own process against the actual Components library.
// No standard renderer overrides are registered: the retained Gallery and
// its reducer are the application on both sides of every native ABI call.
func TestOCamlComponentsEventRoundTrip(t *testing.T) {
	path := os.Getenv("LUI_MYGO_COMPONENTS_LIBRARY")
	if path == "" {
		t.Skip("run tooling/test_mygo.sh for separate Components integration")
	}
	b := New(Config{})
	defer b.Close()
	runtime, err := OpenRuntime(path, b)
	if err != nil {
		t.Fatal(err)
	}
	defer runtime.Close()
	nodeID := func(identifier string) int64 {
		for id, node := range b.nodes {
			if node.String("accessibility-identifier") == identifier {
				return id
			}
		}
		t.Fatalf("missing Gallery event fixture %s", identifier)
		return 0
	}
	button := nodeID("events-button")
	editor := nodeID("events-editor")
	toggle := nodeID("events-toggle")
	radio := nodeID("events-radio")
	slider := nodeID("events-slider")
	list := nodeID("events-list")
	row := nodeID("events-row")
	image := nodeID("events-image")
	picker := nodeID("events-picker")
	status := nodeID("events-status")
	pointer := func(kind string) Event {
		return Event{Kind: kind, Node: button, X: 12.25, Y: -3.5, Modifiers: 7, Button: 2, TargetClass: "deep\x00你好"}
	}
	cases := []struct {
		event Event
		want  string
	}{
		{Event{Kind: "press", Node: button}, "press"},
		{Event{Kind: "press-modifiers", Node: button, Modifiers: 7}, "press-modifiers:7"},
		{Event{Kind: "long-press", Node: button}, "long-press"},
		{Event{Kind: "double-press", Node: row}, "double-press"},
		{Event{Kind: "appear", Node: button}, "appear"},
		{Event{Kind: "text-changed", Node: editor, Text: "before\x00after你好 🌍"}, "text-changed:before\x00after你好 🌍"},
		{Event{Kind: "submit", Node: editor}, "submit"},
		{Event{Kind: "toggle-changed", Node: toggle, Checked: true}, "toggle-changed:true"},
		{Event{Kind: "toggle-changed", Node: toggle, Checked: false}, "toggle-changed:false"},
		{Event{Kind: "change", Node: radio}, "change"},
		{Event{Kind: "value-changed", Node: slider, Value: 0.375}, "value-changed:0.375"},
		{Event{Kind: "dismiss", Node: picker}, "dismiss"},
		{Event{Kind: "picked", Node: picker, Payload: "{\"request\":\"a\\u0000你好\",\"files\":[]}"}, "picked:{\"request\":\"a\\u0000你好\",\"files\":[]}"},
		{pointer("press-detail"), "press-detail:12.25,-3.50:7:2:deep\x00你好"},
		{pointer("pointer-down"), "pointer-down:12.25,-3.50:7:2:deep\x00你好"},
		{pointer("pointer-up"), "pointer-up:12.25,-3.50:7:2:deep\x00你好"},
		{pointer("context-menu-press"), "context-menu-press:12.25,-3.50:7:2:deep\x00你好"},
		{Event{Kind: "pointer-enter", Node: button}, "pointer-enter"},
		{Event{Kind: "pointer-leave", Node: button}, "pointer-leave"},
		{Event{Kind: "load", Node: image}, "load"},
		{Event{Kind: "navigate-previous", Node: editor}, "navigate-previous"},
		{Event{Kind: "navigate-next", Node: editor}, "navigate-next"},
		{Event{Kind: "navigation-key", Node: button, Key: "ArrowRight", Shift: true}, "navigation-key:ArrowRight:true"},
		{Event{Kind: "scroll-completed", Node: list, Token: 9007199254740993, Outcome: "missing-target"}, "scroll-completed:9007199254740993:missing-target"},
		{Event{Kind: "visible-range", Node: list, First: 0, Last: -1}, "visible-range:0:-1"},
		{Event{Kind: "scroll-edges", Node: list, AtStart: false, AtEnd: true}, "scroll-edges:false:true"},
	}
	for _, test := range cases {
		t.Run(test.event.Kind, func(t *testing.T) {
			if err := runtime.Dispatch(test.event); err != nil {
				t.Fatal(err)
			}
			n, _ := b.Node(status)
			if n.String("text") != "Event: "+test.want {
				t.Fatalf("actual OCaml subscriber/reducer lost payload: got %q, want %q", n.String("text"), "Event: "+test.want)
			}
		})
	}
	before, _ := b.Node(status)
	if err := runtime.Resync(); err != nil {
		t.Fatal(err)
	}
	after, _ := b.Node(status)
	if before.String("text") != after.String("text") {
		t.Fatal("snapshot lost reducer event state")
	}
	tester := ui.NewTester(b.View, 1000, 760)
	if !tester.HasText("Event payloads") {
		t.Fatal("actual Gallery failed to render event page")
	}
	if b.Err() != nil {
		t.Fatal(b.Err())
	}
}

func TestOCamlComponentsControlledEditorRejectsUnchangedWireValue(t *testing.T) {
	path := os.Getenv("LUI_MYGO_COMPONENTS_LIBRARY")
	if path == "" {
		t.Skip("run tooling/test_mygo.sh for separate Components integration")
	}
	b := New(Config{})
	defer b.Close()
	runtime, err := OpenRuntime(path, b)
	if err != nil {
		t.Fatal(err)
	}
	defer runtime.Close()
	var editor, status int64
	for id, node := range b.nodes {
		switch node.String("accessibility-identifier") {
		case "events-editor":
			editor = id
		case "events-status":
			status = id
		}
	}
	if editor == 0 || status == 0 {
		t.Fatal("missing actual Gallery event controls")
	}
	tt := ui.NewTester(b.View, 1000, 760)
	tt.Scroll(950, 700, 0, 100000)
	widgetClick(t, tt, "Event input")
	for attempt := 0; attempt < 2; attempt++ {
		tt.Key(ui.Ctrl, ui.KeyA)
		tt.Key(ui.Cmd, ui.KeyA)
		before := b.Generation()
		tt.Type("Rejected proposal")
		if attempt == 1 && b.Generation() != before {
			t.Error("identical actual OCaml model unexpectedly emitted a batch")
		}
		node, _ := b.Node(editor)
		if node.String("text") != "Editable event" {
			t.Fatal("fixture reducer unexpectedly accepted editor text")
		}
		message, _ := b.Node(status)
		if message.String("text") != "Event: text-changed:Rejected proposal" {
			t.Fatalf("actual OCaml subscriber did not receive proposal: %q", message.String("text"))
		}
		tt.Command("selectAll")
		tt.Command("copy")
		if tt.Clipboard() != "Editable event" || b.states[editor].text != "Editable event" {
			t.Errorf("actual OCaml rejection left proposal in editor without an editor patch: state=%q native document=%q", b.states[editor].text, tt.Clipboard())
		}
		if !tt.Focused("Event input") {
			t.Fatal("rejection lost native editor focus")
		}
	}
	if b.Err() != nil {
		t.Fatal(b.Err())
	}
}
