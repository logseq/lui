package luimygo

import (
	"encoding/json"
	"fmt"
	"math"
	"strconv"
	"strings"
)

// The generated predicates mirror canonical OCaml validators. These helpers
// implement their scalar/map operations and shared string grammars only.
type contractWireValue struct {
	kind  uint8
	value any
}
type contractOptional struct {
	exists bool
	value  contractWireValue
}

func contractValue(value any) contractWireValue {
	switch v := value.(type) {
	case string:
		return contractWireValue{scalarString, v}
	case bool:
		return contractWireValue{scalarBool, v}
	case int:
		return contractWireValue{scalarInt, float64(v)}
	case int32:
		return contractWireValue{scalarInt, float64(v)}
	case int64:
		return contractWireValue{scalarInt, float64(v)}
	case float32:
		return contractWireValue{scalarFloat, float64(v)}
	case float64:
		return contractWireValue{scalarFloat, v}
	case json.Number:
		if n, err := v.Int64(); err == nil {
			return contractWireValue{scalarInt, float64(n)}
		}
		if n, err := v.Float64(); err == nil {
			return contractWireValue{scalarFloat, n}
		}
	}
	return contractWireValue{}
}

func propertySupported(kind, property string) bool { return contractKindProperties[kind][property] }
func childKindSupported(parent, child string) bool { return contractKindChildren[parent][child] }
func eventSupported(kind, event string) bool       { return contractKindEvents[kind][event] }

func propertyValueSupported(kind, property string, value any) bool {
	v := contractValue(value)
	// Go's JSON decoder preserves integer syntax; a canonical floating property
	// may still receive 0 or 1 on the wire, exactly as the existing decoder does.
	if v.kind == scalarInt && wireProperties[property]&scalarInt == 0 && wireProperties[property]&scalarFloat != 0 {
		v.kind = scalarFloat
	}
	return propertySupported(kind, property) && contract_property_value_supported_for_kind(kind, property, v)
}

func validateNode(n Node) error {
	if _, ok := wireKinds[n.Kind]; !ok {
		return fmt.Errorf("lui: unknown node kind %q", n.Kind)
	}
	for name, value := range n.Props {
		if !propertyValueSupported(n.Kind, name, value) {
			return fmt.Errorf("lui: invalid %s property %q on node %d", n.Kind, name, n.ID)
		}
	}
	if !contract_node_properties_supported(n.Kind, n.Props) {
		return fmt.Errorf("lui: invalid final properties for %s node %d", n.Kind, n.ID)
	}
	return nil
}

func contractLookup(property string, properties map[string]any) contractOptional {
	value, exists := properties[property]
	v := contractValue(value)
	if v.kind == scalarInt && wireProperties[property]&scalarInt == 0 && wireProperties[property]&scalarFloat != 0 {
		v.kind = scalarFloat
	}
	return contractOptional{exists, v}
}
func contractMem(property string, properties map[string]any) bool {
	_, ok := properties[property]
	return ok
}
func contractTrue(properties map[string]any, property string) bool {
	return properties[property] == true
}
func contractString(properties map[string]any, property, fallback string) string {
	if v, ok := properties[property].(string); ok {
		return v
	}
	return fallback
}
func contractNonempty(properties map[string]any, property string) bool {
	return contractString(properties, property, "") != ""
}
func contractNumber(properties map[string]any, property string, fallback float64) float64 {
	value := contractValue(properties[property])
	if value.kind == scalarInt || value.kind == scalarFloat {
		return value.value.(float64)
	}
	return fallback
}
func contractTreeItem(properties map[string]any) bool {
	return contractString(properties, "role", "") == "treeitem"
}
func contractTreeRow(kind string) bool { return contractTreeRows[kind] }
func contractTrim(value string) string { return strings.Trim(value, " \t\n\r\f") }
func contractContains(value string, values []string) bool {
	for _, item := range values {
		if item == value {
			return true
		}
	}
	return false
}
func contractTag(kind, tag string) bool { return contractKindTags[kind][tag] }
func contractKnownTag(tag string) bool {
	for _, tags := range contractKindTags {
		if tags[tag] {
			return true
		}
	}
	return false
}

func contractSurfaceSize(properties map[string]any) bool {
	for _, axis := range []string{"width", "height"} {
		minimum := contractNumber(properties, "min-"+axis, 0)
		fixed := minimum
		if value := contractLookup(axis, properties); value.exists && value.value.kind == scalarInt {
			fixed = value.value.value.(float64)
		}
		if fixed < minimum {
			return false
		}
		if maximum := contractLookup("max-"+axis, properties); maximum.exists {
			if maximum.value.kind != scalarInt || minimum > maximum.value.value.(float64) || fixed > maximum.value.value.(float64) {
				return false
			}
		}
	}
	return true
}
func contractViewportSize(properties map[string]any) bool {
	for _, axis := range []string{"width", "height"} {
		minimum, maximum := contractLookup("min-"+axis+"-viewport", properties), contractLookup("max-"+axis+"-viewport", properties)
		if minimum.exists && maximum.exists && (minimum.value.kind != scalarFloat || maximum.value.kind != scalarFloat || minimum.value.value.(float64) > maximum.value.value.(float64)) {
			return false
		}
	}
	return true
}

func contractIcon(value string) bool {
	if contractIcons[value] {
		return true
	}
	slug, ok := strings.CutPrefix(value, "app:")
	if !ok || slug == "" {
		return false
	}
	for _, part := range strings.Split(slug, "-") {
		if part == "" {
			return false
		}
		for _, c := range part {
			if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9') {
				return false
			}
		}
	}
	return true
}

// OCaml float_of_string removes underscores, accepts leading ASCII space,
// and accepts hexadecimal mantissas without an explicit binary exponent.
func contractFloatString(value string) (float64, error) {
	value = strings.ReplaceAll(value, "_", "")
	value = strings.TrimLeft(value, " \t\r\n\f\v")
	mantissa := strings.TrimPrefix(strings.TrimPrefix(value, "+"), "-")
	if (strings.HasPrefix(mantissa, "0x") || strings.HasPrefix(mantissa, "0X")) && !strings.ContainsAny(mantissa, "pP") {
		value += "p0"
	}
	return strconv.ParseFloat(value, 64)
}

func contractAnchorRect(value string) bool {
	fields := strings.Split(value, " ")
	if len(fields) != 4 {
		return false
	}
	for i, field := range fields {
		n, err := contractFloatString(field)
		if err != nil || math.IsNaN(n) || math.IsInf(n, 0) || i >= 2 && n < 0 {
			return false
		}
	}
	return true
}
func contractDataAttrs(payload string) bool {
	if payload == "" {
		return true
	}
	for _, record := range strings.Split(payload, "\x1e") {
		fields := strings.Split(record, "\x1f")
		if len(fields) != 2 {
			return false
		}
		name := fields[0]
		if name != "role" && name != "tabindex" && name != "draggable" && name != "style" && !(strings.HasPrefix(name, "data-") && len(name) > 5) && !(strings.HasPrefix(name, "aria-") && len(name) > 5) {
			return false
		}
	}
	return true
}
func contractTextDecoration(value string) bool {
	var tokens []string
	for _, token := range strings.Split(value, " ") {
		if contractTrim(token) != "" {
			tokens = append(tokens, token)
		}
	}
	if len(tokens) == 1 && tokens[0] == "none" {
		return true
	}
	if len(tokens) == 0 {
		return false
	}
	for _, token := range tokens {
		if token != "underline" && token != "line-through" && token != "overline" {
			return false
		}
	}
	return true
}
func contractCSSIdentifier(value string) bool {
	alpha := func(c byte) bool { return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c == '_' }
	if value == "" || !(alpha(value[0]) || value[0] == '-' && len(value) > 1 && (alpha(value[1]) || value[1] == '-')) {
		return false
	}
	for i := 1; i < len(value); i++ {
		c := value[i]
		if !alpha(c) && !(c >= '0' && c <= '9') && c != '-' {
			return false
		}
	}
	return true
}
func contractCSSTime(value string) bool {
	number, ok := strings.CutSuffix(value, "ms")
	if !ok {
		number, ok = strings.CutSuffix(value, "s")
	}
	if !ok || number == "" {
		return false
	}
	n, err := contractFloatString(number)
	return err == nil && n >= 0 && !math.IsInf(n, 0) && !math.IsNaN(n)
}
func contractTransition(value string) bool {
	if contractTrim(value) == "" {
		return false
	}
	start, depth := 0, 0
	var segments []string
	for i := 0; i < len(value); i++ {
		switch value[i] {
		case '(':
			depth++
		case ')':
			if depth > 0 {
				depth--
			}
		case ',':
			if depth == 0 {
				segments = append(segments, value[start:i])
				start = i + 1
			}
		}
	}
	segments = append(segments, value[start:])
	for _, segment := range segments {
		var tokens []string
		begin, nested := -1, 0
		for i := 0; i <= len(segment); i++ {
			whitespace := i == len(segment) || strings.ContainsRune(" \t\n\r", rune(segment[i]))
			if whitespace && nested == 0 {
				if begin >= 0 {
					tokens = append(tokens, segment[begin:i])
					begin = -1
				}
				continue
			}
			if i == len(segment) {
				break
			}
			if begin < 0 {
				begin = i
			}
			if segment[i] == '(' {
				nested++
			} else if segment[i] == ')' && nested > 0 {
				nested--
			}
		}
		if begin >= 0 {
			tokens = append(tokens, segment[begin:])
		}
		if len(tokens) < 2 || !contractCSSIdentifier(tokens[0]) {
			return false
		}
		times := 0
		for _, token := range tokens[1:] {
			if contractCSSTime(token) {
				times++
				continue
			}
			if open := strings.IndexByte(token, '('); open >= 0 {
				if open == 0 || len(token) <= open+2 || token[len(token)-1] != ')' || !contractCSSIdentifier(token[:open]) {
					return false
				}
			} else if !contractCSSIdentifier(token) {
				return false
			}
		}
		if times < 1 || times > 2 {
			return false
		}
	}
	return true
}
