package luimygo

import (
	"github.com/egoist/mygo/ui"
	"time"
)

// A synchronous dispatch acknowledges a proposal even when the reducer emits
// no wire batch. Reconcile only after that interaction, retaining MyGo's
// editor, caret and uncommitted input-method composition between frames.
func (b *Backend) reconcileControl(e Event) {
	n, exists := b.nodes[e.Node]
	s := b.states[e.Node]
	if !exists || s == nil || s.identity != e.incarnation {
		return
	}
	switch e.Kind {
	case "text-changed":
		s.text = n.String("text")
	case "value-changed":
		s.value = n.Number("value", 0)
		if n.Kind == "split" {
			s.layout.acknowledge(n)
		}
	case "toggle-changed", "change":
		property := "checked"
		if n.Kind == "toggle-button" || n.Kind == "accordion" {
			property = "selected"
		}
		s.checked = n.Bool(property)
	}
}

func (b *Backend) interactionBlocked(n Node, e Event) bool {
	// Resource and lifecycle notifications remain meaningful while a subtree
	// is inert or disabled. Interactive events use the current retained tree,
	// including ancestors updated by earlier events in the same frame.
	switch e.Kind {
	case "appear", "load", "scroll-completed", "visible-range", "scroll-edges", "virtual-window":
		return false
	}
	for {
		if n.Props["enabled"] == false || n.Bool("inert") {
			return true
		}
		if n.Parent == 0 {
			return false
		}
		parent, exists := b.nodes[n.Parent]
		if !exists {
			return true
		}
		n = parent
	}
}

func eventModifiers(mods ui.Modifiers) int32 {
	var flags int32
	if mods&ui.Ctrl != 0 {
		flags |= 1
	}
	if mods&ui.Shift != 0 {
		flags |= 2
	}
	if mods&ui.Super != 0 {
		flags |= 4
	}
	return flags
}

func toggleModifiers(mods ui.Modifiers) int32 {
	flags := eventModifiers(mods)
	if mods&ui.Alt != 0 {
		flags |= 8
	}
	return flags
}

func (b *Backend) bindEvents(c *ui.Context, n Node, s *controlState, e ui.Element, emit func(Event)) {
	if b.probing {
		return
	}
	pointer := n.Bool("pointer-enabled")
	captured := pointer && n.Bool("pointer-capture")
	if pointer {
		hover := e.Hovered()
		if hover != s.hovered {
			s.hovered = hover
			kind := "pointer-leave"
			if hover {
				kind = "pointer-enter"
			}
			emit(Event{Kind: kind})
		}
	} else {
		s.hovered = false
	}
	if pointer || n.Bool("long-press-enabled") {
		handle := func(input ui.InputEvent) bool {
			if input.Kind != ui.InputPointerDown && input.Kind != ui.InputPointerUp && input.Kind != ui.InputPointerMove && input.Kind != ui.InputPointerCancel {
				return false
			}
			rect := s.handle.Bounds(c)
			event := Event{X: float64(rect.X + input.X), Y: float64(rect.Y + input.Y), Modifiers: eventModifiers(input.Mods), Button: int32(input.Button)}
			if input.Kind == ui.InputPointerMove && input.Button < 0 {
				event.Button = s.lastPointer.Button
			}
			// MyGo numbers the secondary button as one; the shared protocol uses
			// the DOM convention, where secondary is two and middle is one.
			if input.Button == 1 {
				event.Button = 2
				event.Modifiers |= 8
			} else if input.Button == 2 {
				event.Button = 1
			}
			switch input.Kind {
			case ui.InputPointerDown:
				if captured && input.Button != 0 {
					return true
				}
				s.captureActive = captured
				s.lastPointer = event
				if input.Button == 0 {
					s.longPressFired = false
					s.pressedAt = input.Time
					c.Invalidate()
				}
				if pointer {
					event.Kind = "pointer-down"
					emit(event)
				}
				return captured && input.Button == 0
			case ui.InputPointerUp:
				if captured && !s.captureActive {
					return false
				}
				s.captureActive = false
				s.lastPointer = event
				s.pressedAt = time.Time{}
				if pointer {
					event.Kind = "pointer-up"
					emit(event)
					if input.Button == 1 {
						event.Kind = "context-menu-press"
						emit(event)
					}
				}
			case ui.InputPointerMove:
				if captured && s.captureActive {
					s.lastPointer = event
					event.Kind = "pointer-move"
					emit(event)
				}
				if input.X < 0 || input.Y < 0 || input.X > rect.W || input.Y > rect.H {
					s.pressedAt = time.Time{}
				}
			case ui.InputPointerCancel:
				s.pressedAt = time.Time{}
				if captured && s.captureActive {
					s.captureActive = false
					event.X, event.Y = s.lastPointer.X, s.lastPointer.Y
					event.Kind = "pointer-cancel"
					event.Node, event.incarnation = n.ID, s.identity
					// Cancellation belongs to the admitted gesture, even when its
					// retained node has just been removed or made inert.
					current := b.states[n.ID]
					if !b.closed && (current == nil || current == s) && b.config.Dispatch != nil {
						if err := b.config.Dispatch(event); err != nil && b.err == nil {
							b.err = err
						}
					}
				}
			}
			return false
		}
		if captured {
			e.HandleCapturedPointer(handle)
		} else {
			e.HandleInput(handle)
		}
	}
	if n.Bool("long-press-enabled") && !s.pressedAt.IsZero() && !s.longPressFired {
		remaining := 350*time.Millisecond - c.Now().Sub(s.pressedAt)
		if remaining <= 0 {
			s.longPressFired = true
			emit(Event{Kind: "long-press"})
		} else {
			c.After(remaining)
		}
	}
	if n.Bool("double-press-enabled") && e.DoubleClicked() {
		emit(Event{Kind: "double-press"})
	}
	if !captured && (n.Bool("press-enabled") || pointer) {
		e.OnClick(func() {
			if s.longPressFired {
				return
			}
			if pointer {
				event := s.lastPointer
				event.Kind = "press-detail"
				emit(event)
			}
			if n.Bool("press-enabled") {
				flags := eventModifiers(e.ClickModifiers())
				if flags != 0 {
					emit(Event{Kind: "press-modifiers", Modifiers: flags})
				} else {
					emit(Event{Kind: "press"})
				}
			}
		})
	}
	if n.Bool("navigate-enabled") {
		if eventSupported(n.Kind, "navigate-previous") {
			e.OnShortcut(0, ui.KeyUp, func() { emit(Event{Kind: "navigate-previous"}) })
			e.OnShortcut(0, ui.KeyDown, func() { emit(Event{Kind: "navigate-next"}) })
		}
		if eventSupported(n.Kind, "navigation-key") {
			container := n.Kind == "row" || n.Kind == "box"
			if container {
				if b.interactionBlocked(n, Event{Kind: "navigation-key"}) {
					return
				}
				e.Focusable()
				// Subtree shortcuts claim a key before a child's default handling.
				// Do not register them while a descendant owns focus.
				if !s.handle.Focused(c) {
					return
				}
			}
			navigate := func(name string, shift bool) {
				if !container || s.handle.Focused(c) {
					emit(Event{Kind: "navigation-key", Key: name, Shift: shift})
				}
			}
			for key, name := range map[ui.Key]string{ui.KeyLeft: "ArrowLeft", ui.KeyRight: "ArrowRight", ui.KeyUp: "ArrowUp", ui.KeyDown: "ArrowDown", ui.KeyHome: "Home", ui.KeyEnd: "End", ui.KeyPageUp: "PageUp", ui.KeyPageDown: "PageDown"} {
				e.OnShortcut(0, key, func() { navigate(name, false) })
				e.OnShortcut(ui.Shift, key, func() { navigate(name, true) })
			}
			if container {
				for key, name := range map[ui.Key]string{ui.KeyEnter: "Enter", ui.KeySpace: " ", ui.KeyEscape: "Escape"} {
					e.OnShortcut(0, key, func() { navigate(name, false) })
					e.OnShortcut(ui.Shift, key, func() { navigate(name, true) })
				}
			}
		}
	}
}

// Standard event admission follows the same kind and role contracts as the
// OCaml runtime. PointerEnabled also subscribes non-pointer notifications, so
// it alone never grants a leaf editor pointer-detail events.
func eventAllowed(n Node, e Event) bool {
	if e.Kind == "virtual-window" {
		return n.Kind == "virtual-list" && n.Props["virtual-generation"] != nil
	}
	if n.Kind == "extension" {
		return e.Kind == "extension-event" && e.Identifier == n.Identifier
	}
	if e.Kind == "appear" {
		return n.Bool("appear-enabled")
	}
	if e.Kind == "navigate-previous" || e.Kind == "navigate-next" || e.Kind == "navigation-key" {
		return n.Bool("navigate-enabled") && eventSupported(n.Kind, e.Kind)
	}
	if n.String("role") == "treeitem" {
		switch e.Kind {
		case "press", "press-modifiers":
			return n.Bool("press-enabled")
		case "press-detail", "pointer-down", "pointer-up", "pointer-enter", "pointer-leave", "context-menu-press":
			return n.Bool("pointer-enabled")
		case "change":
			return n.Bool("change-enabled")
		case "toggle-changed":
			return n.Bool("toggle-enabled")
		case "toggle-changed-detail":
			return n.Bool("toggle-detail-enabled")
		}
	}
	if e.Kind == "pointer-move" || e.Kind == "pointer-cancel" {
		return n.Bool("pointer-capture") && n.Bool("pointer-enabled") && eventSupported(n.Kind, e.Kind)
	}
	if e.Kind == "toggle-changed-detail" {
		return n.Bool("toggle-detail-enabled") && eventSupported(n.Kind, e.Kind)
	}
	return eventSupported(n.Kind, e.Kind)
}
