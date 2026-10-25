package luimygo

import (
	"math"
	"slices"
	"strconv"
	"strings"

	"github.com/egoist/mygo/ui"
)

// Kinds requiring application-owned resources or specialized layout are
// accepted only with a registered renderer, rather than silently discarded.
var nativeKinds = strings.Fields(`root row column grid panel card alert bubble box
 text heading paragraph label button toggle-button toggle radio-group radio
 slider number-stepper text-field secure-field input search-field textarea
 checkbox switch progress divider scroll list tabs bottom-tabs bottom-tab
 button-group toggle-group spacer spinner select combobox menu-item list-item
 avatar input-group input-group-actions
 breadcrumb pagination accordion table-row table-cell tree dialog sheet
 toolbar status-bar list-section list-section-header list-section-footer link kbd`)

func SupportedKinds() []string       { kinds := slices.Clone(nativeKinds); slices.Sort(kinds); return kinds }
func supportedKind(kind string) bool { return slices.Contains(nativeKinds, kind) }

func (b *Backend) state(n Node) *controlState {
	s := b.states[n.ID]
	if s == nil {
		b.nextIdentity++
		s = &controlState{text: n.String("text"), checked: n.Bool("checked") || n.Bool("selected") || n.Bool("expanded"), value: n.Number("value", 0), identity: b.nextIdentity}
		b.states[n.ID] = s
	}
	return s
}
func (b *Backend) emit(e Event) {
	if b.building {
		b.queued = append(b.queued, e)
		return
	}
	n, ok := b.nodes[e.Node]
	if !ok || n.Props["enabled"] == false {
		return
	}
	if b.config.Dispatch != nil {
		if err := b.config.Dispatch(e); err != nil && b.err == nil {
			b.err = err
		}
	}
}
func (b *Backend) View(c *ui.Context) {
	var appearances []Event
	b.systemTheme = c.Theme()
	b.building = true
	defer func() { b.building = false }()
	for _, id := range b.Roots() {
		b.render(c, id, &appearances)
	}
	b.building = false
	appearances = append(appearances, b.queued...)
	b.queued = nil
	// No runtime call occurs halfway through constructing the retained frame.
	for _, e := range appearances {
		b.emit(e)
		c.Invalidate()
	}
}
func (b *Backend) render(c *ui.Context, id int64, appearances *[]Event) {
	n, ok := b.nodes[id]
	if !ok || n.String("display") == "none" {
		return
	}
	restoreTheme := b.scopeTheme(c, n)
	defer restoreTheme()
	s := b.state(n)
	c.Key(s.identity)
	children := func() {
		for _, child := range n.Children {
			b.render(c, child, appearances)
		}
	}
	emit := func(e Event) {
		if e.Node == 0 {
			e.Node = id
		}
		b.emit(e)
		c.Invalidate()
	}
	if n.Bool("appear-enabled") && !s.appeared {
		s.appeared = true
		*appearances = append(*appearances, Event{Kind: "appear", Node: id})
	}
	if n.Kind == "extension" {
		b.config.Extensions[n.Identifier].Render(c, n.clone(), children, emit)
		return
	}
	if custom := b.config.Renderers[n.Kind]; custom != nil {
		custom(c, n.clone(), children, emit)
		return
	}
	var e ui.Element
	switch n.Kind {
	case "root":
		e = ui.Column(c).Fill()
	case "row", "button-group", "toggle-group", "tabs", "bottom-tabs", "breadcrumb", "pagination", "table-row", "input-group", "input-group-actions", "toolbar":
		e = ui.Row(c).AlignItems(ui.Center)
		if n.String("orientation") == "vertical" {
			e.Column()
		}
	case "grid":
		e = ui.Grid(c).Columns(max(1, int(n.Number("columns", 1))))
	case "text", "paragraph", "label", "kbd", "table-cell", "status-bar", "step", "list-section-header", "list-section-footer":
		e = ui.Text(c, n.String("text"))
	case "heading":
		e = ui.Text(c, n.String("text")).Bold().FontSize(float32(30 - n.Number("heading-level", 2)*2))
	case "button", "bottom-tab", "menu-item", "list-item", "select":
		label := n.String("text")
		if label == "" {
			label = n.String("title")
		}
		if n.String("variant") == "primary" {
			e = ui.PrimaryButton(c, label)
		} else {
			e = ui.Button(c, label)
		}
		e.Selected(n.Bool("selected"))
	case "toggle-button":
		e = ui.Toggle(c, &s.checked, n.String("text"))
		e.OnChange(func() {
			if n.Bool("toggle-enabled") {
				emit(Event{Kind: "toggle-changed", Checked: s.checked})
			}
		})

	case "checkbox", "toggle":
		e = ui.Checkbox(c, &s.checked, n.String("text"))
		e.OnChange(func() {
			if n.Bool("toggle-enabled") {
				emit(Event{Kind: "toggle-changed", Checked: s.checked})
			}
		})
	case "switch":
		e = ui.Switch(c, &s.checked).Label(n.String("text"))
		e.OnChange(func() {
			if n.Bool("toggle-enabled") {
				emit(Event{Kind: "toggle-changed", Checked: s.checked})
			}
		})
	case "radio":
		e = ui.Radio(c, &s.checked, true, n.String("text"))
		e.OnChange(func() {
			if n.Bool("change-enabled") {
				emit(Event{Kind: "change"})
			}
			if n.Bool("toggle-enabled") {
				emit(Event{Kind: "toggle-changed", Checked: s.checked})
			}
		})
	case "text-field", "secure-field", "input", "search-field", "textarea", "combobox":
		if n.Kind == "textarea" {
			e = ui.TextArea(c, &s.text)
		} else {
			e = ui.TextInput(c, &s.text)
		}
		e.Placeholder(n.String("placeholder")).Label(n.String("placeholder"))
		if n.Kind == "secure-field" {
			e.Password()
		}
		e.OnChange(func() { emit(Event{Kind: "text-changed", Text: s.text}) })
		e.OnSubmit(func() {
			if n.Bool("submit-enabled") {
				emit(Event{Kind: "submit"})
			}
		})
	case "slider":
		e = ui.Slider(c, &s.value, 0, 1)
		e.OnChange(func() { emit(Event{Kind: "value-changed", Value: s.value}) })
	case "number-stepper":
		e = ui.NumberInput(c, &s.value, n.Number("min", 0), n.Number("max", 100), n.Number("step", 1))
		e.OnChange(func() { emit(Event{Kind: "value-changed", Value: s.value}) })
	case "progress":
		e = ui.Progress(c, n.Number("value", 0))
	case "spinner":
		e = ui.Spinner(c)
	case "spacer":
		e = ui.Spacer(c)
	case "divider":
		e = ui.Divider(c)
	case "scroll", "list":
		if n.String("orientation") == "horizontal" {
			e = ui.ScrollHorizontal(c)
		} else {
			e = ui.Scroll(c)
		}
		e.TrackScroll(&s.scroll).FillWidth()
	case "accordion":
		e = ui.Collapsible(c, n.String("text"), &s.checked, children)
		e.OnChange(func() {
			if n.Bool("toggle-enabled") {
				emit(Event{Kind: "toggle-changed", Checked: s.checked})
			}
		})
		children = func() {}
	case "tree":
		e = ui.Tree(c, children)
		children = func() {}
	case "dialog", "sheet":
		open := true
		e = ui.Modal(c, &open, func() {
			if text := n.String("text"); text != "" {
				ui.Text(c, text).Bold()
			}
			if text := n.String("description"); text != "" {
				ui.Text(c, text)
			}
			children()
		})
		if e.Dismissed() {
			emit(Event{Kind: "dismiss"})
		}
		children = func() {}
	case "link":
		e = ui.Link(c, n.String("text"), n.String("url"))
	case "avatar":
		e = ui.Avatar(c, n.String("text"), nil)
	case "radio-group":
		e = ui.RadioGroup(c, children)
		children = func() {}
	case "panel", "card", "alert", "bubble":
		e = ui.Column(c).Padding(12).Radius(8).Background(c.Theme().Surface)
	default:
		e = ui.Column(c)
	}
	if n.Kind == "root" {
		e.Background(c.Theme().Background).TextColor(c.Theme().Text)
	}
	if n.String("theme") != "" || n.String("theme-mode") != "" {
		e.TextColor(c.Theme().Text)
	}
	b.style(c, n, e)
	if n.Bool("autofocus") && !s.focused {
		e.Focus()
		s.focused = true
	}
	if n.Bool("press-enabled") {
		e.OnClick(func() {
			mods := e.ClickModifiers()
			var flags int32
			if mods&ui.Ctrl != 0 {
				flags |= 1
			}
			if mods&ui.Shift != 0 {
				flags |= 2
			}
			if mods&ui.Cmd != 0 {
				flags |= 4
			}
			if flags != 0 {
				emit(Event{Kind: "press-modifiers", Modifiers: flags})
			} else {
				emit(Event{Kind: "press"})
			}
		})
	}
	if text := n.String("tooltip-text"); text != "" {
		e.Tooltip(text)
	}
	if len(n.Children) > 0 {
		e.Children(children)
	}
}
func (b *Backend) style(c *ui.Context, n Node, e ui.Element) {
	e.Disabled(n.Props["enabled"] == false || n.Bool("inert"))
	if label := n.String("accessibility-label"); label != "" {
		e.Label(label)
	}
	numeric := map[string]func(float32) ui.Element{
		"gap": e.Gap, "grow": e.Grow, "width": e.Width, "height": e.Height,
		"min-width": e.MinWidth, "max-width": e.MaxWidth, "min-height": e.MinHeight, "max-height": e.MaxHeight,
		"opacity": e.Opacity, "border-width": func(v float32) ui.Element { return e.BorderWidth(v) },
		"corner-radius": func(v float32) ui.Element { return e.Radius(v) },
	}
	for k, set := range numeric {
		if v, ok := number(n.Props[k]); ok {
			set(float32(v))
		}
	}
	for _, name := range []string{"padding", "margin"} {
		if _, ok := n.Props[name]; ok || hasSpacing(n, name) {
			base := n.Number(name, 0)
			x := n.Number(name+"-horizontal", base)
			y := n.Number(name+"-vertical", base)
			t := float32(n.Number(name+"-top", y))
			r := float32(n.Number(name+"-right", x))
			d := float32(n.Number(name+"-bottom", y))
			l := float32(n.Number(name+"-left", x))
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
	if n.String("overflow") == "hidden" {
		e.Clip()
	}
	if n.String("user-select") == "text" {
		e.Selectable()
	}
	if n.String("font-style") == "italic" {
		e.Italic()
	}
	if n.String("text-decoration") == "underline" {
		e.Underline()
	}
	if v := n.String("font-family"); v != "" {
		e.Font(v)
	}
	if v := n.Number("font-weight", 0); v > 0 {
		e.FontWeight(int(v))
	}
	if v := length(n.String("font-size")); v > 0 {
		e.FontSize(v)
	}
	if v := length(n.String("line-height")); v > 0 {
		e.LineHeight(v)
	}
	if v := n.String("background"); v != "" {
		e.Background(b.color(c, v))
	}
	if v := n.String("foreground"); v != "" {
		e.TextColor(b.color(c, v))
	}
	if v := n.String("border-color"); v != "" {
		e.BorderColor(b.color(c, v))
	}
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
	mult := float64(1)
	if strings.HasSuffix(s, "rem") {
		mult = 16
		s = strings.TrimSuffix(s, "rem")
	}
	s = strings.TrimSuffix(s, "px")
	v, err := strconv.ParseFloat(s, 32)
	if err != nil || math.IsNaN(v) || math.IsInf(v, 0) || math.Abs(v*mult) > math.MaxFloat32 {
		return 0
	}
	return float32(v * mult)
}
func (b *Backend) color(c *ui.Context, s string) ui.Color {
	for i := 0; i < 8; i++ {
		resolved := tokenValue(b.tokens[s], c.Theme().Dark)
		if resolved == "" || resolved == s {
			break
		}
		s = resolved
	}
	if validHex(s) {
		return ui.Hex(s)
	}
	t := c.Theme()
	switch s {
	case "primary", "accent":
		return t.Accent
	case "primary-foreground":
		return t.AccentText
	case "background":
		return t.Background
	case "foreground":
		return t.Text
	case "muted", "secondary":
		return t.Surface
	case "muted-foreground":
		return t.TextMuted
	case "border":
		return t.Border
	case "destructive", "danger":
		return t.Danger
	case "transparent":
		return ui.Transparent
	default:
		return t.Text
	}
}
