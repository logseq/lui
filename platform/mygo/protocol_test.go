package luimygo

import (
	"encoding/json"
	"reflect"
	"testing"

	"github.com/egoist/mygo/ui"
)

// Protocol tests isolate validation from widget availability. The rendering
// acceptance suites exercise every standard kind without these overrides.
func protocolBackend() *Backend {
	renderers := make(map[string]Renderer, len(wireKinds))
	for kind := range wireKinds {
		renderers[kind] = func(*ui.Context, Node, func(), func(Event)) {}
	}
	return New(Config{Renderers: renderers})
}

func TestProtocolRejectsInvalidNodeContractsAtomically(t *testing.T) {
	cases := []struct {
		name string
		ops  []Operation
	}{
		{"wrong property for kind", []Operation{create(2, "text"), prop(2, "url", "https://example.test")}},
		{"invalid orientation", []Operation{create(2, "row"), prop(2, "orientation", "diagonal")}},
		{"invalid font weight", []Operation{create(2, "text"), prop(2, "font-weight", 0)}},
		{"invalid whitespace", []Operation{create(2, "text"), prop(2, "white-space", "mystery")}},
		{"missing accessible button name", []Operation{create(2, "button")}},
		{"empty accessible button name", []Operation{create(2, "button"), prop(2, "text", "")}},
		{"inconsistent size constraints", []Operation{create(2, "box"), prop(2, "min-width", 100), prop(2, "max-width", 20)}},
		{"inconsistent number bounds", []Operation{create(2, "number-stepper"), prop(2, "accessibility-label", "Count"), prop(2, "value", 2.0), prop(2, "min", 5.0), prop(2, "max", 3.0)}},
		{"fraction and pixels together", []Operation{create(2, "split"), prop(2, "value", 0.5), prop(2, "first-pane-width", 120.0)}},
		{"incomplete source crop", []Operation{create(2, "image"), prop(2, "image", 1), prop(2, "source-x", 0.0)}},
		{"incomplete popup point", []Operation{create(2, "popover"), prop(2, "x", 10.0)}},
		{"exclusive popup anchors", []Operation{create(2, "popover"), prop(2, "anchor", "below"), prop(2, "anchor-target", "trigger"), prop(2, "anchor-rect", "0 0 20 20")}},
		{"invalid source width", []Operation{create(2, "image"), prop(2, "image", 1), prop(2, "source-x", 0.0), prop(2, "source-y", 0.0), prop(2, "source-width", -1.0), prop(2, "source-height", 10.0)}},
		{"nonempty resource path", []Operation{create(2, "file-image"), prop(2, "path", "")}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			b := protocolBackend()
			apply(t, b, 1, create(1, "root"), prop(1, "padding", 4))
			ops := append([]Operation{prop(1, "padding", 9)}, tc.ops...)
			if err := b.ApplyBatch(Batch{Generation: 2, Ops: ops}); err == nil {
				t.Fatal("accepted an invalid final node contract")
			}
			root, _ := b.Node(1)
			if root.Number("padding", 0) != 4 || b.Generation() != 1 {
				t.Fatal("validation failure committed a preceding mutation")
			}
			if _, ok := b.Node(2); ok {
				t.Fatal("validation failure leaked the new node")
			}
		})
	}
}

func TestProtocolAllowsCompleteFinalContractInAnyOperationOrder(t *testing.T) {
	b := protocolBackend()
	apply(t, b, 1,
		create(1, "root"), create(2, "button"), insert(1, 2, 0),
		prop(2, "text", "Save"), prop(2, "min-width", 10), prop(2, "max-width", 80), prop(2, "width", 60),
	)
	apply(t, b, 2,
		prop(2, "max-width", 40), prop(2, "width", 30),
		Operation{Op: "remove-prop", ID: 2, Property: "text"}, prop(2, "accessibility-label", "Save"),
	)
	button, _ := b.Node(2)
	if button.String("accessibility-label") != "Save" || button.Number("width", 0) != 30 {
		t.Fatal("a valid final contract did not commit")
	}
	if err := b.ApplyBatch(Batch{Generation: 3, Ops: []Operation{{Op: "remove-prop", ID: 2, Property: "accessibility-label"}}}); err == nil {
		t.Fatal("removed the final accessible name")
	}
	button, _ = b.Node(2)
	if button.String("accessibility-label") != "Save" {
		t.Fatal("rejected removal changed the accessible name")
	}
}

func TestProtocolChildContracts(t *testing.T) {
	for _, tc := range []struct {
		parent, child string
		accepted      bool
	}{
		{"text-field", "context-menu", true},
		{"checkbox", "context-menu", true},
		{"text-field", "button", false},
		{"bottom-tabs", "button", false},
		{"table", "text", false},
		{"table-row", "button", false},
		{"stepper", "text", false},
		{"timeline", "button", false},
		{"context-menu", "text", false},
		{"row", "root", false},
	} {
		t.Run(tc.parent+"/"+tc.child, func(t *testing.T) {
			b := protocolBackend()
			ops := []Operation{create(1, tc.parent), create(2, tc.child)}
			for id, kind := range map[int64]string{1: tc.parent, 2: tc.child} {
				switch kind {
				case "button", "checkbox":
					ops = append(ops, prop(id, "text", "Item"))
				case "bottom-tabs":
					ops = append(ops, prop(id, "accessibility-label", "Sections"))
				case "stepper":
					ops = append(ops, prop(id, "active", 0))
				}
			}
			ops = append(ops, insert(1, 2, 0))
			err := b.ApplyBatch(Batch{Generation: 1, Ops: ops})
			if (err == nil) != tc.accepted {
				t.Fatalf("child contract accepted=%v, expected %v: %v", err == nil, tc.accepted, err)
			}
			if !tc.accepted && (b.Generation() != 0 || len(b.Roots()) != 0) {
				t.Fatal("rejected child insertion changed the tree")
			}
		})
	}
}

func TestProtocolSnapshotInvalidFinalContractPreservesLiveTree(t *testing.T) {
	b := protocolBackend()
	apply(t, b, 1, create(1, "root"), create(2, "text"), prop(2, "text", "Live"), insert(1, 2, 0))
	before, _ := b.Node(2)
	err := b.ApplySnapshot(Batch{Generation: 90, Ops: []Operation{create(3, "button")}})
	if err == nil {
		t.Fatal("accepted invalid authoritative snapshot")
	}
	after, _ := b.Node(2)
	if !reflect.DeepEqual(before, after) || b.Generation() != 1 {
		t.Fatal("invalid snapshot replaced the live tree")
	}
}

func TestProtocolTypedVirtualTuning(t *testing.T) {
	b := protocolBackend()
	payload := []byte(`{"generation":1,"ops":[{"op":"create-node","id":1,"kind":"virtual-list"},{"op":"set-prop","id":1,"property":"overscan","value":0},{"op":"set-prop","id":1,"property":"item-extent","value":24.0}]}`)
	if err := b.ApplyJSON(payload, false); err != nil {
		t.Fatalf("typed collection tuning did not reach the native host: %v", err)
	}
	before, _ := b.Node(1)
	for _, bad := range []Operation{prop(1, "overscan", -1), prop(1, "overscan", 1.5), prop(1, "item-extent", 0.0)} {
		if err := b.ApplyBatch(Batch{Generation: 2, Ops: []Operation{bad}}); err == nil {
			t.Fatalf("accepted invalid collection tuning: %+v", bad)
		}
		after, _ := b.Node(1)
		if !reflect.DeepEqual(before, after) {
			t.Fatal("invalid tuning changed the list")
		}
	}
	data, err := json.Marshal(before.Props)
	if err != nil || len(data) == 0 {
		t.Fatal("typed native properties were not retained")
	}
}
