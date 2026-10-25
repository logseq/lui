package luimygo

import (
	"fmt"
	"math"

	"github.com/egoist/mygo/ui"
)

// BindHostElement gives an extension or custom renderer's primary control the
// retained node's host identity. Call during rendering, on the UI thread.
func (b *Backend) BindHostElement(id int64, element ui.Element) error {
	n, err := b.hostNode(id)
	if err != nil {
		return err
	}
	if !element.Valid() {
		return fmt.Errorf("mygo: host element for node %d is invalid", id)
	}
	if !b.probing {
		element.Bind(&b.state(n).handle)
	}
	return nil
}

// Bounds reads a nonempty committed box in window DIPs, never a speculative
// layout. Missing, hidden, unmounted and closed nodes report false.
func (b *Backend) Bounds(c *ui.Context, id int64) (ui.Rect, bool) {
	if b.closed || c == nil || b.probing {
		return ui.Rect{}, false
	}
	n, ok := b.nodes[id]
	if !ok {
		return ui.Rect{}, false
	}
	for current := n; ; current = b.nodes[current.Parent] {
		if current.String("display") == "none" {
			return ui.Rect{}, false
		}
		if current.Parent == 0 {
			break
		}
	}
	s := b.states[id]
	if s == nil {
		return ui.Rect{}, false
	}
	r := s.handle.Bounds(c)
	return r, r.W > 0 && r.H > 0
}

// RequestFocus waits for this node's next binding if it has not rendered yet.
// It does not acknowledge focus or change any model-controlled property.
func (b *Backend) RequestFocus(id int64) error {
	n, err := b.hostNode(id)
	if err != nil {
		return err
	}
	b.state(n).handle.Focus()
	return nil
}

// ScrollTo sets an immediate offset in DIPs. Token-controlled scroll requests
// retain ownership until completion; use their standard protocol to replace one.
func (b *Backend) ScrollTo(id int64, x, y float32) error {
	s, err := b.hostScroller(id)
	if err != nil {
		return err
	}
	if math.IsNaN(float64(x)) || math.IsNaN(float64(y)) || math.IsInf(float64(x), 0) || math.IsInf(float64(y), 0) {
		return fmt.Errorf("mygo: scroll offset must be finite")
	}
	if s.collection.pending {
		return fmt.Errorf("mygo: node %d has an active scroll-token request", id)
	}
	s.scroll.Stop()
	s.scroll.X, s.scroll.Y = max(0, x), max(0, y)
	return nil
}

// ScrollOffset reads the retained offset, including an unapplied ScrollTo.
// The next committed layout clamps that offset to the content extent.
func (b *Backend) ScrollOffset(id int64) (x, y float32, err error) {
	s, err := b.hostScroller(id)
	if err != nil {
		return 0, 0, err
	}
	return s.scroll.X, s.scroll.Y, nil
}

func (b *Backend) hostNode(id int64) (Node, error) {
	if b.closed {
		return Node{}, fmt.Errorf("mygo: backend is closed")
	}
	n, ok := b.nodes[id]
	if !ok {
		return Node{}, fmt.Errorf("mygo: unknown host node %d", id)
	}
	return n, nil
}

func (b *Backend) hostScroller(id int64) (*controlState, error) {
	n, err := b.hostNode(id)
	if err != nil {
		return nil, err
	}
	if n.Kind != "scroll" && n.Kind != "list" && n.Kind != "virtual-list" {
		return nil, fmt.Errorf("mygo: host node %d is not a scroll container", id)
	}
	return b.state(n), nil
}
