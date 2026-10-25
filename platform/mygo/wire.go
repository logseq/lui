package luimygo

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"strconv"
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
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	opening, err := dec.Token()
	if err != nil || opening != json.Delim('{') {
		return Batch{}, fmt.Errorf("lui: batch requires an object: %v", err)
	}
	var generation *int64
	var batch Batch
	var hasOps bool
	// Canonical wire uses one "op" key per operation. This is only a capacity
	// hint: escaped keys, unknown fields and duplicates retain normal semantics.
	capacity := min(bytes.Count(data, []byte(`"op"`)), len(data)/48)
	for dec.More() {
		key, err := dec.Token()
		if err != nil {
			return Batch{}, fmt.Errorf("lui: decode batch: %w", err)
		}
		switch {
		case strings.EqualFold(key.(string), "generation"):
			if err := dec.Decode(&generation); err != nil {
				return Batch{}, fmt.Errorf("lui: decode generation: %w", err)
			}
		case strings.EqualFold(key.(string), "ops"):
			opening, err := dec.Token()
			if err != nil {
				return Batch{}, fmt.Errorf("lui: decode ops: %w", err)
			}
			batch.Ops, hasOps = nil, opening != nil
			if opening == nil {
				continue
			}
			if opening != json.Delim('[') {
				return Batch{}, fmt.Errorf("lui: ops requires an array")
			}
			if dec.More() {
				batch.Ops = make([]Operation, 0, capacity)
			}
			for dec.More() {
				op, err := decodeOperation(dec)
				if err != nil {
					return Batch{}, fmt.Errorf("lui: operation %d: %w", len(batch.Ops), err)
				}
				batch.Ops = append(batch.Ops, op)
			}
			if _, err := dec.Token(); err != nil {
				return Batch{}, fmt.Errorf("lui: decode ops: %w", err)
			}
		default:
			var ignored any
			if err := dec.Decode(&ignored); err != nil {
				return Batch{}, fmt.Errorf("lui: decode batch field: %w", err)
			}
		}
	}
	if _, err := dec.Token(); err != nil {
		return Batch{}, fmt.Errorf("lui: decode batch: %w", err)
	}
	if generation == nil || !hasOps {
		return Batch{}, fmt.Errorf("lui: batch requires generation and ops")
	}
	var trailing any
	if err := dec.Decode(&trailing); err != io.EOF {
		return Batch{}, fmt.Errorf("lui: trailing data after batch")
	}
	batch.Generation = *generation
	return batch, nil
}

func decodeOperation(dec *json.Decoder) (Operation, error) {
	var op Operation
	opening, err := dec.Token()
	if err != nil || opening != json.Delim('{') {
		return op, fmt.Errorf("patch operation requires an object: %v", err)
	}
	// Required presence uses exact wire names; field assignment remains case
	// insensitive, matching encoding/json and the original decoder.
	const (
		fieldOp uint16 = 1 << iota
		fieldID
		fieldKind
		fieldIdentifier
		fieldFingerprint
		fieldProperty
		fieldValue
		fieldParent
		fieldChild
		fieldIndex
	)
	var present uint16
	for dec.More() {
		key, err := dec.Token()
		if err != nil {
			return op, err
		}
		name := key.(string)
		var value any
		if err := dec.Decode(&value); err != nil {
			return op, err
		}
		var bit uint16
		var targetString *string
		var targetInt *int64
		field := operationField(name)
		switch field {
		case "op":
			bit, targetString = fieldOp, &op.Op
		case "id":
			bit, targetInt = fieldID, &op.ID
		case "kind":
			bit, targetString = fieldKind, &op.Kind
		case "identifier":
			bit, targetString = fieldIdentifier, &op.Identifier
		case "fingerprint":
			bit, targetString = fieldFingerprint, &op.Fingerprint
		case "property":
			bit, targetString = fieldProperty, &op.Property
		case "value":
			bit, op.Value = fieldValue, value
		case "parent":
			bit, targetInt = fieldParent, &op.Parent
		case "child":
			bit, targetInt = fieldChild, &op.Child
		case "index":
			bit = fieldIndex
			if value != nil {
				n, ok := value.(json.Number)
				if !ok {
					return op, fmt.Errorf("index requires an integer")
				}
				parsed, err := strconv.Atoi(string(n))
				if err != nil {
					return op, err
				}
				op.Index = parsed
			}
		}
		if name == field {
			if value == nil {
				present &^= bit
			} else {
				present |= bit
			}
		}
		if value != nil && targetString != nil {
			parsed, ok := value.(string)
			if !ok {
				return op, fmt.Errorf("%s requires a string", name)
			}
			*targetString = parsed
		}
		if value != nil && targetInt != nil {
			n, ok := value.(json.Number)
			if !ok {
				return op, fmt.Errorf("%s requires an integer", name)
			}
			parsed, err := n.Int64()
			if err != nil {
				return op, err
			}
			*targetInt = parsed
		}
	}
	if _, err := dec.Token(); err != nil {
		return op, err
	}
	required := fieldOp
	switch op.Op {
	case "create-node":
		required |= fieldID | fieldKind
	case "create-extension":
		required |= fieldID | fieldIdentifier | fieldFingerprint
	case "drop-node", "detach-subtree":
		required |= fieldID
	case "set-prop", "set-extension-prop":
		required |= fieldID | fieldProperty | fieldValue
	case "remove-prop", "remove-extension-prop":
		required |= fieldID | fieldProperty
	case "insert-child", "move-child":
		required |= fieldParent | fieldChild | fieldIndex
	case "remove-child":
		required |= fieldParent | fieldChild
	default:
		return op, fmt.Errorf("unknown patch operation %q", op.Op)
	}
	if present&required != required {
		return op, fmt.Errorf("patch operation %q is missing a required non-null field", op.Op)
	}
	return op, nil
}

func operationField(name string) string {
	switch name {
	case "op", "id", "kind", "identifier", "fingerprint", "property", "value", "parent", "child", "index":
		return name
	}
	for _, field := range [...]string{"op", "id", "kind", "identifier", "fingerprint", "property", "value", "parent", "child", "index"} {
		if strings.EqualFold(name, field) {
			return field
		}
	}
	return ""
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
