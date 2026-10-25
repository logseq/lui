package luimygo

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"strings"
)

const (
	scalarString uint8 = 1 << iota
	scalarInt
	scalarFloat
	scalarBool
)

// DecodeBatch keeps integer IDs exact, including IDs beyond JavaScript's
// float64 integer range. Required fields must be present even when zero.
func DecodeBatch(data []byte) (Batch, error) {
	var raw struct {
		Generation *int64             `json:"generation"`
		Ops        *[]json.RawMessage `json:"ops"`
	}
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	if err := dec.Decode(&raw); err != nil {
		return Batch{}, fmt.Errorf("lui: decode batch: %w", err)
	}
	if raw.Generation == nil || raw.Ops == nil {
		return Batch{}, fmt.Errorf("lui: batch requires generation and ops")
	}
	var trailing any
	if err := dec.Decode(&trailing); err != io.EOF {
		return Batch{}, fmt.Errorf("lui: trailing data after batch")
	}
	batch := Batch{Generation: *raw.Generation}
	for i, data := range *raw.Ops {
		var fields map[string]json.RawMessage
		if err := json.Unmarshal(data, &fields); err != nil {
			return Batch{}, fmt.Errorf("lui: operation %d: %w", i, err)
		}
		var op Operation
		d := json.NewDecoder(bytes.NewReader(data))
		d.UseNumber()
		if err := d.Decode(&op); err != nil {
			return Batch{}, fmt.Errorf("lui: operation %d: %w", i, err)
		}
		required := []string{"op"}
		switch op.Op {
		case "create-node":
			required = append(required, "id", "kind")
		case "create-extension":
			required = append(required, "id", "identifier", "fingerprint")
		case "drop-node", "detach-subtree":
			required = append(required, "id")
		case "set-prop", "set-extension-prop":
			required = append(required, "id", "property", "value")
		case "remove-prop", "remove-extension-prop":
			required = append(required, "id", "property")
		case "insert-child", "move-child":
			required = append(required, "parent", "child", "index")
		case "remove-child":
			required = append(required, "parent", "child")
		default:
			return Batch{}, fmt.Errorf("lui: unknown patch operation %q", op.Op)
		}
		for _, k := range required {
			value, ok := fields[k]
			if !ok || bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
				return Batch{}, fmt.Errorf("lui: operation %d requires %s", i, k)
			}
		}
		batch.Ops = append(batch.Ops, op)
	}
	return batch, nil
}
func integer(v any) (int64, bool) {
	switch v := v.(type) {
	case int:
		return int64(v), true
	case int32:
		return int64(v), true
	case int64:
		return v, true
	case json.Number:
		n, err := v.Int64()
		return n, err == nil
	default:
		return 0, false
	}
}

func number(v any) (float64, bool) {
	var n float64
	switch v := v.(type) {
	case int:
		n = float64(v)
	case int32:
		n = float64(v)
	case int64:
		n = float64(v)
	case float32:
		n = float64(v)
	case float64:
		n = v
	case json.Number:
		var err error
		n, err = v.Float64()
		if err != nil {
			return 0, false
		}
	default:
		return 0, false
	}
	return n, !math.IsInf(n, 0) && !math.IsNaN(n)
}
func validateValue(property string, v any, extension bool) error {
	var mask uint8
	switch v.(type) {
	case string:
		mask = scalarString
	case bool:
		mask = scalarBool
	default:
		_, ok := number(v)
		if ok {
			mask = scalarFloat
			switch value := v.(type) {
			case int, int32, int64:
				mask |= scalarInt
			case json.Number:
				if _, err := value.Int64(); err == nil {
					mask |= scalarInt
				}
			}
		}
	}
	if mask == 0 {
		return fmt.Errorf("property %s requires a finite scalar", property)
	}
	if extension {
		return nil
	}
	if s, ok := v.(string); ok && strings.HasPrefix(s, "#") {
		colorProperty := strings.Contains(property, "background") || strings.Contains(property, "foreground") || strings.HasSuffix(property, "border") || strings.HasSuffix(property, "border-color")
		if colorProperty && !validHex(s) {
			return fmt.Errorf("invalid hex color for %s", property)
		}
	}
	if property == "theme" {
		s, ok := v.(string)
		if !ok {
			return fmt.Errorf("theme requires a string")
		}
		_, err := decodeTokens(s)
		return err
	}
	if property == "theme-mode" {
		if v != "system" && v != "light" && v != "dark" {
			return fmt.Errorf("invalid theme mode")
		}
	}
	if wireProperties[property]&mask == 0 {
		return fmt.Errorf("invalid scalar type for %s", property)
	}
	if n, ok := number(v); ok {
		if math.Abs(n) > math.MaxFloat32 {
			return fmt.Errorf("%s exceeds native layout numeric range", property)
		}
		nonnegative := property == "gap" || property == "columns" || strings.HasPrefix(property, "padding") || strings.HasPrefix(property, "min-") || strings.HasPrefix(property, "max-") || property == "width" || property == "height" || property == "border-width" || property == "corner-radius" || property == "grow"
		if nonnegative && n < 0 {
			return fmt.Errorf("%s must be nonnegative", property)
		}
		if strings.Contains(property, "opacity") && (n < 0 || n > 1) {
			return fmt.Errorf("%s must be between zero and one", property)
		}
		if property == "heading-level" && (n < 1 || n > 6) {
			return fmt.Errorf("invalid heading-level")
		}
		if property == "step" && n <= 0 {
			return fmt.Errorf("step must be positive")
		}
	}
	return nil
}

func extensionPayload(e Event) (string, error) {
	if e.Kind != "extension-event" {
		return "", nil
	}
	if e.Identifier == "" || e.Name == "" {
		return "", fmt.Errorf("lui: extension event requires identifier and name")
	}
	for k, v := range e.Values {
		if err := validateValue(k, v, true); err != nil {
			return "", err
		}
	}
	data, err := json.Marshal(e.Values)
	if err != nil {
		return "", err
	}
	if e.Values == nil {
		return "{}", nil
	}
	return string(data), nil
}
