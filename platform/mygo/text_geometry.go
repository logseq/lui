package luimygo

import "github.com/egoist/mygo/ui"

// CommittedBounds returns the transformed window-space box of a committed
// node, rejecting model changes that have not reached layout yet.
func (b *Backend) CommittedBounds(c *ui.Context, id int64) (ui.Rect, bool) {
	if b.closed || c == nil || b.probing || b.textGeneration != b.generation {
		return ui.Rect{}, false
	}
	s := b.states[id]
	if s == nil {
		return ui.Rect{}, false
	}
	for n, ok := b.nodes[id]; ok; n, ok = b.nodes[n.Parent] {
		if n.String("display") == "none" {
			return ui.Rect{}, false
		}
		if n.Parent == 0 {
			break
		}
	}
	space, ok := s.handle.Coordinates(c)
	if !ok {
		return ui.Rect{}, false
	}
	return space.Bounds()
}

// TextGeometry reads the exact committed shaped text of a standard text node,
// including its range in a rich inline paragraph. Offsets are rune-relative to
// this node; coordinates are window DIPs. Query after layout or between frames
// on the UI thread. The returned value expires on the next MyGo build.
// Missing, hidden, detached, unmounted and closed nodes return false.
func (b *Backend) TextGeometry(c *ui.Context, id int64) (ui.CommittedText, bool) {
	if b.closed || c == nil || b.probing || b.textGeneration != b.generation {
		return ui.CommittedText{}, false
	}
	n, ok := b.nodes[id]
	if !ok {
		return ui.CommittedText{}, false
	}
	for current := n; ; current = b.nodes[current.Parent] {
		if current.String("display") == "none" {
			return ui.CommittedText{}, false
		}
		if current.Parent == 0 {
			break
		}
	}
	s := b.states[id]
	if s == nil {
		return ui.CommittedText{}, false
	}
	return s.handle.TextGeometry(c)
}
