package luimygo

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"
)

func TestDecodeBatchPresenceAndScalarCompatibility(t *testing.T) {
	for _, text := range []string{
		`{"op":"create-node","id":0,"kind":""}`,
		`{"op":"create-extension","id":0,"identifier":"","fingerprint":""}`,
		`{"op":"drop-node","id":0}`, `{"op":"detach-subtree","id":0}`,
		`{"op":"set-prop","id":0,"property":"","value":false}`,
		`{"op":"set-extension-prop","id":0,"property":"","value":0}`,
		`{"op":"remove-prop","id":0,"property":""}`,
		`{"op":"remove-extension-prop","id":0,"property":""}`,
		`{"op":"insert-child","parent":0,"child":0,"index":0}`,
		`{"op":"move-child","parent":0,"child":0,"index":0}`,
		`{"op":"remove-child","parent":0,"child":0}`,
	} {
		var fields map[string]json.RawMessage
		if err := json.Unmarshal([]byte(text), &fields); err != nil {
			t.Fatal(err)
		}
		decode := func(op string) error {
			_, err := DecodeBatch([]byte(`{"generation":0,"ops":[` + op + `]}`))
			return err
		}
		if err := decode(text); err != nil {
			t.Fatalf("present zero/empty fields must decode: %s: %v", text, err)
		}
		for key, value := range fields {
			delete(fields, key)
			missing, _ := json.Marshal(fields)
			if err := decode(string(missing)); err == nil {
				t.Fatalf("accepted missing %s: %s", key, missing)
			}
			fields[key] = json.RawMessage("null")
			null, _ := json.Marshal(fields)
			if err := decode(string(null)); err == nil {
				t.Fatalf("accepted null %s: %s", key, null)
			}
			fields[key] = value
		}
	}
	for _, value := range []string{`true`, `false`, `"123"`, `"你好\u0000👋"`, `9007199254740993`, `-9223372036854775808`, `1.25`, `[1,{"x":9007199254740993}]`, `{"x":[false,2]}`} {
		batch, err := DecodeBatch([]byte(`{"generation":9223372036854775807,"ops":[{"op":"set-prop","id":9007199254740993,"property":"value","value":` + value + `}]}`))
		if err != nil {
			t.Fatal(value, err)
		}
		var expected any
		d := json.NewDecoder(strings.NewReader(value))
		d.UseNumber()
		if err := d.Decode(&expected); err != nil {
			t.Fatal(err)
		}
		if batch.Generation != 9223372036854775807 || batch.Ops[0].ID != 9007199254740993 || !reflect.DeepEqual(batch.Ops[0].Value, expected) {
			t.Fatalf("scalar changed: %+v vs %#v", batch, expected)
		}
	}
}

func TestDecodeBatchMalformedAndCompatibilityPolicies(t *testing.T) {
	valid := []string{
		`{"generation":1,"ops":[]}`,
		`{"generation":1,"unknown":{"nested":[1]},"ops":[{"op":"drop-node","id":1,"extra":false}]}`,
		`{"generation":1,"generation":2,"ops":[{"op":"drop-node","id":1,"id":2}]}`,
		`{"generation":1,"ops":[{"op":"drop-node","id":1}],"ops":[]}`,
		`{"Generation":1,"OPS":[]}`,
		`{"generation":1,"ops":[{"op":"drop-node","OP":"detach-subtree","id":1,"ID":2}]}`,
	}
	for _, text := range valid {
		if _, err := DecodeBatch([]byte(text)); err != nil {
			t.Fatalf("compatibility policy rejected %s: %v", text, err)
		}
	}
	batch, err := DecodeBatch([]byte(valid[2]))
	if err != nil || batch.Generation != 2 || batch.Ops[0].ID != 2 {
		t.Fatalf("duplicate fields must keep last values: %+v %v", batch, err)
	}
	batch, err = DecodeBatch([]byte(valid[5]))
	if err != nil || batch.Ops[0].Op != "detach-subtree" || batch.Ops[0].ID != 2 {
		t.Fatalf("case-folding of existing fields changed: %+v %v", batch, err)
	}
	for _, text := range []string{
		``, `null`, `[]`, `{}`, `{"generation":1}`, `{"ops":[]}`, `{"generation":null,"ops":[]}`,
		`{"generation":1,"ops":null}`, `{"generation":1,"ops":{}}`, `{"generation":1,"ops":[null]}`,
		`{"generation":1,"ops":[[]]}`, `{"generation":1,"ops":[{}]}`, `{"generation":1,"ops":[{"op":"invented"}]}`,
		`{"generation":1,"ops":[]} {}`, `{"generation":1,"ops":[]} trailing`, `{"generation":1,"ops":[`,
		`{"generation":9223372036854775808,"ops":[]}`, `{"generation":1.0,"ops":[]}`, `{"generation":"1","ops":[]}`,
		`{"generation":1,"ops":[{"op":"drop-node","id":9223372036854775808}]}`,
		`{"generation":1,"ops":[{"op":"drop-node","id":-9223372036854775809}]}`,
		`{"generation":1,"ops":[{"op":"drop-node","id":1.0}]}`, `{"generation":1,"ops":[{"op":"drop-node","id":"1"}]}`,
		`{"generation":1,"ops":[{"op":"drop-node","id":false}]}`, `{"generation":1,"ops":[{"op":"drop-node","id":1,"index":false}]}`,
		`{"generation":1,"ops":[{"op":"drop-node","id":1,"id":null}]}`,
		`{"generation":1,"ops":[{"OP":"drop-node","id":1}]}`,
		`{"generation":1,"ops":[{"op":"drop-node","ID":1}]}`,
		`{"generation":1,"ops":[{"op":"drop-node","id":1}],"ops":null}`,
	} {
		if _, err := DecodeBatch([]byte(text)); err == nil {
			t.Fatalf("accepted malformed/missing required fields: %s", text)
		}
	}
}

func TestDecodeBatchJSONFieldFoldingAndEmptyShape(t *testing.T) {
	for _, text := range []string{`{"generation":1,"ops":[]}`, `{"generation":1,"opſ":[]}`, `{"generation":1,"ops":[{"op":"drop-node","id":1}],"ops":[]}`} {
		batch, err := DecodeBatch([]byte(text))
		if err != nil || batch.Generation != 1 || batch.Ops != nil {
			t.Fatalf("empty batch shape or Unicode folding changed: %+v %v", batch, err)
		}
	}
	for _, text := range []string{`{"op":"create-node","id":1,"kind":"box","Kind":"text"}`, `{"op":"drop-node","id":1,"İD":2}`, `{"op":"drop-node","id":1,"ID":null}`,
		`{"op":"set-prop","id":1,"property":"value","value":{"a":1},"value":{"b":2}}`,
		`{"op":"set-prop","id":1,"property":"value","value":[1,2],"Value":[3]}`,
		`{"op":"set-prop","id":1,"property":"value","value":1,"Value":null}`,
	} {
		var expected Operation
		d := json.NewDecoder(strings.NewReader(text))
		d.UseNumber()
		if err := d.Decode(&expected); err != nil {
			t.Fatal(err)
		}
		batch, err := DecodeBatch([]byte(`{"generation":1,"ops":[` + text + `]}`))
		if err != nil || len(batch.Ops) != 1 || !reflect.DeepEqual(batch.Ops[0], expected) {
			t.Fatalf("field assignment differs from encoding/json: %+v vs %+v: %v", batch, expected, err)
		}
	}
}
