package luimygo

import (
	"bytes"
	"image/png"
	"strconv"
	"time"

	"github.com/egoist/mygo/ui"
)

func (b *Backend) renderMenus(c *ui.Context, n Node, children func(), emit func(Event)) (ui.Element, bool) {
	switch n.Kind {
	case "dropdown-menu":
		if parent, ok := b.nodes[n.Parent]; ok && (parent.Kind == "menu-trigger" || parent.Kind == "menu-item") && !b.widget(parent).submenuOpen {
			return ui.Element{}, true
		}
		if b.probing {
			return ui.Element{}, true
		}
		w := b.widget(n)
		var panel ui.Element
		ui.Overlay(c, func() {
			anchor := b.menuAnchor(c, n)
			if !anchor.Valid() {
				c.Key("menu-point-" + strconv.FormatInt(n.ID, 10))
				anchor = ui.Box(c).Absolute().PassThrough().Role(ui.RoleNone).Left(float32(n.Number("x", 0))).Top(float32(n.Number("y", 0))).Size(0, 0)
			}
			c.Key(b.state(n).identity)
			width, height := c.Size()
			padding := float32(n.Number("collision-padding", 8))
			panel = ui.Scroll(c).Column().Role(ui.RoleMenu).FocusGroup(ui.Vertical).Padding(4).Gap(2).Radius(c.Theme().Radius).Background(c.Theme().Surface).Border(1, c.Theme().Border).Modal().CollisionPadding(padding).MaxWidth(max(0, width-2*padding)).MaxHeight(max(0, height-2*padding))
			b.placeWidgetPopup(n, panel, anchor)
			childOpen := b.widgetSubmenuOpen(n)
			panel.Children(children)
			owner := b.menuAnchorNode(n)
			if owner.ID == 0 {
				owner = n
			}
			panel.Bind(&b.recordMenuOwner(n, owner, false, false).panel)
			parent, nested := b.nodes[n.Parent]
			nested = nested && (parent.Kind == "menu-trigger" || parent.Kind == "menu-item")
			back := nested && panel.OverlayShortcut(0, ui.KeyLeft)
			if !w.popupDismissed && (back || panel.OverlayShortcut(0, ui.KeyEscape) || !childOpen && panel.PressedOutside()) {
				w.popupDismissed = true
				if nested {
					b.widget(parent).submenuOpen = false
					c.Resolve(b.state(parent).handle).Focus()
				}
				emit(Event{Kind: "dismiss"})
			}
		})
		return panel, true
	case "menu-item":
		branch := b.widgetHasSubmenu(n)
		w := b.widget(n)
		e := b.widgetButton(c, n, "", func() {
			selected := n.Bool("selected") || n.Bool("checked")
			placement := n.String("selection-placement")
			if placement == "top" {
				ui.Column(c).AlignItems(ui.Center).Children(func() {
					if selected {
						ui.Text(c, "✓")
					}
					ui.Text(c, n.String("text"))
				})
			} else {
				if selected && placement != "trailing" {
					ui.Text(c, "✓")
				}
				ui.Text(c, n.String("text"))
				if selected && placement == "trailing" {
					ui.Text(c, "✓")
				}
			}
			if !branch || w.submenuOpen {
				children()
			}
		}).Role(ui.RoleMenuItem).Label(n.String("text")).Selected(n.Bool("selected") || n.Bool("checked"))
		if n.String("shortcut-hint") != "" {
			e.Description(n.String("shortcut-hint"))
		}
		if parent, ok := b.nodes[n.Parent]; ok && (parent.Kind == "dropdown-menu" || parent.Kind == "context-menu") {
			for _, id := range parent.Children {
				candidate := b.nodes[id]
				if candidate.Kind != "menu-item" && candidate.Kind != "menu-trigger" || candidate.Props["enabled"] == false {
					continue
				}
				if id == n.ID {
					e.AutoFocus()
				}
				break
			}
		}
		if branch {
			e.Role(ui.RoleMenuButton)
			b.widgetSubmenuTrigger(c, n, e)
		} else if host, menu, ok := b.widgetContextOwner(n); ok {
			e.OnClick(func() { b.closeWidgetContext(host, menu) })
		}
		return e, true
	case "menu-trigger":
		w := b.widget(n)
		e := b.widgetButton(c, n, n.String("text"), nil).Role(ui.RoleMenuButton).Bind(&b.state(n).handle)
		b.widgetSubmenuTrigger(c, n, e)
		e.Children(func() {
			if w.submenuOpen {
				children()
			}
		})
		return e, true
	case "context-menu":
		// Its parent owns presentation through decorateWidget's native menu.
		return ui.Element{}, true
	case "tooltip":
		if n.String("anchor") == "" {
			return ui.Text(c, n.String("text")).Role(ui.RoleStatus), true
		}
		if b.probing {
			return ui.Element{}, true
		}
		anchor := b.menuAnchor(c, n)
		if !anchor.Valid() {
			return ui.Element{}, true
		}
		anchor.Description(n.String("text"))
		if _, custom := n.Props["tooltip-delay"]; !custom {
			tip := ui.TooltipBase(c, anchor, func(tip ui.Element) { b.styleWidgetTip(c, n, tip, anchor) })
			return tip, true
		}
		w := b.widget(n)
		hovered := anchor.Hovered()
		focused := anchor.Focused() && anchor.FocusVisible()
		active := hovered || focused
		if !active {
			w.tooltipHover = false
			w.tooltipSince = time.Time{}
			w.tooltipDismissed = false
			return ui.Element{}, true
		}
		if !w.tooltipHover {
			w.tooltipHover = true
			w.tooltipSince = c.Now()
		}
		if anchor.Pressed() {
			w.tooltipDismissed = true
		}
		delay := time.Duration(n.Number("tooltip-delay", 600)) * time.Millisecond
		if focused {
			delay = 0
		}
		remaining := delay - c.Now().Sub(w.tooltipSince)
		if remaining > 0 {
			c.After(remaining)
			return ui.Element{}, true
		}
		if w.tooltipDismissed {
			return ui.Element{}, true
		}
		var tip ui.Element
		ui.Overlay(c, func() {
			c.Key(b.state(n).identity)
			tip = ui.Box(c).Absolute().PassThrough().Role(ui.RoleTooltip)
			b.styleWidgetTip(c, n, tip, anchor)
			if tip.OverlayShortcut(0, ui.KeyEscape) {
				w.tooltipDismissed = true
			}
		})
		return tip, true
	case "toast":
		if b.probing {
			return ui.Element{}, true
		}
		w := b.widget(n)
		if !w.toastRegistered {
			w.toastRegistered = true
			w.toastID = "lui-" + strconv.FormatUint(b.state(n).identity, 10)
			duration := time.Duration(n.Number("duration", 4000)) * time.Millisecond
			if duration == 0 {
				duration = -1
			}
			id := n.ID
			c.AddToast(ui.Toast{ID: w.toastID, Title: n.String("accessibility-label"), Timeout: duration, Data: id, OnClose: func() {
				w.toastClosed = true
				if current := b.widgets[id]; current == w && !w.retired {
					b.emit(Event{Kind: "dismiss", Node: id})
				}
			}})
		}
		if !b.widgetToastsBuilt {
			b.widgetToastsBuilt = true
			ui.ToastViewportBase(c, func(viewport ui.Element, toasts []ui.Toast) {
				viewport.Padding(16).Gap(8).AlignItems(ui.End)
				viewport.Children(func() {
					for _, toast := range toasts {
						id, ok := toast.Data.(int64)
						if !ok {
							continue
						}
						current, ok := b.nodes[id]
						if !ok {
							continue
						}
						parts := ui.ToastBase(c, toast)
						parts.Root.Padding(12).Radius(c.Theme().Radius).Background(c.Theme().Surface).Border(1, c.Theme().Border).MinWidth(220)
						b.style(c, current, parts.Root)
						parts.Root.Children(func() {
							for _, child := range current.Children {
								b.renderWidgetChild(c, child)
							}
						})
					}
				})
			})
		}
		return ui.Element{}, true
	}
	return ui.Element{}, false
}

func (b *Backend) menuAnchor(c *ui.Context, n Node) ui.Element {
	owner := b.menuAnchorNode(n)
	if owner.ID == 0 {
		return ui.Element{}
	}
	return c.Resolve(b.state(owner).handle)
}

func (b *Backend) menuAnchorNode(n Node) Node {
	parent, ok := b.nodes[n.Parent]
	if !ok {
		return Node{}
	}
	if parent.Kind == "menu-trigger" || parent.Kind == "menu-item" {
		return parent
	}
	for i, id := range parent.Children {
		if id == n.ID && i > 0 {
			return b.nodes[parent.Children[i-1]]
		}
	}
	return Node{}
}

func (b *Backend) placeWidgetPopup(n Node, panel, anchor ui.Element) {
	if n.Kind == "dropdown-menu" && n.String("anchor") == "" {
		parent := b.nodes[n.Parent]
		if parent.Kind == "menu-item" || parent.Kind == "menu-trigger" {
			n = n.clone()
			n.Props["anchor"] = "right"
		}
	}
	at, self := widgetPopupAnchors(n)
	panel.AttachTo(anchor, at, self)
	offset := float32(n.Number("anchor-offset", 0))
	switch n.String("anchor") {
	case "above":
		panel.Margin(0, 0, offset, 0)
	case "left":
		panel.Margin(0, offset, 0, 0)
	case "right":
		panel.Margin(0, 0, 0, offset)
	default:
		panel.Margin(offset, 0, 0, 0)
	}
}
func widgetPopupAnchors(n Node) (ui.Anchor, ui.Anchor) {
	alignment := n.String("anchor-alignment")
	switch n.String("anchor") {
	case "left":
		switch alignment {
		case "end":
			return ui.AnchorBottomStart, ui.AnchorBottomEnd
		case "center":
			return ui.AnchorStart, ui.AnchorEnd
		default:
			return ui.AnchorTopStart, ui.AnchorTopEnd
		}
	case "right":
		switch alignment {
		case "end":
			return ui.AnchorBottomEnd, ui.AnchorBottomStart
		case "center":
			return ui.AnchorEnd, ui.AnchorStart
		default:
			return ui.AnchorTopEnd, ui.AnchorTopStart
		}
	case "above":
		switch alignment {
		case "end":
			return ui.AnchorTopEnd, ui.AnchorBottomEnd
		case "center":
			return ui.AnchorTop, ui.AnchorBottom
		default:
			return ui.AnchorTopStart, ui.AnchorBottomStart
		}
	default:
		switch alignment {
		case "end":
			return ui.AnchorBottomEnd, ui.AnchorTopEnd
		case "center":
			return ui.AnchorBottom, ui.AnchorTop
		default:
			return ui.AnchorBottomStart, ui.AnchorTopStart
		}
	}
}

func (b *Backend) styleWidgetTip(c *ui.Context, n Node, tip, anchor ui.Element) {
	tip.Padding(5, 8).Radius(5).Background(c.Theme().Text).TextColor(c.Theme().Background)
	b.placeWidgetPopup(n, tip, anchor)
	tip.Children(func() { ui.Text(c, n.String("text")) })
}

// Native menu behavior supplies platform keyboard traversal, checked and
// disabled semantics, and the Shift+F10 accessibility path for row actions.
func (b *Backend) decorateWidget(c *ui.Context, n Node, e ui.Element) {
	if b.probing || !e.Valid() {
		return
	}
	var menuID, actionsID int64
	for _, id := range n.Children {
		child := b.nodes[id]
		if child.Kind == "context-menu" {
			menuID = id
		}
		if child.Kind == "swipe-actions" {
			actionsID = id
		}
	}
	if menuID != 0 || actionsID != 0 {
		if b.widget(n).contextOpen || b.widgetMenuNeedsRetained(menuID) || b.widgetMenuNeedsRetained(actionsID) {
			b.decorateRetainedContext(c, n, e, menuID, actionsID)
			return
		}
		w := b.widget(n)
		e.ContextMenu(func(m *ui.Menu) {
			b.recordMenuOwner(n, n, true, false)
			if w.nativeItems == nil {
				w.nativeItems = make(map[int64]uint64)
				w.nativeOwners = make(map[int64]uint64)
				for _, owner := range []int64{menuID, actionsID} {
					if node, ok := b.nodes[owner]; ok {
						w.nativeOwners[owner] = b.state(node).identity
					}
				}
			}
			for _, owner := range []int64{menuID, actionsID} {
				node, ok := b.nodes[owner]
				if !ok || w.nativeOwners[owner] != b.state(node).identity {
					continue
				}
				b.fillWidgetMenu(m, node.Children, w.nativeItems)
			}
		}).OnMenuDismiss(func() {
			if menuID != 0 {
				if menu, ok := b.nodes[menuID]; ok && w.nativeOwners[menuID] == b.state(menu).identity {
					// Native selection runs while building, while this notice runs after
					// frame commit. Append after its queued Press to preserve event order.
					b.queued = append(b.queued, Event{Kind: "dismiss", Node: menuID, incarnation: b.state(menu).identity})
				}
			}
			w.nativeItems = nil
			w.nativeOwners = nil
		})
	}
}

func (b *Backend) fillWidgetMenu(m *ui.Menu, ids []int64, identities map[int64]uint64) {
	for _, id := range ids {
		n, ok := b.nodes[id]
		if !ok {
			continue
		}
		switch n.Kind {
		case "divider":
			m.Separator()
		case "menu-trigger":
			m.Submenu(n.String("text"), func(sub *ui.Menu) {
				for _, child := range n.Children {
					if menu, ok := b.nodes[child]; ok {
						b.fillWidgetMenu(sub, menu.Children, identities)
					}
				}
			}).Disabled(n.Props["enabled"] == false).ImagePNG(b.widgetMenuIcon(n))
		case "menu-item", "swipe-action":
			if b.widgetHasSubmenu(n) {
				m.Submenu(n.String("text"), func(sub *ui.Menu) {
					for _, child := range n.Children {
						if node := b.nodes[child]; node.Kind == "dropdown-menu" {
							b.fillWidgetMenu(sub, node.Children, identities)
						}
					}
				}).Disabled(n.Props["enabled"] == false).ImagePNG(b.widgetMenuIcon(n))
				continue
			}
			identity := b.state(n).identity
			if _, known := identities[id]; !known {
				identities[id] = identity
			}
			item := m.Item(n.String("text")).Disabled(n.Props["enabled"] == false).ImagePNG(b.widgetMenuIcon(n))
			if n.Bool("selected") || n.Bool("checked") {
				item.Checked(true)
			}
			if item.Chosen() && n.Bool("press-enabled") && identities[id] == identity {
				b.emit(Event{Kind: "press", Node: id, incarnation: identity})
			}
		}
	}
}

func (b *Backend) widgetMenuIcon(n Node) []byte {
	icon := b.icon(n.String("icon"))
	if icon == nil {
		return nil
	}
	ink := b.systemTheme.Text
	if n.String("variant") == "destructive" {
		ink = b.systemTheme.Danger
	}
	image := icon.RasterizeIcon(16, 16, ink)
	if image == nil {
		return nil
	}
	var encoded bytes.Buffer
	if png.Encode(&encoded, image) != nil {
		return nil
	}
	return encoded.Bytes()
}

// Native OS menus expose only their own typography and check placement. A
// portable customization selects retained MyGo menu content for this opening.
func (b *Backend) widgetMenuNeedsRetained(id int64) bool {
	n, ok := b.nodes[id]
	if !ok {
		return false
	}
	if n.Kind == "menu-item" || n.Kind == "menu-trigger" || n.Kind == "swipe-action" {
		for _, child := range n.Children {
			if b.nodes[child].Kind != "dropdown-menu" {
				return true
			}
		}
		for key := range n.Props {
			switch key {
			case "text", "enabled", "icon", "selected", "checked", "press-enabled", "appear-enabled", "accessibility-identifier", "edge":
			default:
				return true
			}
		}
	}
	for _, child := range n.Children {
		if b.widgetMenuNeedsRetained(child) {
			return true
		}
	}
	return false
}

func (b *Backend) decorateRetainedContext(c *ui.Context, host Node, e ui.Element, menuID, actionsID int64) {
	w := b.widget(host)
	e.ContextMenuBase(func(x, y float32) {
		for _, owner := range []int64{menuID, actionsID} {
			b.resetWidgetMenu(owner)
		}
		w.contextOpen = true
		w.contextJustOpened = true
		w.contextX = x
		w.contextY = y
	})
	if !w.contextOpen {
		return
	}
	c.AfterFrame(func() { w.contextJustOpened = false })
	ui.Overlay(c, func() {
		c.Key("context-point-" + strconv.FormatInt(host.ID, 10))
		anchor := ui.Box(c).Absolute().Left(w.contextX).Top(w.contextY).Size(0, 0).PassThrough().Role(ui.RoleNone)
		c.Key("context-" + strconv.FormatInt(host.ID, 10))
		width, height := c.Size()
		panel := ui.Scroll(c).Column().AttachTo(anchor, ui.AnchorBottomStart, ui.AnchorTopStart).CollisionPadding(8).MaxWidth(width-16).MaxHeight(height-16).Role(ui.RoleMenu).FocusGroup(ui.Vertical).Modal().Padding(4).Gap(2).Radius(c.Theme().Radius).Background(c.Theme().Surface).Border(1, c.Theme().Border)
		panel.Bind(&b.recordMenuOwner(host, host, false, true).panel)
		childOpen := b.widgetSubmenuOpen(b.nodes[menuID]) || b.widgetSubmenuOpen(b.nodes[actionsID])
		panel.Children(func() {
			for _, owner := range []int64{menuID, actionsID} {
				if node, ok := b.nodes[owner]; ok {
					for _, child := range node.Children {
						b.renderWidgetChild(c, child)
					}
				}
			}
		})
		if panel.OverlayShortcut(0, ui.KeyEscape) || !childOpen && !w.contextJustOpened && panel.PressedOutside() {
			b.closeWidgetContext(host, b.nodes[menuID])
		}
	})
}

func (b *Backend) widgetContextOwner(n Node) (Node, Node, bool) {
	for parent := b.nodes[n.Parent]; parent.ID != 0; parent = b.nodes[parent.Parent] {
		if parent.Kind == "context-menu" || parent.Kind == "swipe-actions" {
			host := b.nodes[parent.Parent]
			if b.widget(host).contextOpen {
				return host, parent, true
			}
			return Node{}, Node{}, false
		}
	}
	return Node{}, Node{}, false
}
func (b *Backend) closeWidgetContext(host, menu Node) {
	w := b.widget(host)
	if !w.contextOpen {
		return
	}
	w.contextOpen = false
	if menu.Kind == "swipe-actions" {
		for _, id := range host.Children {
			if b.nodes[id].Kind == "context-menu" {
				menu = b.nodes[id]
				break
			}
		}
	}
	if menu.Kind == "context-menu" {
		identity := b.state(menu).identity
		b.queued = append(b.queued, Event{Kind: "dismiss", Node: menu.ID, incarnation: identity})
	}
}

func (b *Backend) resetWidgetMenu(id int64) {
	n, ok := b.nodes[id]
	if !ok {
		return
	}
	if w := b.widgets[id]; w != nil {
		w.submenuOpen = false
		w.popupDismissed = false
	}
	for _, child := range n.Children {
		b.resetWidgetMenu(child)
	}
}

func (b *Backend) widgetHasSubmenu(n Node) bool {
	for _, id := range n.Children {
		if b.nodes[id].Kind == "dropdown-menu" {
			return true
		}
	}
	return false
}

func (b *Backend) widgetSubmenuOpen(n Node) bool {
	for _, id := range n.Children {
		child := b.nodes[id]
		if b.widgetHasSubmenu(child) && b.widget(child).submenuOpen || b.widgetSubmenuOpen(child) {
			return true
		}
	}
	return false
}

func (b *Backend) widgetSubmenuTrigger(_ *ui.Context, n Node, e ui.Element) {
	w := b.widget(n)
	open := func() {
		if n.Props["enabled"] == false || n.Bool("inert") || w.submenuOpen {
			return
		}
		for _, child := range n.Children {
			b.resetWidgetMenu(child)
		}
		w.submenuOpen = true
	}
	e.OnClick(func() {
		if w.submenuOpen {
			w.submenuOpen = false
		} else {
			open()
		}
	})
	e.OnShortcut(0, ui.KeyRight, open)
	if parent := b.nodes[n.Parent]; parent.Kind != "dropdown-menu" && parent.Kind != "context-menu" {
		e.OnShortcut(0, ui.KeyDown, open)
	}
}
