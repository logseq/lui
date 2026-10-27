package luimygo

import (
	"fmt"
	"math"
	"slices"
	"unicode/utf8"
)

// Native OCaml uses a signed tagged integer, with 63 payload bits on the
// supported 64-bit hosts. Lengths cross the ABI as signed 32-bit integers.
func validateEvent(e Event) error {
	invalid := func(reason string) error { return fmt.Errorf("lui: invalid event %s: %s", e.Kind, reason) }
	const maxOCamlInt = int64(math.MaxInt64 >> 1)
	if e.Node <= 0 || e.Node > maxOCamlInt {
		return invalid("node is outside the native integer range")
	}
	for _, value := range []string{e.Text, e.TargetClass, e.Payload, e.Identifier, e.Name, e.Key, e.Outcome} {
		if len(value) > math.MaxInt32 || !utf8.ValidString(value) {
			return invalid("invalid UTF-8 or ABI string length")
		}
	}
	switch e.Kind {
	case "press", "long-press", "double-press", "submit", "dismiss", "appear", "change", "pointer-enter", "pointer-leave", "load", "navigate-previous", "navigate-next", "toggle-changed", "text-changed", "picked", "scroll-edges":
	case "press-modifiers":
		if e.Modifiers < 0 || e.Modifiers&^15 != 0 {
			return invalid("unknown modifier bits")
		}
	case "toggle-changed-detail":
		if e.Modifiers < 0 || e.Modifiers&^15 != 0 {
			return invalid("unknown modifier bits")
		}
	case "press-detail", "pointer-down", "pointer-up", "pointer-move", "pointer-cancel", "context-menu-press":
		if math.IsNaN(e.X) || math.IsNaN(e.Y) || math.IsInf(e.X, 0) || math.IsInf(e.Y, 0) {
			return invalid("nonfinite pointer coordinates")
		}
		if e.Modifiers < 0 || e.Modifiers&^15 != 0 || e.Button < 0 || e.Button > 2 {
			return invalid("unknown pointer modifiers or button")
		}
	case "value-changed":
		if math.IsNaN(e.Value) || math.IsInf(e.Value, 0) {
			return invalid("nonfinite value")
		}
	case "visible-range":
		if e.First < 0 || e.First > maxOCamlInt || e.Last > maxOCamlInt || e.Last < -1 || e.Last < e.First && !(e.First == 0 && e.Last == -1) {
			return invalid("invalid inclusive visible range")
		}
	case "scroll-completed":
		if e.Token < 0 || e.Token > maxOCamlInt || !slices.Contains([]string{"succeeded", "cancelled", "missing-target"}, e.Outcome) {
			return invalid("invalid scroll token or outcome")
		}
	case "navigation-key":
		if !slices.Contains([]string{"ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End", "PageUp", "PageDown", "Enter", " ", "Escape"}, e.Key) {
			return invalid("unknown navigation key")
		}
	case "extension-event":
		if _, err := extensionPayload(e); err != nil {
			return invalid(err.Error())
		}
	default:
		return invalid("unknown event kind")
	}
	return nil
}
