package luimygo

import (
	"reflect"
	"testing"
)

func TestRuntimeReceiveMatchesByteDecodingAndAtomicity(t *testing.T) {
	for _, tc := range []struct {
		name, data string
		snapshot   bool
	}{
		{"generation after ops", `{"ops":[{"op":"set-prop","id":1,"property":"gap","value":8}],"generation":2}`, false},
		{"duplicate generation", `{"generation":99,"generation":2,"ops":[]}`, false},
		{"duplicate ops replace prior semantic errors", `{"generation":2,"ops":[{"op":"set-prop","id":999,"property":"text","value":"ignored"}],"ops":[{"op":"set-prop","id":1,"property":"gap","value":7}]}`, false},
		{"Unicode field folding", `{"Generation":2,"opſ":[{"op":"set-prop","id":1,"property":"gap","value":3}]}`, false},
		{"duplicate operation fields", `{"generation":2,"ops":[{"op":"set-prop","id":99,"ID":1,"property":"gap","value":2,"Value":5}]}`, false},
		{"exact null required field", `{"generation":2,"ops":[{"op":"set-prop","id":1,"property":"gap","value":null}]}`, false},
		{"wrong case required field", `{"generation":2,"ops":[{"OP":"set-prop","id":1,"property":"gap","value":3}]}`, false},
		{"trailing input", `{"generation":2,"ops":[{"op":"set-prop","id":1,"property":"gap","value":9}]} trailing`, false},
		{"rollback preceding property", `{"generation":2,"ops":[{"op":"set-prop","id":1,"property":"gap","value":9},{"op":"set-prop","id":999,"property":"text","value":"invalid"}]}`, false},
		{"exact large ID and embedded NUL", `{"generation":17,"ops":[{"op":"create-node","id":9007199254740993,"kind":"text"},{"op":"set-prop","id":9007199254740993,"property":"text","value":"café\u0000你好 👋"}]}`, true},
		{"invalid snapshot preserves tree", `{"generation":17,"ops":[{"op":"create-node","id":3,"kind":"button"}]}`, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			bytesBackend, stringBackend := New(Config{}), New(Config{})
			defer bytesBackend.Close()
			defer stringBackend.Close()
			for _, b := range []*Backend{bytesBackend, stringBackend} {
				apply(t, b, 1, create(1, "column"), prop(1, "gap", 1))
			}
			byteError := bytesBackend.ApplyJSON([]byte(tc.data), tc.snapshot)
			stringError := (&Runtime{backend: stringBackend}).receive([]string{tc.data}, tc.snapshot)
			if (byteError == nil) != (stringError == nil) {
				t.Fatalf("receive error=%v, byte API error=%v", stringError, byteError)
			}
			if byteError != nil && byteError.Error() != stringError.Error() {
				t.Fatalf("receive error=%v, byte API error=%v", stringError, byteError)
			}
			if bytesBackend.Generation() != stringBackend.Generation() || !reflect.DeepEqual(bytesBackend.Roots(), stringBackend.Roots()) {
				t.Fatal("receive changed generation or root semantics")
			}
			for _, id := range []int64{1, 3, 9007199254740993} {
				want, wantExists := bytesBackend.Node(id)
				got, gotExists := stringBackend.Node(id)
				if wantExists != gotExists || !reflect.DeepEqual(got, want) {
					t.Fatalf("receive changed retained node %d: %+v vs %+v", id, got, want)
				}
			}
		})
	}
}

func TestRuntimeReceiveSnapshotsOnlyItsFirstBatch(t *testing.T) {
	b := New(Config{})
	defer b.Close()
	apply(t, b, 1, create(1, "column"))
	r := Runtime{backend: b}
	batches := []string{
		`{"generation":17,"ops":[{"op":"create-node","id":2,"kind":"text"},{"op":"set-prop","id":2,"property":"text","value":"Snapshot"}]}`,
		`{"generation":18,"ops":[{"op":"set-prop","id":2,"property":"text","value":"Following batch"}]}`,
	}
	if err := r.receive(batches, true); err != nil {
		t.Fatal(err)
	}
	if _, ok := b.Node(1); ok {
		t.Fatal("snapshot did not replace the original tree")
	}
	if n, _ := b.Node(2); n.String("text") != "Following batch" || b.Generation() != 18 {
		t.Fatal("following batch did not apply incrementally")
	}
	batches[0] = `{"generation":19,"ops":[{"op":"set-prop","id":2,"property":"text","value":"Committed"}]}`
	batches[1] = `{"generation":21,"ops":[]}`
	if err := r.receive(batches, false); err == nil {
		t.Fatal("accepted an incremental generation gap")
	}
	if n, _ := b.Node(2); n.String("text") != "Committed" || b.Generation() != 19 {
		t.Fatal("a later invalid batch rolled back a prior committed batch")
	}
}
