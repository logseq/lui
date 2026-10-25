// Package luimygo renders LUI patch batches with MyGo native UI.
// Backend methods belong to the UI goroutine. Runtime serializes C ABI calls
// on a dedicated OS thread and delivers copied batches back to that goroutine.
package luimygo

import (
	"fmt"
	"maps"
	"slices"
	"time"

	"github.com/egoist/mygo/ui"
)

type Operation struct {
	Op          string `json:"op"`
	ID          int64  `json:"id,omitempty"`
	Parent      int64  `json:"parent,omitempty"`
	Child       int64  `json:"child,omitempty"`
	Index       int    `json:"index"`
	Kind        string `json:"kind,omitempty"`
	Property    string `json:"property,omitempty"`
	Identifier  string `json:"identifier,omitempty"`
	Fingerprint string `json:"fingerprint"`
	Value       any    `json:"value,omitempty"`
}
type Batch struct {
	Generation int64       `json:"generation"`
	Ops        []Operation `json:"ops"`
}

// Node is a detached read snapshot. Parent is zero for a root; wire IDs are positive.
type Node struct {
	ID                            int64
	Kind, Identifier, Fingerprint string
	Parent                        int64
	Children                      []int64
	Props                         map[string]any
}

func (n Node) String(k string) string { s, _ := n.Props[k].(string); return s }
func (n Node) Bool(k string) bool     { v, _ := n.Props[k].(bool); return v }
func (n Node) Number(k string, fallback float64) float64 {
	v, ok := number(n.Props[k])
	if !ok {
		return fallback
	}
	return v
}
func (n Node) clone() Node {
	n.Children = slices.Clone(n.Children)
	n.Props = maps.Clone(n.Props)
	return n
}

type Event struct {
	Kind        string         `json:"kind"`
	Node        int64          `json:"node"`
	Text        string         `json:"text,omitempty"`
	Checked     bool           `json:"checked,omitempty"`
	Value       float64        `json:"value,omitempty"`
	Modifiers   int32          `json:"modifiers,omitempty"`
	Identifier  string         `json:"identifier,omitempty"`
	Name        string         `json:"name,omitempty"`
	Values      map[string]any `json:"values,omitempty"`
	X           float64        `json:"x,omitempty"`
	Y           float64        `json:"y,omitempty"`
	Button      int32          `json:"button,omitempty"`
	TargetClass string         `json:"target-class,omitempty"`
	Token       int64          `json:"token,omitempty"`
	Outcome     string         `json:"outcome,omitempty"`
	First       int64          `json:"first"`
	Last        int64          `json:"last"`
	AtStart     bool           `json:"at-start"`
	AtEnd       bool           `json:"at-end"`
	Key         string         `json:"key,omitempty"`
	Shift       bool           `json:"shift,omitempty"`
	Payload     string         `json:"payload,omitempty"`
	incarnation uint64
}

// Renderer builds a custom control, calling children within its container.
// emit queues an event for delivery after construction; never retain Context.
type Renderer func(*ui.Context, Node, func(), func(Event))
type Extension struct {
	Fingerprint string
	Defaults    map[string]any
	Render      Renderer
}
type Config struct {
	FileServices FileServices
	// Dispatch synchronously delivers a model-owned interaction proposal.
	// Apply accepted or normalized property updates before returning. If the
	// controlled property is unchanged, the native proposal is rejected.
	Dispatch   func(Event) error
	Extensions map[string]Extension
	// Renderers deliberately overrides built-in standard component behavior.
	Renderers map[string]Renderer
}
type controlState struct {
	collection        collectionState
	layout            layoutState
	pressedAt         time.Time
	longPressFired    bool
	lastPointer       Event
	text              string
	checked           bool
	value             float64
	appeared, focused bool
	identity          uint64
	handle            ui.Handle
	resource          nodeResourceState
	hovered           bool
	scroll            ui.ScrollState
}
type Backend struct {
	closed            bool
	files             fileStore
	config            Config
	nodes             map[int64]Node
	generation        int64
	states            map[int64]*controlState
	err               error
	nextIdentity      uint64
	building          bool
	probing           bool
	queued            []Event
	widgets           map[int64]*widgetState
	resources         resourceStore
	widgetToastsBuilt bool
	tokens            map[string]any
	systemTheme       *ui.Theme
}

func New(config Config) *Backend {
	config.Extensions = maps.Clone(config.Extensions)
	for name, e := range config.Extensions {
		e.Defaults = maps.Clone(e.Defaults)
		config.Extensions[name] = e
	}
	config.Renderers = maps.Clone(config.Renderers)
	return &Backend{config: config, nodes: map[int64]Node{}, states: map[int64]*controlState{}}
}
func (b *Backend) Node(id int64) (Node, bool) { n, ok := b.nodes[id]; return n.clone(), ok }
func (b *Backend) Roots() []int64 {
	roots := []int64{}
	for id, n := range b.nodes {
		if n.Parent == 0 {
			roots = append(roots, id)
		}
	}
	slices.Sort(roots)
	return roots
}
func (b *Backend) Generation() int64 { return b.generation }

// Err reports the first asynchronous event-dispatch failure.
func (b *Backend) Err() error { return b.err }

// Close releases node services and registered host resources. Call it on the
// UI goroutine after closing the OCaml session; repeated calls are harmless.
func (b *Backend) Close() {
	if b.closed {
		return
	}
	b.closed = true
	b.closeFiles()
	b.closeResources()
	b.resetWidgets()
	clear(b.nodes)
	clear(b.states)
	b.queued = nil
}
func (b *Backend) ApplyJSON(data []byte, snapshot bool) error {
	batch, err := DecodeBatch(data)
	if err != nil {
		return err
	}
	if snapshot {
		return b.ApplySnapshot(batch)
	}
	return b.ApplyBatch(batch)
}
func (b *Backend) ApplySnapshot(batch Batch) error { return b.apply(batch, true) }
func (b *Backend) ApplyBatch(batch Batch) error    { return b.apply(batch, false) }
func (b *Backend) apply(batch Batch, snapshot bool) error {
	if b.closed {
		return fmt.Errorf("lui: backend is closed")
	}
	if batch.Generation < 1 || (!snapshot && batch.Generation != b.generation+1) {
		return fmt.Errorf("lui: expected generation %d, received %d", b.generation+1, batch.Generation)
	}
	// Journal original nodes for rollback; clone their mutable data only before
	// a write. Pure deletion keeps the originals without copying discarded data.
	oldNodes := b.nodes
	if snapshot {
		b.nodes = map[int64]Node{}
	}
	previous := map[int64]Node{}
	existed := map[int64]bool{}
	retired := map[int64]bool{}
	remember := func(id int64) bool {
		if _, ok := existed[id]; ok {
			return false
		}
		n, ok := b.nodes[id]
		previous[id] = n
		existed[id] = ok
		return true
	}
	touch := func(id int64) {
		if remember(id) && existed[id] {
			b.nodes[id] = b.nodes[id].clone()
		}
	}
	rollback := func() {
		if snapshot {
			b.nodes = oldNodes
			return
		}
		for id, n := range previous {
			if existed[id] {
				b.nodes[id] = n
			} else {
				delete(b.nodes, id)
			}
		}
	}
	for i, op := range batch.Ops {
		if err := b.applyOp(op, touch, remember, retired); err != nil {
			rollback()
			return fmt.Errorf("lui: operation %d (%s): %w", i, op.Op, err)
		}
	}
	// Validate complete final contracts, permitting arbitrary property order and
	// transient incompleteness within one atomic wire batch.
	for id := range previous {
		n, exists := b.nodes[id]
		if !exists || n.Kind == "extension" {
			continue
		}
		if err := validateNode(n); err != nil {
			rollback()
			return fmt.Errorf("lui: node %d (%s): %w", id, n.Kind, err)
		}
	}
	b.generation = batch.Generation
	if snapshot {
		b.resetFiles()
		b.resetResources()
		b.resetWidgets()
		b.states = map[int64]*controlState{}
	} else {
		for id := range retired {
			b.retireFile(id)
			b.retireResource(id)
			b.retireWidget(id)
			delete(b.states, id)
		}
	}
	for _, op := range batch.Ops {
		if s := b.states[op.ID]; s != nil {
			n, ok := b.nodes[op.ID]
			if !ok {
				continue
			}
			switch op.Property {
			case "text":
				s.text = n.String("text")
			case "checked", "selected", "expanded":
				s.checked = n.Bool(op.Property)
			case "value":
				s.value = n.Number("value", 0)
			}
		}
	}
	return nil
}
func (b *Backend) applyOp(op Operation, touch func(int64), remember func(int64) bool, retired map[int64]bool) error {
	node := func(id int64) (Node, error) {
		n, ok := b.nodes[id]
		if !ok {
			return n, fmt.Errorf("unknown node %d", id)
		}
		return n, nil
	}
	switch op.Op {
	case "create-node", "create-extension":
		if op.ID <= 0 {
			return fmt.Errorf("node ID must be positive")
		}
		if _, ok := b.nodes[op.ID]; ok {
			return fmt.Errorf("duplicate node %d", op.ID)
		}
		n := Node{ID: op.ID, Kind: op.Kind, Props: map[string]any{}}
		if op.Op == "create-extension" {
			ext, ok := b.config.Extensions[op.Identifier]
			if !ok || ext.Render == nil {
				return fmt.Errorf("unregistered extension %q", op.Identifier)
			}
			if op.Fingerprint != "" && op.Fingerprint != ext.Fingerprint {
				return fmt.Errorf("extension fingerprint mismatch")
			}
			n.Kind = "extension"
			n.Identifier = op.Identifier
			n.Fingerprint = ext.Fingerprint
			n.Props = maps.Clone(ext.Defaults)
			if n.Props == nil {
				n.Props = map[string]any{}
			}
			for name, value := range n.Props {
				if err := validateValue(name, value, true); err != nil {
					return fmt.Errorf("extension default: %w", err)
				}
			}
		} else {
			if _, ok := wireKinds[op.Kind]; !ok {
				return fmt.Errorf("unknown kind %q", op.Kind)
			}
			if !supportedKind(op.Kind) && b.config.Renderers[op.Kind] == nil {
				return fmt.Errorf("kind %q requires a Config.Renderers registration", op.Kind)
			}
		}
		touch(op.ID)
		b.nodes[op.ID] = n
	case "set-prop", "remove-prop", "set-extension-prop", "remove-extension-prop":
		n, err := node(op.ID)
		if err != nil {
			return err
		}
		extension := op.Op == "set-extension-prop" || op.Op == "remove-extension-prop"
		if extension != (n.Kind == "extension") {
			return fmt.Errorf("property namespace does not match node")
		}
		if op.Property == "" {
			return fmt.Errorf("empty property")
		}
		if !extension {
			if _, ok := wireProperties[op.Property]; !ok {
				return fmt.Errorf("unknown property %q", op.Property)
			}
			if !propertySupported(n.Kind, op.Property) {
				return fmt.Errorf("property %q is unsupported on %s", op.Property, n.Kind)
			}
		}
		setting := op.Op == "set-prop" || op.Op == "set-extension-prop"
		if setting {
			if err := validateValue(op.Property, op.Value, extension); err != nil {
				return err
			}
		}
		touch(op.ID)
		n = b.nodes[op.ID]
		if setting {
			n.Props[op.Property] = op.Value
		} else {
			delete(n.Props, op.Property)
			if extension {
				if v, ok := b.config.Extensions[n.Identifier].Defaults[op.Property]; ok {
					n.Props[op.Property] = v
				}
			}
		}
		b.nodes[op.ID] = n
	case "insert-child", "remove-child", "move-child":
		p, err := node(op.Parent)
		if err != nil {
			return err
		}
		ch, err := node(op.Child)
		if err != nil {
			return err
		}
		index := -1
		if op.Op != "insert-child" {
			index = slices.Index(p.Children, op.Child)
		}
		switch op.Op {
		case "insert-child":
			if p.Kind != "extension" && ch.Kind != "extension" && !childKindSupported(p.Kind, ch.Kind) {
				return fmt.Errorf("kind %s cannot contain %s", p.Kind, ch.Kind)
			}
			if p.Kind != "extension" && ch.Kind == "extension" && !wireKinds[p.Kind] {
				return fmt.Errorf("kind %s cannot contain extensions", p.Kind)
			}
			// Committed mutations keep both sides of the parent link in sync.
			// Parent alone proves attachment without scanning every sibling.
			if ch.Parent != 0 {
				return fmt.Errorf("child already attached")
			}
			if op.Index < 0 || op.Index > len(p.Children) {
				return fmt.Errorf("child index out of bounds")
			}
			// Walk upwards rather than scanning the inserted subtree.
			for id := p.ID; id != 0; id = b.nodes[id].Parent {
				if id == ch.ID {
					return fmt.Errorf("child insertion creates a cycle")
				}
			}
			touch(p.ID)
			touch(ch.ID)
			p = b.nodes[p.ID]
			ch = b.nodes[ch.ID]
			p.Children = slices.Insert(p.Children, op.Index, ch.ID)
			ch.Parent = p.ID
		case "remove-child":
			if index < 0 || ch.Parent != p.ID {
				return fmt.Errorf("child is not attached to parent")
			}
			touch(p.ID)
			touch(ch.ID)
			p = b.nodes[p.ID]
			ch = b.nodes[ch.ID]
			p.Children = slices.Delete(p.Children, index, index+1)
			ch.Parent = 0
		case "move-child":
			if index < 0 || ch.Parent != p.ID {
				return fmt.Errorf("child is not attached to parent")
			}
			if op.Index < 0 || op.Index >= len(p.Children) {
				return fmt.Errorf("child index out of bounds")
			}
			touch(p.ID)
			p = b.nodes[p.ID]
			p.Children = slices.Delete(p.Children, index, index+1)
			p.Children = slices.Insert(p.Children, op.Index, ch.ID)
		}
		b.nodes[p.ID] = p
		b.nodes[ch.ID] = ch
	case "drop-node":
		n, err := node(op.ID)
		if err != nil {
			return err
		}
		if n.Parent != 0 || len(n.Children) > 0 {
			return fmt.Errorf("cannot drop attached node")
		}
		remember(op.ID)
		delete(b.nodes, op.ID)
		retired[op.ID] = true
	case "detach-subtree":
		n, err := node(op.ID)
		if err != nil {
			return err
		}
		if n.Parent != 0 {
			touch(n.Parent)
			p := b.nodes[n.Parent]
			i := slices.Index(p.Children, n.ID)
			p.Children = slices.Delete(p.Children, i, i+1)
			b.nodes[p.ID] = p
		}
		pending := []int64{op.ID}
		for len(pending) > 0 {
			id := pending[len(pending)-1]
			pending = pending[:len(pending)-1]
			pending = append(pending, b.nodes[id].Children...)
			remember(id)
			delete(b.nodes, id)
			retired[id] = true
		}
	default:
		return fmt.Errorf("unknown patch operation %q", op.Op)
	}
	return nil
}
