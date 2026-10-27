package luimygo

import (
	"fmt"
	"math"
	"strconv"
	"time"

	"github.com/egoist/mygo/ui"
)

func (b *Backend) switchControl(c *ui.Context, n Node, checked *bool) ui.Element {
	authored := hasSpacing(n, "padding")
	for _, name := range []string{"width", "height", "min-width", "max-width", "min-height", "max-height",
		"width-viewport", "min-width-viewport", "max-width-viewport", "height-viewport", "min-height-viewport", "max-height-viewport",
		"padding", "foreground", "background", "corner-radius", "border-width", "border-color",
		"selected-foreground", "hover-foreground", "focus-within-foreground", "pressed-foreground"} {
		if _, ok := n.Props[name]; ok {
			authored = true
			break
		}
	}
	if !authored {
		return ui.Switch(c, checked).Label(n.String("text"))
	}
	theme := c.Theme()
	e := ui.SwitchBase(c, checked).Label(n.String("text"))
	e.Size(theme.Space(9), theme.Space(5)).Radius(theme.Space(2.5))
	target := float32(0)
	if *checked {
		target = 1
	}
	position := e.Animate("knob", target, 140*time.Millisecond)
	e.Background(theme.Border.Mix(theme.Text, 0.15).Mix(theme.Accent, position))
	foreground := n.String("foreground")
	for _, state := range []struct {
		active bool
		prefix string
	}{
		{n.Bool("selected"), "selected"}, {e.FocusWithin(), "focus-within"},
		{e.Hovered(), "hover"}, {hasPressedStyle(n) && e.Pressed(), "pressed"},
	} {
		if value := n.String(state.prefix + "-foreground"); state.active && value != "" {
			foreground = value
		}
	}
	thumb := ui.RGB(255, 255, 255)
	if foreground != "" {
		thumb = b.color(c, foreground)
	}
	top, right, bottom, left := spacing(n, "padding", float64(theme.Space(0.5)))
	rtl := c.Direction() == ui.RightToLeft
	e.Draw(func(p *ui.Painter, rect ui.Rect) {
		width := max(float32(0), rect.W-left-right)
		height := max(float32(0), rect.H-top-bottom)
		diameter := min(width, height)
		at := position
		if rtl {
			at = 1 - at
		}
		knob := ui.Rect{X: rect.X + left + at*(width-diameter), Y: rect.Y + top + (height-diameter)/2, W: diameter, H: diameter}
		p.Shadow(knob, diameter/2, 0, 1, 3, 0, ui.RGBA(0, 0, 0, 0.25))
		p.Fill(knob, thumb, diameter/2)
	})
	return e
}

// widgetState contains host state whose lifetime follows one retained node.
// Handles are persistent identities; Elements and Contexts belong to one pass.
type widgetState struct {
	nativeColor        ui.Color
	nativeTime         time.Time
	inputText          string
	listIndex          int
	editorFocused      bool
	stepIndex          int
	nativeItems        map[int64]uint64
	nativeOwners       map[int64]uint64
	retired            bool
	treeChildren       []int64
	toastID            string
	toastRegistered    bool
	toastClosed        bool
	tooltipSince       time.Time
	tooltipHover       bool
	tooltipDismissed   bool
	popupDismissed     bool
	submenuOpen        bool
	contextOpen        bool
	contextJustOpened  bool
	contextX, contextY float32
}

func (b *Backend) widget(n Node) *widgetState {
	if b.widgets == nil {
		b.widgets = make(map[int64]*widgetState)
	}
	s := b.widgets[n.ID]
	if s == nil {
		s = &widgetState{}
		b.widgets[n.ID] = s
	}
	return s
}

func (b *Backend) retireWidget(id int64) {
	if s := b.widgets[id]; s != nil {
		s.retired = true
	}
}
func (b *Backend) resetWidgets() {
	for id := range b.widgets {
		b.retireWidget(id)
	}
}

func (b *Backend) beginWidgets(c *ui.Context) {
	if b.probing {
		return
	}
	b.widgetToastsBuilt = false
	for id, s := range b.widgets {
		if !s.retired {
			continue
		}
		if s.toastRegistered && !s.toastClosed {
			s.toastClosed = true
			c.CloseToast(s.toastID)
		}
		delete(b.widgets, id)
	}
}

func (b *Backend) renderWidgetChild(c *ui.Context, id int64) {
	var appearances []Event
	b.render(c, id, &appearances)
	b.queued = append(b.queued, appearances...)
}

func (b *Backend) renderControls(c *ui.Context, n Node, children func(), emit func(Event)) (ui.Element, bool) {
	switch n.Kind {
	case "tabs":
		axis := ui.Horizontal
		if n.String("orientation") == "vertical" {
			axis = ui.Vertical
		}
		// RadioGroup's behavior base activates the newly focused member. LUI
		// supplies the TabList/Tab roles and continues owning selected state.
		e := ui.RadioGroup(c, children).Role(ui.RoleTabList).FocusGroup(axis)
		if axis == ui.Horizontal {
			e.Row()
		}
		return e, true
	case "bottom-tabs":
		e := ui.Column(c)
		e.Children(func() {
			for _, id := range n.Children {
				tab, ok := b.nodes[id]
				if !ok || !tab.Bool("selected") {
					continue
				}
				c.Key("bottom-page-" + strconv.FormatInt(id, 10))
				ui.Column(c).Role(ui.RoleTabPanel).FillWidth().Children(func() {
					for _, child := range tab.Children {
						b.renderWidgetChild(c, child)
					}
				})
				break
			}
			c.Key("bottom-tab-list")
			ui.RadioGroup(c, func() {
				for _, id := range n.Children {
					b.renderWidgetChild(c, id)
				}
			}).Row().Role(ui.RoleTabList).FocusGroup(ui.Horizontal)
		})
		return e, true
	case "bottom-tab":
		return b.widgetButton(c, n, n.String("title"), nil).Role(ui.RoleTab).Selected(n.Bool("selected")), true
	case "link":
		e := ui.LinkBase(c, n.String("url")).Row().AlignItems(ui.Center).Gap(6)
		if n.String("icon-placement") == "top" {
			e.Column()
		}
		e.Children(func() {
			draw := func() {
				if icon := b.icon(n.String("icon")); icon != nil {
					ui.Icon(c, icon).Size(16, 16)
				}
			}
			if n.String("icon-placement") != "trailing" {
				draw()
			}
			ui.Text(c, n.String("text"))
			if n.String("icon-placement") == "trailing" {
				draw()
			}
			children()
		})
		return e, true
	case "button":
		e := b.widgetButton(c, n, n.String("text"), children).Selected(n.Bool("selected"))
		if parent, ok := b.nodes[n.Parent]; ok && parent.Kind == "tabs" {
			e.Role(ui.RoleTab)
		}
		return e, true
	case "toggle-button":
		s := b.state(n)
		e := b.styleWidgetButton(c, n, ui.Toggle(c, &s.checked, ""), n.String("text"), children)
		e.OnChange(func() {
			defer b.reconcileControl(Event{Node: n.ID, Kind: "toggle-changed", incarnation: s.identity})
			if n.Bool("toggle-enabled") {
				emit(Event{Kind: "toggle-changed", Checked: s.checked})
			}
		})
		return e, true
	case "tree":
		roots := b.prepareTree(n.Children)
		return ui.Tree(c, func() {
			for _, id := range roots {
				b.renderWidgetChild(c, id)
			}
		}), true
	case "list-item", "row", "column", "panel", "card", "box":
		if n.String("role") == "treeitem" {
			open := n.Bool("expanded")
			initial := open
			var branch func()
			w := b.widget(n)
			if _, hasExpansion := n.Props["expanded"]; hasExpansion {
				branch = func() {
					for _, id := range w.treeChildren {
						b.renderWidgetChild(c, id)
					}
				}
			}
			e := ui.TreeItem(c, "", &open, branch).Label(n.String("text")).Selected(n.Bool("selected")).Level(int(n.Number("tree-level", 1)))
			if open != initial && n.Bool("toggle-enabled") {
				emit(Event{Kind: "toggle-changed", Checked: open})
			}
			e.Children(func() {
				if n.String("icon-placement") != "trailing" {
					if icon := b.icon(n.String("icon")); icon != nil {
						ui.Icon(c, icon).Size(16, 16)
					}
				}
				ui.Text(c, n.String("text")).SingleLine()
				if n.String("icon-placement") == "trailing" {
					if icon := b.icon(n.String("icon")); icon != nil {
						ui.Icon(c, icon).Size(16, 16)
					}
				}
				children()
			})
			return e, true
		}
	case "select":
		label := n.String("text")
		if label == "" {
			label = n.String("placeholder")
		}
		e := b.widgetButton(c, n, label, children).Role(ui.RolePopUpButton)
		e.OnShortcut(0, ui.KeyDown, func() {
			if n.Bool("press-enabled") {
				emit(Event{Kind: "press"})
			}
		})
		return e, true
	case "checkbox", "toggle", "radio":
		return b.widgetCheck(c, n, children, emit), true
	case "text-field", "secure-field", "input", "search-field", "textarea", "combobox":
		s := b.state(n)
		w := b.widget(n)
		if n.Kind == "input" && !n.Bool("read-only") {
			if w.inputText != s.text || w.nativeTime.IsZero() {
				w.inputText = s.text
				w.nativeColor = ui.RGB(0, 0, 0)
				if validHex(w.inputText) {
					w.nativeColor = ui.Hex(w.inputText)
				}
				w.nativeTime, _ = time.Parse("15:04", w.inputText)
				if w.nativeTime.IsZero() {
					w.nativeTime = time.Date(1970, 1, 1, 0, 0, 0, 0, time.UTC)
				}
			}
			switch n.String("input-type") {
			case "color":
				e := ui.ColorWell(c, &w.nativeColor)
				e.OnChange(func() {
					s.text = fmt.Sprintf("#%02x%02x%02x", w.nativeColor.R, w.nativeColor.G, w.nativeColor.B)
					w.inputText = s.text
					emit(Event{Kind: "text-changed", Text: s.text})
				})
				return e, true
			case "time":
				e := ui.TimeInput(c, &w.nativeTime)
				e.OnChange(func() {
					s.text = w.nativeTime.Format("15:04")
					w.inputText = s.text
					emit(Event{Kind: "text-changed", Text: s.text})
				})
				return e, true
			}
		}
		var e ui.Element
		if n.Kind == "textarea" {
			e = ui.TextArea(c, &s.text)
		} else {
			e = ui.TextInput(c, &s.text)
		}
		e.Placeholder(n.String("placeholder")).Label(n.String("placeholder")).ReadOnly(n.Bool("read-only"))
		if n.Kind == "secure-field" {
			e.Password()
		}
		e.OnChange(func() {
			if !n.Bool("read-only") {
				emit(Event{Kind: "text-changed", Text: s.text})
			}
		})
		if n.Kind == "textarea" && n.Bool("submit-on-enter") {
			identity := s.identity
			e.OnTextKey(func(k ui.TextKey) bool {
				if k.Key != ui.KeyEnter || k.Mods != 0 {
					return false
				}
				if n.Bool("submit-enabled") {
					b.emit(Event{Kind: "submit", Node: n.ID, incarnation: identity})
				}
				return true
			})
		}
		focused := e.Focused()
		if w.editorFocused && !focused && n.Bool("submit-on-blur") && n.Bool("submit-enabled") && n.Props["enabled"] != false {
			emit(Event{Kind: "submit"})
		}
		w.editorFocused = focused
		e.OnSubmit(func() {
			if n.Bool("submit-enabled") {
				emit(Event{Kind: "submit"})
			}
		})
		if n.Kind == "combobox" {
			e.Role(ui.RoleComboBox)
			e.OnShortcut(0, ui.KeyDown, func() {
				if n.Bool("press-enabled") {
					emit(Event{Kind: "press"})
				}
			})
		}
		if len(n.Children) > 0 {
			e.Children(children)
		}
		return e, true
	case "number-stepper":
		s := b.state(n)
		e := ui.NumberInput(c, &s.value, n.Number("min", 0), n.Number("max", math.MaxFloat64), n.Number("step", 1))
		e.OnChange(func() { emit(Event{Kind: "value-changed", Value: s.value}) })
		if len(n.Children) > 0 {
			e.Children(children)
		}
		return e, true
	}
	return ui.Element{}, false
}

// The public tree carries flat retained rows with explicit levels. Build the
// toolkit's hierarchy from those levels so its disclosure, focus traversal and
// accessibility share the same parent relationships.
func (b *Backend) prepareTree(ids []int64) []int64 {
	var roots, stack []int64
	for _, id := range ids {
		n, ok := b.nodes[id]
		if !ok {
			continue
		}
		w := b.widget(n)
		w.treeChildren = nil
		level := int(n.Number("tree-level", 1))
		for len(stack) > 0 {
			parent := b.nodes[stack[len(stack)-1]]
			if int(parent.Number("tree-level", 1)) < level {
				break
			}
			stack = stack[:len(stack)-1]
		}
		if len(stack) == 0 {
			roots = append(roots, id)
		} else {
			parent := b.widget(b.nodes[stack[len(stack)-1]])
			parent.treeChildren = append(parent.treeChildren, id)
		}
		stack = append(stack, id)
	}
	return roots
}

// widgetButton retains MyGo's native button behavior and theme while composing
// portable labels and icons as ordinary children.
func (b *Backend) widgetButton(c *ui.Context, n Node, label string, children func()) ui.Element {
	var e ui.Element
	if n.String("variant") == "primary" {
		e = ui.PrimaryButton(c, "")
	} else {
		e = ui.Button(c, "")
	}
	return b.styleWidgetButton(c, n, e.Bind(&b.state(n).handle), label, children)
}

func (b *Backend) styleWidgetButton(c *ui.Context, n Node, e ui.Element, label string, children func()) ui.Element {
	switch n.String("size") {
	case "sm":
		e.Padding(3, 8)
	case "lg":
		e.Padding(10, 20)
	case "icon":
		e.Padding(6).MinWidth(30).MinHeight(30)
	}
	if n.String("variant") == "outline" {
		e.Background(ui.Color{}).Border(1, c.Theme().Border)
	}
	if n.String("variant") == "secondary" {
		e.Background(c.Theme().SurfaceHover)
	}
	if n.String("variant") == "ghost" {
		e.Background(ui.Color{}).Border(0, ui.Color{})
	}
	if n.String("variant") == "destructive" {
		e.Background(c.Theme().Danger).TextColor(ui.RGB(255, 255, 255))
	}
	if n.String("icon-placement") == "top" {
		e.Column()
	}
	e.Gap(6)
	e.Children(func() {
		icon := b.icon(n.String("icon"))
		drawIcon := func() {
			if icon != nil {
				ui.Icon(c, icon).Size(16, 16)
			}
		}
		if n.String("icon-placement") != "trailing" {
			drawIcon()
		}
		if label != "" {
			ui.Text(c, label).SingleLine()
		}
		if n.String("icon-placement") == "trailing" {
			drawIcon()
		}
		if children != nil {
			children()
		}
	})
	return e
}

func (b *Backend) widgetCheck(c *ui.Context, n Node, children func(), emit func(Event)) ui.Element {
	s := b.state(n)
	t := c.Theme()
	var e ui.Element
	if n.Kind == "radio" {
		e = ui.RadioBase(c, &s.checked, true)
	} else {
		e = ui.CheckboxBase(c, &s.checked)
	}
	// Decorative indicator glyphs must not become part of the accessible name.
	e.Label(n.String("text")).Gap(8).AlignItems(ui.Center)
	e.Children(func() {
		radius := float32(4)
		if n.Kind == "radio" {
			radius = 8
		}
		border := t.Border
		key := "indicator-border-color"
		if s.checked {
			key = "checked-indicator-border-color"
		}
		if value := n.String(key); value != "" {
			border = b.color(c, value)
		}
		box := ui.Box(c).Size(16, 16).Radius(radius).Border(1, border).Center()
		if s.checked {
			box.Background(t.Accent).Children(func() {
				if n.Kind == "radio" {
					ui.Box(c).Size(6, 6).Radius(3).Background(t.AccentText)
				} else {
					ui.Text(c, "✓").FontSize(12).TextColor(t.AccentText)
				}
			})
		}
		if text := n.String("text"); text != "" {
			ui.Text(c, text).Opacity(float32(n.Number("label-opacity", 1)))
		}
		children()
	})
	e.OnChange(func() {
		defer b.reconcileControl(Event{Node: n.ID, Kind: "toggle-changed", incarnation: s.identity})
		checked := s.checked
		if n.Kind == "radio" && n.Bool("change-enabled") {
			emit(Event{Kind: "change"})
		}
		if n.Bool("toggle-enabled") {
			emit(Event{Kind: "toggle-changed", Checked: checked})
		}
	})
	return e
}
