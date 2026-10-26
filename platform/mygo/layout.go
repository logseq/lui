package luimygo

import (
	"fmt"
	"github.com/egoist/mygo/ui"
	"time"
)

type layoutState struct {
	outer             ui.Handle
	source            float64
	sourceSet, pixels bool
	current           float32
	animationStarted  bool
	acknowledged      bool
}

// acknowledge reconciles direct resize proposals after the reducer returns,
// including unchanged wire values and normalized pixel-mode values.
func (s *layoutState) acknowledge(n Node) {
	value := n.Number("value", .5)
	if pixels, ok := number(n.Props["first-pane-width"]); ok {
		value = pixels
	}
	s.current = float32(value)
	s.acknowledged = true
}

func layoutAnchor(name string) ui.Anchor {
	switch name {
	case "top-leading":
		return ui.AnchorTopStart
	case "top":
		return ui.AnchorTop
	case "top-trailing":
		return ui.AnchorTopEnd
	case "leading":
		return ui.AnchorStart
	case "trailing":
		return ui.AnchorEnd
	case "bottom-leading":
		return ui.AnchorBottomStart
	case "bottom":
		return ui.AnchorBottom
	case "bottom-trailing":
		return ui.AnchorBottomEnd
	default:
		return ui.AnchorCenter
	}
}

func (b *Backend) renderLayout(c *ui.Context, n Node, s *controlState, appearances *[]Event) (ui.Element, bool) {
	child := func(id int64) { b.render(c, id, appearances) }
	switch n.Kind {
	case "stack":
		e := ui.Grid(c).ColumnTracks(ui.FitContent()).RowTracks(ui.FitContent())
		e.Children(func() {
			for _, id := range n.Children {
				c.Key(fmt.Sprintf("stack:%d", id))
				ui.Box(c).PassThrough().ColumnStart(1).RowStart(1).ZIndex(int(b.nodes[id].Number("z-index", 0))).Children(func() { child(id) })
			}
		})
		return e, true
	case "overlay":
		e := ui.Column(c)
		e.Children(func() {
			for i, id := range n.Children {
				c.Key(fmt.Sprintf("overlay:%d", id))
				wrapper := ui.Box(c).PassThrough().ZIndex(int(b.nodes[id].Number("z-index", 0)))
				if i > 0 {
					alignment := b.nodes[id].String("alignment")
					if alignment == "" {
						alignment = n.String("alignment")
					}
					anchor := layoutAnchor(alignment)
					wrapper.Absolute().Attach(anchor, anchor)
				}
				wrapper.Children(func() { child(id) })
			}
		})
		return e, true
	case "edge-inset":
		side := n.String("edge") == "leading" || n.String("edge") == "trailing"
		e := ui.Column(c).AlignItems(ui.Stretch)
		if side {
			e.Row()
		}
		pinned := func() {
			if n.Props["visible"] == false || len(n.Children) < 2 {
				return
			}
			c.Key("pinned")
			region := ui.Column(c).Shrink(0).Gap(0)
			if side {
				region.Row().FillHeight()
			} else {
				region.FillWidth()
			}

			region.Children(func() {
				for _, id := range n.Children[1:] {
					child(id)
				}
			})
			surface := n.clone()
			surface.Kind = "box"
			for name := range surface.Props {
				if !pinnedSurfaceProperty(name) && name != "selected" {
					delete(surface.Props, name)
				}
			}
			b.style(c, surface, region)
		}
		content := func() {
			if len(n.Children) > 0 {
				c.Key("content")
				ui.Box(c).Grow(1).MinWidth(0).MinHeight(0).Children(func() { child(n.Children[0]) })
			}
		}
		e.Children(func() {
			if n.String("edge") == "top" || n.String("edge") == "leading" {
				pinned()
				content()
			} else {
				content()
				pinned()
			}
		})
		return e, true
	case "view-that-fits":
		probes := make([]func(*ui.Context), len(n.Children))
		for index, id := range n.Children {
			probes[index] = func(probe *ui.Context) {
				previous := b.probing
				previousStates, previousWidgets := b.states, b.widgets
				previousProbes := b.resources.probeStates
				b.resources.probeStates = previousStates
				b.states, b.widgets = map[int64]*controlState{}, map[int64]*widgetState{}
				b.probing = true
				defer func() {
					b.probing = previous
					b.states, b.widgets = previousStates, previousWidgets
					b.resources.probeStates = previousProbes
				}()
				var discarded []Event
				b.render(probe, id, &discarded)
			}
		}
		e := c.Fitting(n.String("orientation") == "vertical", probes, func(actual *ui.Context, index int) { b.render(actual, n.Children[index], appearances) })
		return e, true
	case "resizable":
		e := ui.Column(c)
		e.Children(func() {
			for _, id := range n.Children {
				child(id)
			}
		})
		return e, true
	case "split":
		return b.renderSplit(c, n, s, appearances), true
	default:
		return ui.Element{}, false
	}
}

func (b *Backend) renderSplit(c *ui.Context, n Node, s *controlState, appearances *[]Event) ui.Element {
	state := &s.layout
	value, pixels := n.Number("value", .5), false
	if number, ok := number(n.Props["first-pane-width"]); ok {
		value, pixels = number, true
	}
	if !state.sourceSet || state.source != value || state.pixels != pixels {
		state.current = float32(value)
		state.source = value
		state.pixels = pixels
		state.sourceSet = true
	}
	gap := float32(n.Number("gap", 9))
	e := ui.Grid(c).Bind(&state.outer).MinWidth(0)
	const motionKey = "lui-split-resize"
	if state.acknowledged {
		e.Jump(motionKey, state.current)
		state.acknowledged = false
	}
	duration := time.Duration(n.Number("resize-duration", 0)) * time.Millisecond
	shown := state.current
	if duration > 0 {
		if !state.animationStarted {
			if origin, ok := number(n.Props["resize-origin"]); ok {
				e.Jump(motionKey, float32(origin))
			}
		}
		animation := ui.Animation{Duration: duration, Ease: ui.EaseInOut}
		switch n.String("resize-easing") {
		case "linear":
			animation.Ease = ui.Linear
		case "emphasized":
			animation.Ease = ui.EaseOut
		case "spring":
			animation = ui.Animation{Spring: ui.SpringOptions{Duration: duration, Bounce: .15}}
		}
		shown = e.AnimateTo(motionKey, state.current, animation)
	} else {
		e.Jump(motionKey, state.current)
	}
	state.animationStarted = true
	first, second := ui.Fr(max(0, min(1, shown))), ui.Fr(max(0, 1-min(1, shown)))
	if pixels {
		first, second = ui.Fixed(max(0, shown)), ui.Fr(1)
	}
	e.ColumnTracks(first, ui.Fixed(gap), second).RowTracks(ui.Fr(1))
	update := func(delta float32) {
		bounds := state.outer.Bounds(c)
		available := max(0, bounds.W-gap)
		if available <= 0 {
			return
		}
		next := state.current
		if pixels {
			next += delta
		} else {
			next += delta / available
		}
		minimum, maximum := float32(0), available
		if len(n.Children) > 0 {
			minimum = float32(b.nodes[n.Children[0]].Number("min-width", 0))
		}
		if len(n.Children) > 1 {
			maximum -= float32(b.nodes[n.Children[1]].Number("min-width", 0))
		}
		if pixels {
			next = max(minimum, min(maximum, next))
		} else {
			next = max(minimum/available, min(maximum/available, next))
		}
		if next != state.current {
			state.current = next
			e.Jump(motionKey, next)
			if n.Bool("change-enabled") {
				b.emit(Event{Kind: "value-changed", Node: n.ID, Value: float64(next)})
			}
			c.Invalidate()
		}
	}
	e.Children(func() {
		if len(n.Children) > 0 {
			c.Key("first")
			ui.Grid(c).Columns(1).RowTracks(ui.Fr(1)).ColumnStart(1).RowStart(1).MinWidth(0).Clip().Children(func() { b.render(c, n.Children[0], appearances) })
		}
		c.Key("divider")
		divider := ui.Box(c).ColumnStart(2).RowStart(1).Background(c.Theme().Border)
		handleWidth := float32(n.Number("resize-handle-width", float64(max(gap, 3))))
		if handleWidth > 0 {
			c.Key("resize-handle")
			handle := ui.Box(c).Absolute().AttachTo(divider, ui.AnchorCenter, ui.AnchorCenter).Left(float32(n.Number("resize-handle-offset", 0))).Width(handleWidth).FillHeight().Focusable().Role(ui.RoleSplitter).Label("Resize panes").Cursor(ui.CursorResizeEW)
			if dx, _, held := handle.Dragged(); held {
				update(dx)
				handle.Focus()
			}
			if handle.Shortcut(0, ui.KeyLeft) {
				update(-10)
			}
			if handle.Shortcut(0, ui.KeyRight) {
				update(10)
			}
		}
		if len(n.Children) > 1 {
			c.Key("second")
			ui.Grid(c).Columns(1).RowTracks(ui.Fr(1)).ColumnStart(3).RowStart(1).MinWidth(0).Clip().Children(func() { b.render(c, n.Children[1], appearances) })
		}
	})
	return e
}
