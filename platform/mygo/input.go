package luimygo

import "github.com/egoist/mygo/ui"

// InputNode is a snapshot of a retained node resolved from committed MyGo input.
// Current rejects removed or remounted node IDs, including reuse between a
// pointer press and release. Node is a copy and must not be changed.
type InputNode struct {
	Node     Node
	backend  *Backend
	identity uint64
}

// Current reports whether the same visible retained incarnation still exists.
func (n InputNode) Current() bool {
	b := n.backend
	if b == nil || b.closed {
		return false
	}
	if !b.inputNodeAvailable(n.Node.ID) {
		return false
	}
	s := b.states[n.Node.ID]
	return s != nil && s.identity == n.identity
}

// InputNode resolves the closest retained host binding on MyGo's actual focus
// or hit ancestry. Call only inside Context.CaptureInput, on the UI thread.
// Unbound internal control children resolve to their closest retained parent;
// missing, hidden, disabled, closed and expired targets do not resolve.
func (b *Backend) InputNode(target ui.InputTarget) (InputNode, bool) {
	if b.closed || b.probing {
		return InputNode{}, false
	}
	var best *controlState
	var node Node
	distance := int(^uint(0) >> 1)
	for id, s := range b.states {
		d := target.Distance(s.handle)
		if d < 0 || d >= distance {
			continue
		}
		if !b.inputNodeAvailable(id) {
			continue
		}
		n := b.nodes[id]
		best, node, distance = s, n, d
	}
	if best == nil {
		return InputNode{}, false
	}
	return InputNode{Node: node.clone(), backend: b, identity: best.identity}, true
}

func (b *Backend) inputNodeAvailable(id int64) bool {
	for id != 0 {
		n, ok := b.nodes[id]
		if !ok || n.String("display") == "none" || n.Props["enabled"] == false || n.Bool("inert") {
			return false
		}
		id = n.Parent
	}
	return true
}
