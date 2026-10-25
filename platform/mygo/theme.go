package luimygo

import (
	"encoding/json"
	"fmt"
	"maps"
	"strings"

	"github.com/egoist/mygo/ui"
)

func tokenValue(v any, dark bool) string {
	if value, ok := v.(string); ok {
		return value
	}
	if adaptive, ok := v.(map[string]any); ok {
		key := "light"
		if dark {
			key = "dark"
		}
		value, _ := adaptive[key].(string)
		return value
	}
	return ""
}
func decodeTokens(s string) (map[string]any, error) {
	var tokens map[string]any
	if err := json.Unmarshal([]byte(s), &tokens); err != nil || tokens == nil {
		return nil, fmt.Errorf("lui: theme requires a JSON object")
	}
	for key, v := range tokens {
		switch value := v.(type) {
		case string:
			if value == "" || (strings.HasPrefix(value, "#") && !validHex(value)) {
				return nil, fmt.Errorf("lui: empty theme token %s", key)
			}
		case map[string]any:
			if tokenValue(value, false) == "" || tokenValue(value, true) == "" || !tokenHexValid(tokenValue(value, false)) || !tokenHexValid(tokenValue(value, true)) {
				return nil, fmt.Errorf("lui: adaptive token %s requires light and dark", key)
			}
		default:
			return nil, fmt.Errorf("lui: invalid theme token %s", key)
		}
	}
	return tokens, nil
}

// SetThemeDefaults replaces this window's host-owned tokens. It does not emit
// patches or modify application nodes. Nested theme props override these values
// only for their subtree. Call between frames on the UI goroutine; nil clears.
func (b *Backend) SetThemeDefaults(tokens map[string]string) error {
	if b.closed || b.building {
		return fmt.Errorf("lui: cannot install theme defaults while closed or building")
	}
	next := make(map[string]any, len(tokens))
	for name, value := range tokens {
		if strings.TrimSpace(name) == "" || (value == "" && !strings.HasPrefix(name, "--")) || !tokenHexValid(value) {
			return fmt.Errorf("lui: invalid host theme token %q", name)
		}
		next[name] = value
	}
	b.tokens = next
	return nil
}

func (b *Backend) applyThemeSlots(c *ui.Context, next *ui.Theme) {
	slots := map[string]*ui.Color{
		"primary": &next.Accent, "primary-foreground": &next.AccentText,
		"background": &next.Background, "foreground": &next.Text,
		"muted": &next.Surface, "muted-foreground": &next.TextMuted,
		"border": &next.Border, "destructive": &next.Danger,
		"success-foreground": &next.Success, "warning-foreground": &next.Warning,
		"ring": &next.Focus,
	}
	c.SetTheme(next)
	resolved := map[string]ui.Color{}
	for name := range slots {
		if tokenValue(b.tokens[name], next.Dark) != "" {
			if color, err := b.ResolveColor(c, name); err == nil {
				resolved[name] = color
			}
		}
	}
	for name, color := range resolved {
		*slots[name] = color
	}
}

func (b *Backend) scopeTheme(c *ui.Context, n Node) func() {
	oldTheme, oldTokens := c.Theme(), b.tokens
	next := *oldTheme
	changed := false
	switch n.String("theme-mode") {
	case "system":
		next = *b.systemTheme
		changed = true
	case "dark":
		next = *ui.DarkTheme()
		changed = true
	case "light":
		next = *ui.LightTheme()
		changed = true
	}
	if encoded := n.String("theme"); encoded != "" {
		added, _ := decodeTokens(encoded)
		b.tokens = maps.Clone(b.tokens)
		if b.tokens == nil {
			b.tokens = map[string]any{}
		}
		maps.Copy(b.tokens, added)
		changed = true
	}
	if !changed {
		return func() {}
	}
	b.applyThemeSlots(c, &next)
	return func() { b.tokens = oldTokens; c.SetTheme(oldTheme) }
}

func validHex(s string) bool {
	if len(s) != 4 && len(s) != 5 && len(s) != 7 && len(s) != 9 {
		return false
	}
	if s[0] != '#' {
		return false
	}
	for _, c := range s[1:] {
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')) {
			return false
		}
	}
	return true
}
func tokenHexValid(s string) bool { return !strings.HasPrefix(s, "#") || validHex(s) }
