package luimygo

import (
	"encoding/json"
	"os"
	"strconv"
	"testing"
)

type oracleValue struct {
	Type  string `json:"type"`
	Value any    `json:"value"`
}

func (v oracleValue) wire(t *testing.T) contractWireValue {
	t.Helper()
	switch v.Type {
	case "string":
		return contractWireValue{scalarString, v.Value.(string)}
	case "bool":
		return contractWireValue{scalarBool, v.Value.(bool)}
	case "int":
		return contractWireValue{scalarInt, v.Value.(float64)}
	case "float":
		return contractWireValue{scalarFloat, v.Value.(float64)}
	default:
		t.Fatalf("invalid oracle value type %q", v.Type)
		return contractWireValue{}
	}
}
func (v oracleValue) raw() any {
	if v.Type == "int" {
		return int64(v.Value.(float64))
	}
	return v.Value
}
func oracleVerdict(t *testing.T, bits string, index int) bool {
	t.Helper()
	if index/4 >= len(bits) {
		t.Fatal("truncated oracle")
	}
	nibble, err := strconv.ParseUint(bits[index/4:index/4+1], 16, 8)
	if err != nil {
		t.Fatal(err)
	}
	return nibble&(1<<uint(index%4)) != 0
}

// Expected decisions are produced by the actual linked OCaml validators.
// This checks the native validation boundary, including grammar helpers, across
// every property/kind and complete retained-node combinations.
func TestContractMatchesCanonicalOCamlOracle(t *testing.T) {
	path := os.Getenv("LUI_MYGO_CONTRACT_ORACLE")
	if path == "" {
		t.Skip("requires the temporary oracle produced by generate_mygo_schema.py --export --oracle-output")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var contract struct {
		Oracle struct {
			Values     []oracleValue                `json:"values"`
			Properties map[string]string            `json:"properties"`
			KindValues map[string]map[string]string `json:"kindValues"`
			Nodes      map[string]struct {
				Baseline   map[string]oracleValue `json:"baseline"`
				Properties map[string]string      `json:"properties"`
			} `json:"nodes"`
		} `json:"oracle"`
	}
	if err := json.Unmarshal(data, &contract); err != nil {
		t.Fatal(err)
	}
	oracle := contract.Oracle
	if len(oracle.Values) == 0 || len(oracle.Properties) != len(wireProperties) ||
		len(oracle.KindValues) != len(wireKinds) || len(oracle.Nodes) != len(wireKinds) {
		t.Fatal("incomplete canonical OCaml oracle; regenerate the temporary fixture with --export --oracle-output")
	}
	for property, bits := range oracle.Properties {
		for index, value := range oracle.Values {
			actual := contract_property_value_supported(property, value.wire(t))
			if expected := oracleVerdict(t, bits, index); actual != expected {
				t.Fatalf("scalar %s=%+v: Go=%v OCaml=%v", property, value, actual, expected)
			}
		}
	}
	for kind, properties := range oracle.KindValues {
		for property, bits := range properties {
			for index, value := range oracle.Values {
				actual := contract_property_value_supported_for_kind(kind, property, value.wire(t))
				if expected := oracleVerdict(t, bits, index); actual != expected {
					t.Fatalf("kind scalar %s.%s=%+v: Go=%v OCaml=%v", kind, property, value, actual, expected)
				}
			}
		}
	}
	for kind, fixture := range oracle.Nodes {
		properties := make(map[string]any, len(fixture.Baseline)+1)
		for name, value := range fixture.Baseline {
			properties[name] = value.raw()
		}
		if err := validateNode(Node{ID: 1, Kind: kind, Props: properties}); err != nil {
			t.Fatalf("canonical baseline %s: %v", kind, err)
		}
		for property, bits := range fixture.Properties {
			original, existed := properties[property]
			for index, value := range oracle.Values {
				properties[property] = value.raw()
				actual := validateNode(Node{ID: 1, Kind: kind, Props: properties}) == nil
				expected := oracleVerdict(t, bits, index)
				// Protocol floats can arrive with integer JSON syntax; this
				// test intentionally preserves the oracle's exact scalar tag.
				normalized := value.wire(t)
				if normalized.kind == scalarInt && wireProperties[property]&scalarInt == 0 && wireProperties[property]&scalarFloat != 0 {
					actual = contract_property_value_supported_for_kind(kind, property, normalized) && contract_node_properties_supported(kind, properties)
				}
				if actual != expected {
					t.Fatalf("node %s.%s=%+v: Go=%v OCaml=%v", kind, property, value, actual, expected)
				}
			}
			if existed {
				properties[property] = original
			} else {
				delete(properties, property)
			}
		}
	}
}
