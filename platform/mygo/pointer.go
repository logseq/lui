package luimygo

import (
	"strings"

	"github.com/egoist/mygo/ui"
)

func pointerPolicy(n Node, e ui.Element) {
	if enabled, explicit := n.Props["pointer-enabled"].(bool); explicit {
		e.PointerEvents(enabled)
	} else if presentedOverlay(n) {
		e.PointerEvents(true)
	}
}

func presentedOverlay(n Node) bool {
	for _, record := range strings.Split(n.String("data-attrs"), "\x1e") {
		name, value, _ := strings.Cut(record, "\x1f")
		if name == "data-overlay-layer" && value == "true" {
			return false
		}
	}
	switch n.Kind {
	case "dialog", "sheet", "popover", "dropdown-menu", "context-menu", "toast":
		return true
	case "drawer":
		_, selected := n.Props["selected"]
		return !selected
	}
	return false
}
