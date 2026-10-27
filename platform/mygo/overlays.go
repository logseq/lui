package luimygo

import (
	"fmt"
	"math"
	"strconv"
	"strings"

	"github.com/egoist/mygo/ui"
)

func (b *Backend) renderOverlays(c *ui.Context, n Node, children func(), emit func(Event)) (ui.Element, bool) {
	switch n.Kind {
	case "popover":
		if b.probing {
			return ui.Element{}, true
		}
		anchor, handle, owner, ok := b.popoverAnchor(c, n)
		if !ok {
			return ui.Element{}, true
		}
		w := b.widget(n)
		open := true
		panel := ui.PopoverBase(c, anchor, &open, func(panel ui.Element) {
			panel.Bind(&b.recordMenuOwner(n, owner, false, false).panel)
			panel.Column().Padding(12).Gap(8).Radius(c.Theme().Radius).Background(c.Theme().Surface).Border(1, c.Theme().Border)
			width, height := c.Size()
			padding := float32(n.Number("collision-padding", 8))
			panel.ScrollAxes(false, true).MaxWidth(max(0, width-2*padding)).MaxHeight(max(0, height-2*padding))
			b.placeWidgetPopup(n, panel, anchor)
			if handle != nil {
				at, self := widgetPopupAnchors(n)
				panel.AttachToHandle(handle, at, self)
			}
			panel.CollisionPadding(float32(n.Number("collision-padding", 8)))
			if n.String("role") == "menu" {
				panel.Role(ui.RoleMenu).FocusGroup(ui.Vertical)
			} else if n.String("role") == "dialog" {
				panel.Role(ui.RoleDialog)
			}
			if n.String("anchor-alignment") == "stretch" {
				panel.MatchAnchorWidth()
			}
			if offset := float32(n.Number("anchor-alignment-offset", 0)); offset != 0 {
				if n.String("anchor") == "left" || n.String("anchor") == "right" {
					panel.Top(offset)
				} else {
					panel.Left(offset)
				}
			}
			if _, present := n.Props["available-height"]; present {
				panel.MaxHeight(min(max(0, height-2*padding), float32(n.Number("available-height", 0)))).ClipY()
			}
			panel.Children(children)
		})
		if panel.Dismissed() && !w.popupDismissed {
			w.popupDismissed = true
			emit(Event{Kind: "dismiss"})
		}
		return panel, true
	case "dialog":
		if b.probing {
			return ui.Element{}, true
		}
		w := b.widget(n)
		open := true
		panel := ui.Modal(c, &open, func() {
			if title := n.String("text"); title != "" {
				ui.Text(c, title).Bold()
			}
			if description := n.String("description"); description != "" {
				ui.Text(c, description)
			}
			children()
		}).Column().ScrollAxes(false, true)
		if panel.Dismissed() && !w.popupDismissed {
			w.popupDismissed = true
			emit(Event{Kind: "dismiss"})
		}
		return panel, true
	case "sheet":
		if b.probing {
			return ui.Element{}, true
		}
		w := b.widget(n)
		open := true
		width, height := c.Size()
		panel := ui.DialogBase(c, &open, func(back, panel ui.Element) {
			back.Justify(ui.End).AlignItems(ui.Center).Background(ui.RGBA(0, 0, 0, 0.35))
			panel.Column().ScrollAxes(false, true).Padding(20).Gap(12).Radius(c.Theme().Radius).Background(c.Theme().Surface).Width(min(width, 560)).MaxWidth(width).MaxHeight(height)
			if n.String("sizing") == "page" {
				panel.Width(width).Height(height)
			} else if n.String("sizing") != "fitted" {
				panel.Height(height * sheetDetent(n.String("detents")))
			}
			panel.Children(func() {
				ui.Text(c, n.String("text")).Bold()
				children()
			})
		})
		if panel.Dismissed() && !w.popupDismissed {
			w.popupDismissed = true
			emit(Event{Kind: "dismiss"})
		}
		return panel, true
	case "drawer":
		e := ui.Row(c).FillWidth().AlignItems(ui.Stretch)
		e.Children(func() {
			if n.Bool("selected") && len(n.Children) > 1 {
				c.Key("drawer-sidebar")
				ui.Column(c).Width(280).Shrink(0).Background(c.Theme().Surface).Role(ui.RoleGroup).Label(n.String("text")).Children(func() { b.renderWidgetChild(c, n.Children[1]) })
			}
			if len(n.Children) > 0 {
				c.Key("drawer-main")
				ui.Column(c).Grow(1).Children(func() { b.renderWidgetChild(c, n.Children[0]) })
			}
		})
		if n.Bool("selected") && n.Bool("toggle-enabled") {
			e.OnShortcut(0, ui.KeyEscape, func() { emit(Event{Kind: "toggle-changed", Checked: false}) })
		}
		return e, true
	}
	return ui.Element{}, false
}
func sheetDetent(value string) float32 {
	detent := float32(1)
	for _, token := range strings.Split(value, ",") {
		token = strings.TrimSpace(token)
		fraction := float64(0)
		switch token {
		case "medium":
			fraction = 0.5
		case "large":
			fraction = 1
		default:
			fraction, _ = strconv.ParseFloat(token, 64)
		}
		if fraction > 0 && fraction <= 1 && !math.IsNaN(fraction) {
			detent = min(detent, float32(fraction))
		}
	}
	return detent
}

// Forward references attach through stable handles. The toolkit resolves the
// actual target after construction, before geometry and focus are committed.
func (b *Backend) popoverAnchor(c *ui.Context, n Node) (ui.Element, *ui.Handle, Node, bool) {
	var bounds ui.Rect
	if rectangle := n.String("anchor-rect"); rectangle != "" {
		if _, err := fmt.Sscanf(rectangle, "%f %f %f %f", &bounds.X, &bounds.Y, &bounds.W, &bounds.H); err != nil {
			return ui.Element{}, nil, Node{}, false
		}
	} else if _, point := n.Props["x"]; point {
		bounds.X, bounds.Y = float32(n.Number("x", 0)), float32(n.Number("y", 0))
	} else if identifier := n.String("anchor-target"); identifier != "" {
		for _, target := range b.nodes {
			if target.String("accessibility-identifier") != identifier {
				continue
			}
			if target.String("display") == "none" {
				return ui.Element{}, nil, Node{}, false
			}
			handle := &b.state(target).handle
			return c.Resolve(*handle), handle, target, true
		}
		return ui.Element{}, nil, Node{}, false
	} else {
		anchor := b.menuAnchor(c, n)
		return anchor, nil, b.menuAnchorNode(n), anchor.Valid()
	}
	var proxy ui.Element
	ui.Overlay(c, func() {
		c.Key("popover-anchor-" + strconv.FormatInt(n.ID, 10))
		proxy = ui.Box(c).Absolute().PassThrough().Role(ui.RoleNone).Left(bounds.X).Top(bounds.Y).Size(bounds.W, bounds.H)
	})
	return proxy, nil, n, true
}
