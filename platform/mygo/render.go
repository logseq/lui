package luimygo

import (
	"slices"
	"strings"

	"github.com/egoist/mygo/ui"
)

// Standard kinds use built-in layout, behavior and resource adapters.
var nativeKinds = strings.Fields(`root row column grid panel card alert bubble box
 text heading paragraph label button toggle-button toggle radio-group radio
 slider number-stepper text-field secure-field input search-field textarea
 checkbox switch progress divider scroll list tabs bottom-tabs bottom-tab
 button-group toggle-group spacer spinner select combobox menu-item list-item
 avatar input-group input-group-actions
 breadcrumb pagination accordion table-row table-cell tree dialog sheet
 toolbar status-bar list-section list-section-header list-section-footer link kbd
 dropdown-menu context-menu menu-trigger tooltip toast stepper step timeline timeline-item swipe-actions swipe-action
 stack overlay edge-inset view-that-fits virtual-list table split resizable icon image media-surface file-image file-picker file-preview drawer popover`)

func SupportedKinds() []string       { kinds := slices.Clone(nativeKinds); slices.Sort(kinds); return kinds }
func supportedKind(kind string) bool { return slices.Contains(nativeKinds, kind) }

func (b *Backend) state(n Node) *controlState {
	s := b.states[n.ID]
	if s == nil {
		identity := uint64(n.ID)
		if !b.probing {
			b.nextIdentity++
			identity = b.nextIdentity
		}
		s = &controlState{text: n.String("text"), checked: n.Bool("checked") || n.Bool("selected") || n.Bool("expanded"), value: n.Number("value", 0), identity: identity}
		b.states[n.ID] = s
	}
	return s
}
func (b *Backend) emit(e Event) {
	if b.probing || b.closed {
		return
	}
	if e.incarnation == 0 {
		if s := b.states[e.Node]; s != nil {
			e.incarnation = s.identity
		}
	}
	if b.building {
		b.queued = append(b.queued, e)
		return
	}
	n, ok := b.nodes[e.Node]
	if !ok || (e.incarnation != 0 && (b.states[e.Node] == nil || b.states[e.Node].identity != e.incarnation)) {
		return
	}
	defer b.reconcileControl(e)
	if b.interactionBlocked(n, e) {
		return
	}
	if !eventAllowed(n, e) {
		return
	}
	if b.config.Dispatch != nil {
		if err := b.config.Dispatch(e); err != nil && b.err == nil {
			b.err = err
		}
	}
}
func (b *Backend) View(c *ui.Context) {
	b.viewGeneration = b.generation
	if b.closed {
		return
	}
	textGeneration := b.generation
	c.AfterFrame(func() { b.textGeneration = textGeneration })
	var appearances []Event
	b.systemTheme = c.Theme()
	previousTheme := c.Theme()
	if len(b.tokens) > 0 {
		next := *previousTheme
		b.applyThemeSlots(c, &next)
		defer c.SetTheme(previousTheme)
	}
	b.beginWidgets(c)
	b.prepareResources(c)
	b.prepareFiles(c)
	for _, id := range b.Roots() {
		b.render(c, id, &appearances)
	}
	// Virtual row and fitting builders run during layout, after View returns.
	// Only the final committed pass may dispatch their queued lifecycle events.
	c.AfterFrame(func() {
		pending := append(appearances, b.queued...)
		b.queued = nil
		for _, event := range pending {
			if event.Kind == "appear" {
				state := b.states[event.Node]
				if state == nil || state.identity != event.incarnation || state.appeared {
					continue
				}
				state.appeared = true
			}
			b.emit(event)
		}
		if len(pending) > 0 {
			c.Invalidate()
		}
		for key, owner := range b.menuOwners {
			if !owner.current(b, c) {
				delete(b.menuOwners, key)
			}
		}
	})
}
func (b *Backend) render(c *ui.Context, id int64, appearances *[]Event) {
	previousBuilding := b.building
	b.building = true
	defer func() { b.building = previousBuilding }()
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
		e.incarnation = s.identity
		b.emit(e)
		c.Invalidate()
	}
	if !b.probing && n.Bool("appear-enabled") && !s.appeared {
		*appearances = append(*appearances, Event{Kind: "appear", Node: id, incarnation: s.identity})
	}
	if n.Kind == "extension" {
		b.config.Extensions[n.Identifier].Render(c, n.clone(), children, emit)
		return
	}
	if n.Kind == "table" {
		s.collection.tableColumns = collectionTableColumns(n.Children, func(id int64) Node { return b.nodes[id] })
	}
	if custom := b.config.Renderers[n.Kind]; custom != nil {
		custom(c, n.clone(), children, emit)
		return
	}
	var e ui.Element
	handled := false
	for _, hook := range []func(*ui.Context, Node, *controlState, *[]Event) (ui.Element, bool){b.renderLayout, b.renderCollections, b.renderResources, b.renderFiles} {
		if e, handled = hook(c, n, s, appearances); handled {
			children = func() {}
			break
		}
	}
	if !handled {
		for _, hook := range []func(*ui.Context, Node, func(), func(Event)) (ui.Element, bool){b.renderControls, b.renderMenus, b.renderComposites, b.renderOverlays} {
			if e, handled = hook(c, n, children, emit); handled {
				children = func() {}
				break
			}
		}
	}
	if !handled {
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
				defer b.reconcileControl(Event{Node: id, Kind: "toggle-changed", incarnation: s.identity})
				if n.Bool("toggle-enabled") {
					emit(Event{Kind: "toggle-changed", Checked: s.checked})
				}
			})

		case "checkbox", "toggle":
			e = ui.Checkbox(c, &s.checked, n.String("text"))
			e.OnChange(func() {
				defer b.reconcileControl(Event{Node: id, Kind: "toggle-changed", incarnation: s.identity})
				if n.Bool("toggle-enabled") {
					emit(Event{Kind: "toggle-changed", Checked: s.checked})
				}
			})
		case "switch":
			e = ui.Switch(c, &s.checked).Label(n.String("text"))
			e.OnChange(func() {
				defer b.reconcileControl(Event{Node: id, Kind: "toggle-changed", incarnation: s.identity})
				if n.Bool("toggle-enabled") {
					emit(Event{Kind: "toggle-changed", Checked: s.checked})
				}
			})
		case "radio":
			e = ui.Radio(c, &s.checked, true, n.String("text"))
			e.OnChange(func() {
				defer b.reconcileControl(Event{Node: id, Kind: "toggle-changed", incarnation: s.identity})
				checked := s.checked
				if n.Bool("change-enabled") {
					emit(Event{Kind: "change"})
				}
				if n.Bool("toggle-enabled") {
					emit(Event{Kind: "toggle-changed", Checked: checked})
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
			e = ui.Spacer(c).PassThrough()
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
				defer b.reconcileControl(Event{Node: id, Kind: "toggle-changed", incarnation: s.identity})
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
	}
	e.Bind(&s.handle)
	if !b.probing {
		b.decorateWidget(c, n, e)
	}
	if n.Kind == "root" {
		e.Background(c.Theme().Background).TextColor(c.Theme().Text)
	}
	if n.String("theme") != "" || n.String("theme-mode") != "" {
		e.TextColor(c.Theme().Text)
	}
	b.style(c, n, e)
	if !b.probing && n.Bool("autofocus") && !s.focused {
		e.Focus()
		s.focused = true
	}
	b.bindEvents(c, n, s, e, emit)
	if text := n.String("tooltip"); text != "" {
		if keys := n.String("tooltip-keys"); keys != "" {
			text += " (" + keys + ")"
		}
		e.Tooltip(text)
	}
	if len(n.Children) > 0 {
		e.Children(children)
	}
}
