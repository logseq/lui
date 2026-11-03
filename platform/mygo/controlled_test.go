package luimygo

import (
	"errors"
	"math"
	"strings"
	"testing"

	"github.com/egoist/mygo/ui"
)

// The dispatcher models a synchronous reducer: a missing patch acknowledges
// rejection, rather than implicitly accepting a toolkit's mutable proposal.
func TestControlledEditorsAcknowledgeReducerWithoutLosingCaretOrComposition(t *testing.T) {
	for _, kind := range []string{"text-field", "secure-field", "input", "search-field", "textarea", "combobox"} {
		for _, mode := range []string{"accept", "normalize", "reject", "unsubscribed", "error"} {
			t.Run(kind+"/"+mode, func(t *testing.T) {
				var events []Event
				var b *Backend
				b = mounted(t, func(e Event) error {
					events = append(events, e)
					if e.Kind != "text-changed" {
						return nil
					}
					if mode == "error" {
						return errors.New("reducer unavailable")
					}
					if mode == "accept" || mode == "normalize" {
						text := e.Text
						if mode == "normalize" {
							text = strings.ToUpper(text)
						}
						return b.ApplyBatch(Batch{Generation: b.Generation() + 1, Ops: []Operation{prop(e.Node, "text", text)}})
					}
					return nil
				})
				if mode == "unsubscribed" {
					b.config.Dispatch = nil
				}
				apply(t, b, 2, create(3, kind), prop(3, "text", "ab"), prop(3, "placeholder", "Editor"), prop(3, "change-enabled", true), insert(2, 3, 0), create(4, "text"), prop(4, "text", "Status"), insert(2, 4, 1))
				tt := ui.NewTester(b.View, 480, 260)
				widgetClick(t, tt, "Editor")
				tt.Key(0, ui.KeyHome)
				tt.Key(0, ui.KeyRight)
				caret, active := tt.TextCaret()
				if !active {
					t.Fatal("editor has no input method")
				}
				before := len(events)
				tt.Compose("ni", 2)
				tt.Compose("你", 1)
				apply(t, b, b.Generation()+1, prop(4, "text", "Status changed"))
				tt.Frame()
				composing, active := tt.TextCaret()
				if !active || composing.X <= caret.X || len(events) != before {
					t.Fatal("retained frame lost composition or dispatched uncommitted text")
				}
				tt.Type("你")
				if mode != "unsubscribed" && widgetLast(t, events, "text-changed", 3).Text != "a你b" {
					t.Fatal(events)
				}
				want := "ab"
				if mode == "accept" {
					want = "a你b"
				}
				if mode == "normalize" {
					want = "A你B"
				}
				if got := b.states[3].text; got != want {
					t.Fatalf("acknowledged editor = %q, want %q", got, want)
				}
				if !tt.Focused("Editor") {
					t.Fatal("acknowledgement replaced focused editor")
				}
				// A same-length acknowledgement preserves the toolkit caret, so
				// the next insertion still precedes the original final character.
				if mode == "accept" || mode == "normalize" {
					tt.Type("x")
					if got := widgetLast(t, events, "text-changed", 3).Text; got != want[:len(want)-1]+"x"+want[len(want)-1:] {
						t.Fatalf("caret moved on acknowledgement: %q", got)
					}
				}
				if mode == "error" && b.Err() == nil {
					t.Fatal("dispatcher failure was hidden")
				}
				if kind != "secure-field" {
					tt.Command("selectAll")
					tt.Command("copy")
					node, _ := b.Node(3)
					if got := tt.Clipboard(); got != node.String("text") {
						t.Fatalf("native document %q differs from acknowledged model %q", got, node.String("text"))
					}
				}
			})
		}
	}
}

func TestControlledTogglesRejectWithoutPatchAndAcceptEcho(t *testing.T) {
	for _, kind := range []string{"checkbox", "toggle", "switch", "toggle-button", "radio", "accordion"} {
		for _, mode := range []string{"accept", "reject", "unsubscribed"} {
			t.Run(kind+"/"+mode, func(t *testing.T) {
				property := "checked"
				if kind == "toggle-button" || kind == "accordion" {
					property = "selected"
				}
				var events []Event
				var b *Backend
				b = mounted(t, func(e Event) error {
					events = append(events, e)
					if mode == "accept" && e.Kind == "toggle-changed" {
						return b.ApplyBatch(Batch{Generation: b.Generation() + 1, Ops: []Operation{prop(3, property, e.Checked)}})
					}
					return nil
				})
				if mode == "unsubscribed" {
					b.config.Dispatch = nil
				}
				ops := []Operation{create(3, kind), prop(3, "text", "Choice"), prop(3, property, false), prop(3, "toggle-enabled", mode != "unsubscribed"), insert(2, 3, 0)}
				if kind != "accordion" {
					ops = append(ops, prop(3, "accessibility-label", "Choice"))
				}
				apply(t, b, 2, ops...)
				tt := ui.NewTester(b.View, 400, 200)
				widgetClick(t, tt, "Choice")
				if got := b.states[3].checked; got != (mode == "accept") {
					t.Fatalf("acknowledged checked = %v in %s", got, mode)
				}
				if mode == "reject" {
					widgetClick(t, tt, "Choice")
					if !widgetLast(t, events, "toggle-changed", 3).Checked {
						t.Fatal("rejected proposal became next interaction's value")
					}
				}
			})
		}
	}
}

func TestControlledNumbersAcknowledgeAcceptedNormalizedAndNoPatch(t *testing.T) {
	for _, kind := range []string{"number-stepper", "slider"} {
		for _, mode := range []string{"accept", "normalize", "reject", "unsubscribed"} {
			t.Run(kind+"/"+mode, func(t *testing.T) {
				var events []Event
				var b *Backend
				b = mounted(t, func(e Event) error {
					events = append(events, e)
					if e.Kind == "value-changed" && (mode == "accept" || mode == "normalize") {
						value := e.Value
						if mode == "normalize" {
							value = 0.25
						}
						return b.ApplyBatch(Batch{Generation: b.Generation() + 1, Ops: []Operation{prop(3, "value", value)}})
					}
					return nil
				})
				if mode == "unsubscribed" {
					b.config.Dispatch = nil
				}
				ops := []Operation{create(3, kind), prop(3, "accessibility-label", "Value"), prop(3, "value", 0.5), prop(3, "change-enabled", true), insert(2, 3, 0)}
				if kind == "number-stepper" {
					ops = append(ops, prop(3, "min", 0.0), prop(3, "max", 1.0), prop(3, "step", 0.1))
				}
				apply(t, b, 2, ops...)
				tt := ui.NewTester(b.View, 400, 180)
				r, ok := tt.Find("Value")
				if !ok {
					t.Fatal("missing numeric control")
				}
				tt.ClickAt(r.X+20, r.Y+r.H/2)
				tt.Key(0, ui.KeyUp)
				want := 0.5
				if mode == "accept" {
					want = widgetLast(t, events, "value-changed", 3).Value
				}
				if mode == "normalize" {
					want = 0.25
				}
				if got := b.states[3].value; math.Abs(got-want) > 1e-9 {
					t.Fatalf("acknowledged number = %g, want %g", got, want)
				}
			})
		}
	}
}

func TestControlledAcknowledgementCannotTouchReplacementIncarnation(t *testing.T) {
	var b *Backend
	b = mounted(t, func(e Event) error {
		if e.Kind != "text-changed" {
			return nil
		}
		return b.ApplyBatch(Batch{Generation: b.Generation() + 1, Ops: []Operation{{Op: "remove-child", Parent: 2, Child: 3}, {Op: "drop-node", ID: 3}, create(3, "text-field"), prop(3, "text", "Replacement"), prop(3, "placeholder", "Editor"), insert(2, 3, 0)}})
	})
	apply(t, b, 2, create(3, "text-field"), prop(3, "text", "Original"), prop(3, "placeholder", "Editor"), insert(2, 3, 0))
	tt := ui.NewTester(b.View, 400, 180)
	widgetClick(t, tt, "Editor")
	tt.Type("x")
	tt.Frame()
	if got := b.states[3].text; got != "Replacement" {
		t.Fatalf("old interaction changed replacement: %q", got)
	}
}

func TestControlledQueuedInteractionUsesCurrentAncestorAdmission(t *testing.T) {
	for _, property := range []string{"inert", "enabled"} {
		t.Run(property, func(t *testing.T) {
			var events []Event
			var b *Backend
			b = mounted(t, func(e Event) error {
				events = append(events, e)
				if e.Node == 3 && e.Kind == "press" {
					return b.ApplyBatch(Batch{Generation: b.Generation() + 1, Ops: []Operation{prop(7, property, property == "inert")}})
				}
				return nil
			})
			parentKind := "box"
			if property == "enabled" {
				parentKind = "drawer"
			}
			queued := map[int64]bool{}
			// Custom renderers may queue events during construction. The first
			// reducer invalidates the second event's ancestor before delivery.
			b.config.Renderers = map[string]Renderer{
				parentKind: func(c *ui.Context, n Node, children func(), emit func(Event)) { ui.Column(c).Children(children) },
				"button": func(c *ui.Context, n Node, _ func(), emit func(Event)) {
					ui.Button(c, n.String("text"))
					if !queued[n.ID] {
						queued[n.ID] = true
						emit(Event{Kind: "press"})
					}
				},
				"image": func(c *ui.Context, n Node, _ func(), emit func(Event)) {
					ui.Box(c).Size(10, 10)
					if !queued[n.ID] {
						queued[n.ID] = true
						emit(Event{Kind: "load"})
					}
				},
			}
			ops := []Operation{create(7, parentKind), insert(2, 7, 0)}
			if parentKind == "drawer" {
				ops = append(ops, prop(7, "text", "Ancestor"))
			}
			ops = append(ops, create(3, "button"), prop(3, "text", "Block subtree"), prop(3, "press-enabled", true), insert(7, 3, 0), create(4, "button"), prop(4, "text", "Queued victim"), prop(4, "press-enabled", true), insert(7, 4, 1), create(5, "text"), prop(5, "text", "Appearance"), prop(5, "appear-enabled", true), insert(7, 5, 2), create(6, "image"), prop(6, "image", 7), prop(6, "pointer-enabled", true), insert(7, 6, 3))
			apply(t, b, 2, ops...)
			ui.NewTester(b.View, 400, 220)
			if b.Err() != nil {
				t.Fatal(b.Err())
			}
			if widgetCount(events, "press", 4) != 0 {
				t.Fatal("queued interaction escaped current ancestor restriction")
			}
			widgetLast(t, events, "appear", 5)
			widgetLast(t, events, "load", 6)
		})
	}
}

func TestControlledGenericButtonNavigationUsesCanonicalKeys(t *testing.T) {
	var events []Event
	b := mounted(t, func(e Event) error { events = append(events, e); return nil })
	apply(t, b, 2, create(3, "button"), prop(3, "text", "Navigate"), prop(3, "navigate-enabled", true), insert(2, 3, 0))
	tt := ui.NewTester(b.View, 400, 200)
	widgetClick(t, tt, "Navigate")
	for _, entry := range []struct {
		key  ui.Key
		name string
	}{{ui.KeyUp, "ArrowUp"}, {ui.KeyDown, "ArrowDown"}, {ui.KeyLeft, "ArrowLeft"}, {ui.KeyRight, "ArrowRight"}, {ui.KeyHome, "Home"}, {ui.KeyEnd, "End"}, {ui.KeyPageUp, "PageUp"}, {ui.KeyPageDown, "PageDown"}} {
		for _, shift := range []bool{false, true} {
			before := len(events)
			mods := ui.Modifiers(0)
			if shift {
				mods = ui.Shift
			}
			tt.Key(mods, entry.key)
			if len(events) != before+1 {
				t.Errorf("%s shift=%v callback count=%d", entry.name, shift, len(events)-before)
				continue
			}
			e := events[len(events)-1]
			if e.Kind != "navigation-key" || e.Key != entry.name || e.Shift != shift {
				t.Errorf("wrong navigation: %+v", e)
			}
		}
	}
}

func TestProbeStateUsesIsolatedScratchMap(t *testing.T) {
	b := New(Config{})
	n := Node{ID: 7, Kind: "toggle-button", Props: map[string]any{"selected": true}}
	live := b.state(n)
	identities := b.nextIdentity
	liveStates := b.states
	b.probing = true
	b.states = map[int64]*controlState{}
	first, second := b.state(n), b.state(n)
	if first != second || b.states[n.ID] != first {
		t.Error("probing lost per-node handles across repeated state lookups")
	}
	if !first.checked {
		t.Error("probing ignored selected state")
	}
	if first.identity != uint64(n.ID) || b.nextIdentity != identities {
		t.Error("measurement consumed live retained identity")
	}
	b.states = liveStates
	b.probing = false
	if b.state(n) != live {
		t.Error("measurement replaced live state")
	}
}
