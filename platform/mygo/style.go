package luimygo

import (
	"fmt"
	"github.com/egoist/mygo/ui"
	"math"
	"strconv"
	"strings"
)

func (b *Backend) style(c *ui.Context, n Node, e ui.Element) {
	pointerPolicy(n, e)
	if n.Kind == "edge-inset" {
		n = n.clone()
		for name := range n.Props {
			if pinnedSurfaceProperty(name) {
				delete(n.Props, name)
			}
		}
	}
	if n.Kind == "divider" {
		switch n.String("orientation") {
		case "vertical":
			e.Width(1).FillHeight()
		case "horizontal":
			e.Height(1).FillWidth()
		}
	}
	if n.Kind == "spinner" {
		extent := float32(20)
		switch n.String("size") {
		case "sm":
			extent = 16
		case "lg":
			extent = 24
		}
		e.Size(extent, extent)
	}
	e.Disabled(n.Props["enabled"] == false).Inert(n.Bool("inert"))
	if label := n.String("accessibility-label"); label != "" {
		e.Label(label)
	}
	numeric := map[string]func(float32) ui.Element{
		"grow": e.Grow, "width": e.Width, "height": e.Height,
		"min-width": e.MinWidth, "max-width": e.MaxWidth, "min-height": e.MinHeight, "max-height": e.MaxHeight,
		"opacity": e.Opacity, "border-width": func(v float32) ui.Element { return e.BorderWidth(v) },
		"corner-radius": func(v float32) ui.Element { return e.Radius(v) },
	}
	if n.Kind != "split" {
		numeric["gap"] = e.Gap
	}
	for k, set := range numeric {
		if v, ok := number(n.Props[k]); ok {
			set(float32(v))
		}
	}
	for _, name := range []string{"padding", "margin"} {
		if _, ok := n.Props[name]; ok || hasSpacing(n, name) {
			t, r, d, l := spacing(n, name, 0)
			if name == "padding" {
				e.Padding(t, r, d, l)
			} else {
				e.Margin(t, r, d, l)
			}
		}
	}
	if v := n.String("main"); v != "" {
		e.Justify(alignment(v))
	}
	if v := n.String("cross"); v != "" {
		e.AlignItems(alignment(v))
	}
	if v := n.String("text-alignment"); v != "" {
		e.TextAlign(alignment(v))
	}
	if n.String("flex-wrap") == "wrap" {
		e.Wrap()
	}
	switch n.String("overflow") {
	case "hidden":
		e.Clip()
	case "auto":
		e.ScrollAxes(true, true)
	}
	switch n.String("user-select") {
	case "text":
		e.Selectable()
	case "none":
		e.Unselectable()
	}
	if v := n.String("font-style"); v != "" {
		e.FontItalic(v == "italic" || v == "oblique")
	}
	if v := n.String("text-decoration"); v != "" {
		e.TextDecorations(strings.Contains(v, "underline"), strings.Contains(v, "line-through"))
	}
	if v, ok := b.styleValue(c, n.String("font-family")); ok && v != "" {
		e.Font(v)
	}
	if n.Kind == "table-cell" {
		switch n.String("size") {
		case "sm":
			e.FontSize(12)
		case "lg":
			e.FontSize(18)
		case "icon":
			e.FontSize(18)
		case "heading":
			e.FontSize(24).Bold()
		case "display":
			e.FontSize(32).Bold()
		}
	}
	if v := n.Number("font-weight", 0); v > 0 {
		e.FontWeight(int(v))
	}

	if value, ok := b.styleValue(c, n.String("font-size")); ok {
		if v := length(value); v > 0 {
			e.FontSize(v)
		}
	}
	if line, ok := b.styleValue(c, n.String("line-height")); ok && line != "" {
		if v := length(line); v > 0 {
			if strings.HasSuffix(line, "px") || strings.HasSuffix(line, "em") {
				e.FixedLineHeight(v)
			} else {
				e.LineHeight(v)
			}
		}
	}
	if v, ok := number(n.Props["letter-spacing"]); ok {
		e.LetterSpacing(float32(v))
	}
	if v, ok := number(n.Props["grid-column-span"]); ok {
		e.ColumnSpan(int(v))
	}
	if mode := n.String("white-space"); mode != "" {
		e.WhiteSpace(mode)
	}
	if n.String("text-overflow") == "ellipsis" {
		e.Ellipsis("…")
	}
	if v, ok := number(n.Props["line-clamp"]); ok {
		e.MaxLines(int(v))
	}
	cursor := n.String("cursor")
	for parent := n.Parent; cursor == "" && parent != 0; {
		ancestor, ok := b.nodes[parent]
		if !ok {
			break
		}
		cursor = ancestor.String("cursor")
		parent = ancestor.Parent
	}
	switch cursor {
	case "pointer":
		e.Cursor(ui.CursorPointer)
	case "text":
		e.Cursor(ui.CursorText)
	case "default":
		e.Cursor(ui.CursorDefault)
	}
	w, h := c.Size()
	for name, set := range map[string]func(float32) ui.Element{"width-viewport": e.Width, "min-width-viewport": e.MinWidth, "max-width-viewport": e.MaxWidth, "height-viewport": e.Height, "min-height-viewport": e.MinHeight, "max-height-viewport": e.MaxHeight} {
		if v, ok := number(n.Props[name]); ok {
			size := w
			if strings.Contains(name, "height") {
				size = h
			}
			set(float32(v) * size)
		}
	}

	if v := n.String("background"); v != "" && n.Kind != "edge-inset" {
		e.Background(b.color(c, v))
	}
	if v := n.String("foreground"); v != "" {
		e.TextColor(b.color(c, v))
	}
	if v := n.String("border-color"); v != "" && n.Kind != "edge-inset" {
		e.BorderColor(b.color(c, v))
	}
	if n.Kind != "edge-inset" {
		applyState := func(prefix string) {
			if v := n.String(prefix + "-background"); v != "" {
				e.Background(b.color(c, v))
			}
			if v := n.String(prefix + "-foreground"); v != "" {
				e.TextColor(b.color(c, v))
			}
			if v := n.String(prefix + "-border"); v != "" {
				e.BorderColor(b.color(c, v))
			}
			if v, ok := number(n.Props[prefix+"-opacity"]); ok {
				e.Opacity(float32(v))
			}
		}
		if n.Bool("selected") {
			applyState("selected")
		}
		if e.FocusWithin() {
			applyState("focus-within")
		}
		if e.Hovered() {
			applyState("hover")
		}
		if hasPressedStyle(n) && e.Pressed() {
			applyState("pressed")
		}
		if n.Props["enabled"] == false {
			if value, ok := number(n.Props["disabled-opacity"]); ok {
				e.DisabledOpacity(float32(value))
			}
		}
	}

	switch n.String("position") {
	case "absolute", "relative":
		if n.String("position") == "absolute" {
			e.Absolute()
		}
		base, hasBase := number(n.Props["inset"])
		for _, edge := range []struct {
			name string
			set  func(float32) ui.Element
		}{{"top", e.Top}, {"right", e.Right}, {"bottom", e.Bottom}, {"left", e.Left}} {
			if value, ok := number(n.Props["inset-"+edge.name]); ok {
				edge.set(float32(value))
			} else if hasBase {
				edge.set(float32(base))
			}
		}
	}
	if value, ok := number(n.Props["z-index"]); ok {
		e.ZIndex(int(value))
	}
	inset := -float32(n.Number("container-relative-frame-inset", 0))
	switch n.String("container-relative-frame") {
	case "horizontal":
		e.FillWidth()
	case "vertical":
		e.FillHeight()
	case "both":
		e.Fill()
	case "min-horizontal":
		e.MinWidthPercentOffset(100, inset)
	case "min-vertical":
		e.MinHeightPercentOffset(100, inset)
	case "min-both":
		e.MinWidthPercentOffset(100, inset).MinHeightPercentOffset(100, inset)
	}
	switch n.Kind {
	case "heading":
		e.Role(ui.RoleHeading).Level(int(n.Number("heading-level", 2)))
	case "table":
		e.Role(ui.RoleTable)
	case "table-row":
		e.Role(ui.RoleRow)
	case "table-cell":
		e.Role(ui.RoleCell)
	}
	switch n.String("role") {
	case "treeitem":
		e.Role(ui.RoleTreeItem).Level(int(n.Number("tree-level", 1)))
	case "navigation":
		e.Role(ui.RoleGroup).Label(n.String("text"))
	case "navigation-heading":
		e.Role(ui.RoleHeading).Label(n.String("text")).Level(2)
	}
	shadow := n.String("shadow")
	chooseShadow := func(name string) {
		if value := n.String(name); value != "" {
			shadow = value
		}
	}
	if n.Bool("selected") {
		chooseShadow("selected-shadow")
	}
	if e.FocusVisible() {
		chooseShadow("focus-shadow")
	}
	if e.Hovered() {
		chooseShadow("hover-shadow")
		if n.Bool("selected") {
			chooseShadow("selected-hover-shadow")
		}
	}
	if hasPressedStyle(n) && e.Pressed() {
		chooseShadow("pressed-shadow")
	}
	b.applyShadow(c, e, shadow)

}

func spacing(n Node, name string, fallback float64) (top, right, bottom, left float32) {
	base := n.Number(name, fallback)
	x := n.Number(name+"-horizontal", base)
	y := n.Number(name+"-vertical", base)
	return float32(n.Number(name+"-top", y)), float32(n.Number(name+"-right", x)),
		float32(n.Number(name+"-bottom", y)), float32(n.Number(name+"-left", x))
}
func hasSpacing(n Node, prefix string) bool {
	for _, s := range []string{"-horizontal", "-vertical", "-top", "-right", "-bottom", "-left"} {
		if _, ok := n.Props[prefix+s]; ok {
			return true
		}
	}
	return false
}
func alignment(s string) ui.Align {
	switch s {
	case "center":
		return ui.Center
	case "end":
		return ui.End
	case "stretch":
		return ui.Stretch
	case "space-between":
		return ui.SpaceBetween
	case "space-around":
		return ui.SpaceAround
	case "space-evenly":
		return ui.SpaceEvenly
	default:
		return ui.Start
	}
}
func length(s string) float32 {
	s = strings.TrimSpace(s)
	mult := float64(1)
	if strings.HasSuffix(s, "rem") {
		mult = 16
		s = strings.TrimSuffix(s, "rem")
	} else if strings.HasSuffix(s, "em") {
		mult = 16
		s = strings.TrimSuffix(s, "em")
	}
	s = strings.TrimSuffix(s, "px")
	v, err := strconv.ParseFloat(s, 32)
	if err != nil || math.IsNaN(v) || math.IsInf(v, 0) || math.Abs(v*mult) > math.MaxFloat32 {
		return 0
	}
	return float32(v * mult)
}

func (b *Backend) styleValue(c *ui.Context, value string) (string, bool) {
	lookup := themeVariableLookup(nil, func(name string) (string, bool) {
		value, ok := b.tokens[name]
		return tokenValue(value, c.Theme().Dark), ok
	})
	resolved, ok := substituteThemeValue(value, lookup)
	return strings.TrimSpace(resolved), ok
}

func (b *Backend) color(c *ui.Context, s string) ui.Color {
	color, err := b.ResolveColor(c, s)
	if err != nil {
		return c.Theme().Text
	}
	return color
}

// ResolveColor uses the same current scoped tokens as standard typed paint
// properties. Call from a renderer while building; do not retain Context.
// Unlike the internal legacy paint fallback, an unresolved value is an error.
func (b *Backend) ResolveColor(c *ui.Context, s string) (ui.Color, error) {
	original := s
	seen := map[string]bool{}
	for {
		s = strings.TrimSpace(s)
		if seen[s] {
			return ui.Color{}, fmt.Errorf("lui: cyclic color token %q", original)
		}
		seen[s] = true
		value, valid := b.styleValue(c, s)
		if !valid {
			return ui.Color{}, fmt.Errorf("lui: unresolved color variables in %q", original)
		}
		s = strings.TrimSpace(value)
		if resolved := tokenValue(b.tokens[s], c.Theme().Dark); resolved != "" {
			s = resolved
			continue
		}
		break
	}
	if parsed, ok := styleColor(s); ok {
		return parsed, nil
	}
	t := c.Theme()
	var color ui.Color
	switch s {
	case "primary", "accent":
		color = t.Accent
	case "primary-foreground":
		color = t.AccentText
	case "background":
		color = t.Background
	case "foreground", "card-foreground", "secondary-foreground", "accent-foreground":
		color = t.Text
	case "card":
		color = t.Background
	case "muted", "secondary":
		color = t.Surface
	case "muted-foreground":
		color = t.TextMuted
	case "border":
		color = t.Border
	case "destructive", "danger", "error-foreground":
		color = t.Danger
	case "destructive-foreground":
		color = t.AccentText
	case "success":
		color = t.Success.Alpha(.15)
	case "success-foreground":
		color = t.Success
	case "warning":
		color = t.Warning.Alpha(.15)
	case "warning-foreground":
		color = t.Warning
	case "error":
		color = t.Danger.Alpha(.15)
	case "input":
		color = t.Border
	case "ring":
		color = t.Focus
	case "glass-fallback":
		color = ui.Transparent
	case "transparent":
		color = ui.Transparent
	default:
		return ui.Color{}, fmt.Errorf("lui: unknown color %q", original)
	}
	return color, nil
}

func (b *Backend) applyShadow(c *ui.Context, e ui.Element, value string) {
	if value == "" || value == "none" {
		return
	}
	switch value {
	case "sm":
		value = "0px 1px 2px 0px #00000020"
	case "md":
		value = "0px 4px 6px -1px #00000030"
	case "lg":
		value = "0px 10px 15px -3px #00000030"
	}
	parts := []string{}
	start, depth := 0, 0
	for i, char := range value {
		if char == '(' {
			depth++
		} else if char == ')' {
			depth--
		} else if char == ',' && depth == 0 {
			parts = append(parts, value[start:i])
			start = i + 1
		}
	}
	parts = append(parts, value[start:])
	for _, part := range parts {
		tokens := styleFields(part)
		inset := false
		values := []float32{}
		colorName := "foreground"
		for _, token := range tokens {
			if token == "inset" {
				inset = true
				continue
			}
			if parsed, err := strconv.ParseFloat(strings.TrimSuffix(strings.TrimSuffix(token, "px"), "rem"), 32); err == nil {
				if strings.HasSuffix(token, "rem") {
					parsed *= 16
				}
				values = append(values, float32(parsed))
			} else {
				colorName = token
			}
		}
		if len(values) < 2 || len(values) > 4 {
			continue
		}
		for len(values) < 4 {
			values = append(values, 0)
		}
		tint := b.color(c, colorName)
		if inset {
			e.InsetShadow(values[0], values[1], max(0, values[2]), values[3], tint)
		} else {
			e.Shadow(values[0], values[1], max(0, values[2]), values[3], tint)
		}
	}
}

func pinnedSurfaceProperty(name string) bool {
	return strings.HasPrefix(name, "padding") || name == "background" || name == "foreground" || name == "border-color" || name == "border-width" || name == "corner-radius" || name == "opacity" || name == "shadow" || strings.HasPrefix(name, "hover-") || strings.HasPrefix(name, "pressed-") || strings.HasPrefix(name, "focus-") || strings.HasPrefix(name, "selected-") || name == "disabled-opacity"
}

func hasPressedStyle(n Node) bool {
	for name := range n.Props {
		if strings.HasPrefix(name, "pressed-") {
			return true
		}
	}
	return false
}
