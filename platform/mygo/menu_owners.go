package luimygo

import (
	"cmp"
	"slices"

	"github.com/egoist/mygo/ui"
)

type menuOwner struct {
	ownerID  int64
	identity uint64
	panel    ui.Handle
	widget   *widgetState
	native   bool
	context  bool
}

// OpenMenuOwners returns detached snapshots of actual open menu/popover
// owners, including anchors outside a portal. Query after layout or between
// frames on the UI thread. Only committed presentations and live retained
// incarnations resolve; this does not change input, focus or presentation.
func (b *Backend) OpenMenuOwners(c *ui.Context) []InputNode {
	if c == nil || b.closed || b.probing || b.viewGeneration != b.generation {
		return nil
	}
	var owners []InputNode
	seen := make(map[int64]bool)
	for _, menu := range b.menuOwners {
		if seen[menu.ownerID] || !menu.current(b, c) {
			continue
		}
		seen[menu.ownerID] = true
		owners = append(owners, InputNode{Node: b.nodes[menu.ownerID].clone(), backend: b, identity: menu.identity})
	}
	slices.SortFunc(owners, func(a, b InputNode) int { return cmp.Compare(a.Node.ID, b.Node.ID) })
	return owners
}

func (m *menuOwner) current(b *Backend, c *ui.Context) bool {
	state := b.states[m.ownerID]
	if state == nil || state.identity != m.identity || m.widget.retired || !b.inputNodeAvailable(m.ownerID) {
		return false
	}
	if m.native {
		return c.NativeMenuOpen(state.handle)
	}
	if m.widget.popupDismissed || m.context && !m.widget.contextOpen {
		return false
	}
	if _, ok := m.panel.Coordinates(c); !ok {
		return false
	}
	_, ok := state.handle.Coordinates(c)
	return ok
}

func (b *Backend) recordMenuOwner(presentation, owner Node, native, context bool) *menuOwner {
	key := b.state(presentation).identity
	if b.menuOwners == nil {
		b.menuOwners = make(map[uint64]*menuOwner)
	}
	m := b.menuOwners[key]
	if m == nil {
		m = &menuOwner{}
		b.menuOwners[key] = m
	}
	m.ownerID, m.identity = owner.ID, b.state(owner).identity
	m.widget, m.native, m.context = b.widget(presentation), native, context
	return m
}
