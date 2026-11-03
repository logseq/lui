package luimygo

import (
	"strconv"

	"github.com/egoist/mygo/ui"
)

func (b *Backend) renderComposites(c *ui.Context, n Node, children func(), emit func(Event)) (ui.Element, bool) {
	t := c.Theme()
	switch n.Kind {
	case "toolbar":
		e := ui.Toolbar(c, children)
		switch n.String("placement") {
		case "bottom":
			e.Absolute().Left(0).Right(0).Bottom(0)
		case "principal", "status":
			e.Justify(ui.Center)
		case "primary-action", "confirmation-action", "destructive-action", "top-bar-trailing":
			e.Justify(ui.End)
		case "navigation", "secondary-action", "cancellation-action", "top-bar-leading":
			e.Justify(ui.Start)
		}
		if n.String("orientation") == "vertical" {
			e.Column().FocusGroup(ui.Vertical)
		}
		return e, true
	case "input-group":
		return ui.Column(c).Gap(0).Border(1, t.Border).Radius(t.Radius).Clip().Children(children), true
	case "input-group-actions":
		return ui.Row(c).AlignItems(ui.Center).Gap(6).Padding(4, 8, 8).Children(children), true
	case "button-group":
		return ui.Row(c).AlignItems(ui.Center).Gap(0).Role(ui.RoleGroup).Children(children), true
	case "toggle-group":
		return ui.ToggleGroup(c, children), true
	case "breadcrumb":
		e := ui.Row(c).AlignItems(ui.Center).Gap(6)
		e.Children(func() {
			for i, id := range n.Children {
				if i > 0 {
					ui.Text(c, "›").TextColor(t.TextMuted)
				}
				b.renderWidgetChild(c, id)
			}
		})
		return e, true
	case "pagination":
		return ui.Row(c).AlignItems(ui.Center).Gap(4).Role(ui.RoleGroup).Children(children), true
	case "stepper":
		e := ui.Row(c).AlignItems(ui.Center).Gap(8).Role(ui.RoleGroup)
		e.Children(func() {
			for i, id := range n.Children {
				b.widget(b.nodes[id]).stepIndex = i
				if i > 0 {
					ui.Divider(c).Width(32)
				}
				b.renderWidgetChild(c, id)
			}
		})
		return e, true
	case "step":
		parent := b.nodes[n.Parent]
		index := b.widget(n).stepIndex
		active := int(parent.Number("active", 0))
		color := t.TextMuted
		fill := t.Surface
		if index <= active {
			color = t.AccentText
			fill = t.Accent
		}
		e := ui.Row(c).AlignItems(ui.Center).Gap(8)
		e.Children(func() {
			ui.Box(c).Size(26, 26).Radius(13).Background(fill).Center().Children(func() {
				label := strconv.Itoa(index + 1)
				if index < active {
					label = "✓"
				}
				ui.Text(c, label).TextColor(color)
			})
			label := ui.Text(c, n.String("text"))
			if index == active {
				label.Bold()
			} else if index > active {
				label.TextColor(t.TextMuted)
			}
		})
		return e, true
	case "timeline":
		return ui.Column(c).Gap(float32(n.Number("gap", 12))).Role(ui.RoleList).Children(children), true
	case "timeline-item":
		e := ui.Row(c).AlignItems(ui.Start).Gap(12).Role(ui.RoleListItem)
		if n.Bool("selected") {
			e.Background(t.Surface).Radius(t.Radius)
		}
		e.Children(func() {
			ui.Column(c).AlignItems(ui.Center).Gap(4).Children(func() {
				ui.Box(c).Size(24, 24).Radius(12).Background(t.Accent).Center().Children(func() {
					if icon := b.icon(n.String("icon")); icon != nil {
						ui.Icon(c, icon).Size(16, 16).TextColor(t.AccentText)
					} else {
						ui.Text(c, n.String("indicator")).TextColor(t.AccentText)
					}
				})
				if n.Bool("connector") {
					ui.Box(c).Width(1).Height(32).Background(t.Border)
				}
			})
			ui.Column(c).Gap(3).Children(func() {
				ui.Text(c, n.String("title")).Bold()
				if text := n.String("description"); text != "" {
					ui.Text(c, text)
				}
				if text := n.String("meta"); text != "" {
					ui.Text(c, text).TextColor(t.TextMuted)
				}
			})
		})
		return e, true
	case "list-section":
		index := 0
		for _, id := range n.Children {
			if b.nodes[id].Kind == "list-item" {
				b.widget(b.nodes[id]).listIndex = index
				index++
			}
		}
		return ui.Column(c).Gap(0).Children(children), true
	case "list-item":
		if _, disclosure := n.Props["expanded"]; disclosure {
			s := b.state(n)
			root := ui.Column(c).Gap(0)
			root.Children(func() {
				parts := ui.CollapsibleBase(c, &s.checked)
				b.styleWidgetButton(c, n, parts.Trigger, n.String("text"), nil).Label(n.String("text"))
				parts.Trigger.OnChange(func() {
					defer b.reconcileControl(Event{Node: n.ID, Kind: "toggle-changed", incarnation: s.identity})
					if n.Bool("toggle-enabled") {
						emit(Event{Kind: "toggle-changed", Checked: s.checked})
					}
				})
				parts.Panel(children)
			})
			return root, true
		}
		parent := b.nodes[n.Parent]
		direct := parent.Kind == "list" || parent.Kind == "virtual-list"
		marker := n.String("list-style")
		if !direct && marker == "" {
			for ancestor := parent; ancestor.ID != 0; ancestor = b.nodes[ancestor.Parent] {
				if value := ancestor.String("list-style"); value != "" {
					marker = value
					break
				}
			}
		}
		e := b.widgetButton(c, n, "", func() {
			if !direct && (marker == "disc" || marker == "decimal") {
				text := "•"
				if marker == "decimal" {
					index := b.widget(n).listIndex + 1
					text = strconv.Itoa(index) + "."
				}
				ui.Text(c, text).MinWidth(20).TextAlign(ui.End)
			}
			ui.Text(c, n.String("text"))
			children()
		}).Role(ui.RoleListItem).Selected(n.Bool("selected"))
		if !direct && n.String("separator") == "visible" {
			e.DrawOver(func(p *ui.Painter, r ui.Rect) { p.Fill(ui.Rect{X: r.X, Y: r.Y + r.H - 1, W: r.W, H: 1}, t.Border, 0) })
		}
		return e, true
	case "swipe-action":
		if host, menu, ok := b.widgetContextOwner(n); ok {
			e := b.widgetButton(c, n, n.String("text"), nil).Role(ui.RoleMenuItem)
			e.OnClick(func() { b.closeWidgetContext(host, menu) })
			return e, true
		}
		return ui.Element{}, true
	case "swipe-actions":
		// Row actions are attached to their owner as a native context menu by
		// decorateWidget. This gives desktop users pointer and keyboard access.
		return ui.Element{}, true
	}
	return ui.Element{}, false
}
