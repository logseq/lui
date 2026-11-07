package luimygo

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func decodeFixture(t *testing.T, name string) (Batch, Batch) {
	t.Helper()
	path := filepath.Join("..", "..", "test", "fixtures", "wire", name)
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := DecodeBatch(data)
	if err != nil {
		t.Fatalf("DecodeBatch %s: %v", name, err)
	}
	var expected Batch
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()
	if err := decoder.Decode(&expected); err != nil {
		t.Fatal(err)
	}
	return decoded, expected
}

func TestCanonicalFixtureAgreesWithEncodingJSON(t *testing.T) {
	decoded, expected := decodeFixture(t, "canonical.json")
	if decoded.Generation == 0 || len(decoded.Ops) < 100 {
		t.Fatalf("canonical fixture is unexpectedly small: generation %d ops %d", decoded.Generation, len(decoded.Ops))
	}
	if !reflect.DeepEqual(decoded, expected) {
		t.Fatalf("MyGo decode diverges from encoding/json on the OCaml canonical bytes")
	}
	seen := map[string]bool{}
	for _, op := range decoded.Ops {
		seen[op.Op] = true
	}
	for _, op := range []string{
		"create-node", "create-extension", "drop-node", "detach-subtree",
		"set-prop", "remove-prop", "set-extension-prop", "remove-extension-prop",
		"insert-child", "remove-child", "move-child",
	} {
		if !seen[op] {
			t.Fatalf("canonical fixture never used %s", op)
		}
	}
}

func TestCompatFixtureSkipsNestedUnknownFields(t *testing.T) {
	decoded, expected := decodeFixture(t, "compat.json")
	if !reflect.DeepEqual(decoded, expected) {
		t.Fatalf("compat fixture diverges from encoding/json: %+v vs %+v", decoded, expected)
	}
	if decoded.Generation != 3 || len(decoded.Ops) != 3 {
		t.Fatalf("compat shape changed: %+v", decoded)
	}
	if decoded.Ops[0].Op != "drop-node" || decoded.Ops[0].ID != 1 {
		t.Fatalf("drop-node changed: %+v", decoded.Ops[0])
	}
	if decoded.Ops[1].Value != "你好🌍" || decoded.Ops[2].Property != "opacity" {
		t.Fatalf("scalar values changed: %+v %+v", decoded.Ops[1], decoded.Ops[2])
	}
}
