package luimygo

import (
	"maps"
	"strings"
)

type themeVariable struct {
	start, end int
	name       string
	fallback   *string
}

// nextThemeVariable skips quoted tokens and comments: neither contains a var()
// function in the CSS token stream. Escaped characters do not end a string.
func nextThemeVariable(value string, cursor int) (themeVariable, bool, bool) {
	quote := byte(0)
	for i := cursor; i < len(value); i++ {
		ch := value[i]
		if ch == '\\' {
			i++
			continue
		}
		if quote != 0 {
			if ch == quote {
				quote = 0
			}
			continue
		}
		if ch == '\'' || ch == '"' {
			quote = ch
			continue
		}
		if strings.HasPrefix(value[i:], "/*") {
			end := strings.Index(value[i+2:], "*/")
			if end < 0 {
				return themeVariable{}, false, false
			}
			i += end + 3
			continue
		}
		if i+4 > len(value) || !strings.EqualFold(value[i:i+4], "var(") {
			continue
		}
		if i > 0 && themeIdentByte(value[i-1]) {
			continue
		}
		depth, comma, innerQuote := 1, -1, byte(0)
		for j := i + 4; j < len(value); j++ {
			ch := value[j]
			if ch == '\\' {
				j++
				continue
			}
			if innerQuote != 0 {
				if ch == innerQuote {
					innerQuote = 0
				}
				continue
			}
			if ch == '\'' || ch == '"' {
				innerQuote = ch
				continue
			}
			if strings.HasPrefix(value[j:], "/*") {
				end := strings.Index(value[j+2:], "*/")
				if end < 0 {
					return themeVariable{}, false, false
				}
				j += end + 3
				continue
			}
			switch ch {
			case '(':
				depth++
			case ')':
				depth--
			case ',':
				if depth == 1 && comma < 0 {
					comma = j
				}
			}
			if depth != 0 {
				continue
			}
			nameEnd := j
			var fallback *string
			if comma >= 0 {
				nameEnd = comma
				text := strings.TrimSpace(value[comma+1 : j])
				fallback = &text
			}
			name := strings.TrimSpace(value[i+4 : nameEnd])
			if !strings.HasPrefix(name, "--") || len(name) <= 2 || strings.ContainsAny(name, " \t\r\n(),") {
				return themeVariable{}, false, false
			}
			return themeVariable{start: i, end: j + 1, name: name, fallback: fallback}, true, true
		}
		return themeVariable{}, false, false
	}
	return themeVariable{}, false, quote == 0
}

func themeIdentByte(ch byte) bool {
	return ch >= 'a' && ch <= 'z' || ch >= 'A' && ch <= 'Z' || ch >= '0' && ch <= '9' || ch == '-' || ch == '_' || ch >= 128
}

func substituteThemeValue(value string, lookup func(string) (string, bool)) (string, bool) {
	var result strings.Builder
	for cursor := 0; ; {
		variable, found, valid := nextThemeVariable(value, cursor)
		if !valid {
			return "", false
		}
		if !found {
			result.WriteString(value[cursor:])
			return result.String(), true
		}
		replacement, ok := lookup(variable.name)
		if !ok && variable.fallback != nil {
			replacement, ok = substituteThemeValue(*variable.fallback, lookup)
		}
		if !ok {
			return "", false
		}
		result.WriteString(value[cursor:variable.start])
		result.WriteString(replacement)
		cursor = variable.end
	}
}

// ResolveThemeValue substitutes variables from a computed, inherited variable
// map. Missing/invalid references use their fallback, including an empty one.
func ResolveThemeValue(value string, variables map[string]string) (string, bool) {
	return substituteThemeValue(value, func(name string) (string, bool) { v, ok := variables[name]; return v, ok })
}

type themeVariableResult struct {
	value string
	valid bool
}

func themeVariableLookup(parent map[string]string, raw func(string) (string, bool)) func(string) (string, bool) {
	computed := map[string]themeVariableResult{}
	visiting := map[string]int{}
	cyclic := map[string]bool{}
	var stack []string
	var lookup func(string) (string, bool)
	lookup = func(name string) (string, bool) {
		value, exists := raw(name)
		if !exists {
			v, ok := parent[name]
			return v, ok
		}
		if result, ok := computed[name]; ok {
			return result.value, result.valid
		}
		if start, ok := visiting[name]; ok {
			for _, member := range stack[start:] {
				cyclic[member] = true
			}
			return "", false
		}
		visiting[name] = len(stack)
		stack = append(stack, name)
		// References in unused fallbacks participate in the dependency graph.
		valid := true
		for cursor := 0; ; {
			variable, found, good := nextThemeVariable(value, cursor)
			if !good {
				valid = false
				break
			}
			if !found {
				break
			}
			lookup(variable.name)
			cursor = variable.start + 4
		}
		var resolved string
		if valid && !cyclic[name] {
			resolved, valid = substituteThemeValue(value, lookup)
			if valid {
				switch strings.ToLower(strings.TrimSpace(resolved)) {
				case "initial":
					valid = false
				case "inherit", "unset":
					resolved, valid = parent[name]
				}
			}
		} else {
			valid = false
		}
		stack = stack[:len(stack)-1]
		delete(visiting, name)
		if !valid {
			resolved = ""
		}
		computed[name] = themeVariableResult{resolved, valid}
		return resolved, valid
	}
	return lookup
}

// ComputeThemeVariables computes declarations before inheritance. Invalid or
// cyclic declarations remove an inherited value; an absent declaration keeps it.
// Parent values must already be computed, not raw declarations from an ancestor.
func ComputeThemeVariables(parent, declarations map[string]string) map[string]string {
	lookup := themeVariableLookup(parent, func(name string) (string, bool) { value, ok := declarations[name]; return value, ok })
	result := maps.Clone(parent)
	if result == nil {
		result = map[string]string{}
	}
	for name := range declarations {
		if value, valid := lookup(name); valid {
			result[name] = value
		} else {
			delete(result, name)
		}
	}
	return result
}
