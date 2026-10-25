// Package luimygo renders LUI patch batches with MyGo native UI.
// Backend methods belong to the UI goroutine. Runtime serializes C ABI calls
// on a dedicated OS thread and delivers copied batches back to that goroutine.
package luimygo

import (
	"bytes"
	"fmt"
	"io"
	"maps"
	"slices"
	"strings"
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
	Generation  int64          `json:"generation,omitempty"`
	Pins        []int64        `json:"pins,omitempty"`
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
	return b.applyJSONReader(bytes.NewReader(data), snapshot)
}

func (b *Backend) applyJSONString(data string, snapshot bool) error {
	return b.applyJSONReader(strings.NewReader(data), snapshot)
}

// JSON fields may be reordered or repeated. Every ops field replaces the prior
// candidate, and only the complete, valid document may commit native effects.
func (b *Backend) applyJSONReader(source io.Reader, snapshot bool) (result error) {
	var transaction *batchTransaction
	var operationError error
	defer func() {
		if result != nil && transaction != nil {
			transaction.rollback()
		}
	}()
	generation, err := decodeBatchInto(source, func() {
		if transaction != nil {
			transaction.rollback()
			transaction = nil
		}
		operationError = nil
		if !b.closed {
			transaction = b.beginTransaction(snapshot)
		}
	}, func(op Operation, index int) {
		// A later duplicate ops array can replace a semantic error. Structural
		// decoding still checks all remaining input before accepting anything.
		if transaction != nil && operationError == nil {
			operationError = transaction.apply(op, index)
		}
	})
	if err != nil {
		return err
	}
	if err := b.checkGeneration(generation, snapshot); err != nil {
		return err
	}
	if operationError != nil {
		return operationError
	}
	return transaction.commit(generation)
}

func (b *Backend) ApplySnapshot(batch Batch) error { return b.apply(batch, true) }
func (b *Backend) ApplyBatch(batch Batch) error    { return b.apply(batch, false) }

func (b *Backend) checkGeneration(generation int64, snapshot bool) error {
	if b.closed {
		return fmt.Errorf("lui: backend is closed")
	}
	if generation < 1 || (!snapshot && generation != b.generation+1) {
		return fmt.Errorf("lui: expected generation %d, received %d", b.generation+1, generation)
	}
	return nil
}

func (b *Backend) apply(batch Batch, snapshot bool) error {
	if err := b.checkGeneration(batch.Generation, snapshot); err != nil {
		return err
	}
	transaction := b.beginTransaction(snapshot)
	for i, op := range batch.Ops {
		if err := transaction.apply(op, i); err != nil {
			transaction.rollback()
			return err
		}
	}
	if err := transaction.commit(batch.Generation); err != nil {
		transaction.rollback()
		return err
	}
	return nil
}

type controlPropertyUpdate struct {
	text, value bool
	checked     string
}

type batchTransaction struct {
	backend      *Backend
	snapshot     bool
	oldNodes     map[int64]Node
	previous     map[int64]Node
	existed      map[int64]bool
	retired      map[int64]bool
	stateUpdates map[int64]controlPropertyUpdate
}

func (b *Backend) beginTransaction(snapshot bool) *batchTransaction {
	transaction := &batchTransaction{
		backend: b, snapshot: snapshot,
		previous: map[int64]Node{}, existed: map[int64]bool{}, retired: map[int64]bool{},
	}
	if snapshot {
		transaction.oldNodes = b.nodes
		b.nodes = map[int64]Node{}
	}
	return transaction
}

// Journal original nodes for rollback; clone their mutable data only before
// a write. Pure deletion keeps the originals without copying discarded data.
func (t *batchTransaction) remember(id int64) bool {
	if _, ok := t.existed[id]; ok {
		return false
	}
	n, ok := t.backend.nodes[id]
	t.previous[id] = n
	t.existed[id] = ok
	return true
}

func (t *batchTransaction) touch(id int64) {
	if t.remember(id) && t.existed[id] {
		t.backend.nodes[id] = t.backend.nodes[id].clone()
	}
}

func (t *batchTransaction) rollback() {
	if t.snapshot {
		t.backend.nodes = t.oldNodes
		return
	}
	for id, n := range t.previous {
		if t.existed[id] {
			t.backend.nodes[id] = n
		} else {
			delete(t.backend.nodes, id)
		}
	}
}

func (t *batchTransaction) apply(op Operation, index int) error {
	b := t.backend
	if err := b.applyOp(op, t.touch, t.remember, t.retired); err != nil {
		return fmt.Errorf("lui: operation %d (%s): %w", index, op.Op, err)
	}
	if t.snapshot || b.states[op.ID] == nil {
		return nil
	}
	update := t.stateUpdates[op.ID]
	switch op.Property {
	case "text":
		update.text = true
	case "checked", "selected", "expanded":
		// These properties share native checked state; the last one wins.
		update.checked = op.Property
	case "value":
		update.value = true
	default:
		return nil
	}
	if t.stateUpdates == nil {
		t.stateUpdates = map[int64]controlPropertyUpdate{}
	}
	t.stateUpdates[op.ID] = update
	return nil
}

func (t *batchTransaction) commit(generation int64) error {
	b := t.backend
	// Validate final contracts, permitting transient incompleteness and any
	// property order within one atomic batch.
	for id := range t.previous {
		n, exists := b.nodes[id]
		if !exists || n.Kind == "extension" {
			continue
		}
		if err := validateNode(n); err != nil {
			return fmt.Errorf("lui: node %d (%s): %w", id, n.Kind, err)
		}
		if err := validateVirtualSource(n); err != nil {
			return err
		}
	}
	b.generation = generation
	if t.snapshot {
		b.resetFiles()
		b.resetResources()
		b.resetWidgets()
		b.states = map[int64]*controlState{}
	} else {
		for id := range t.retired {
			b.retireFile(id)
			b.retireResource(id)
			b.retireWidget(id)
			delete(b.states, id)
		}
	}
	for id, update := range t.stateUpdates {
		if state := b.states[id]; state != nil {
			n, ok := b.nodes[id]
			if !ok {
				continue
			}
			if update.text {
				state.text = n.String("text")
			}
			if update.checked != "" {
				state.checked = n.Bool(update.checked)
			}
			if update.value {
				state.value = n.Number("value", 0)
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
