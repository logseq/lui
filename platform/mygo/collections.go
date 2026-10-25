package luimygo

import (
	"encoding/json"
	"github.com/egoist/mygo/ui"
	"math"
	"slices"
	"strconv"
	"strings"
)

type collectionState struct {
	list                        ui.ListState
	viewport                    ui.Handle
	rows                        map[int64]*ui.Handle
	token                       int64
	tokenSet, pending, animated bool
	target                      string
	anchor                      string
	targetIndex                 int
	first, last                 int
	rangeSet, edgesSet          bool
	atStart, atEnd              bool
	issued                      bool
	tableColumns                int
	windowSet                   bool
	windowGeneration            int64
	windowFirst, windowLast     int
	windowPins                  []int64
}

// sparseCollection describes committed row roots; source data and unmounted
// rows remain in the application. Missing rows receive only host geometry.
type sparseCollection struct {
	lazy       bool
	total      int
	generation int64
	rows       map[int]int64
	indices    map[int64]int
}

func collectionSource(n Node) sparseCollection {
	generation, lazy := integer(n.Props["virtual-generation"])
	result := sparseCollection{lazy: lazy, total: len(n.Children), generation: generation}
	if !lazy {
		return result
	}
	count, _ := integer(n.Props["virtual-total-count"])
	result.total = int(count)
	var indices []int
	_ = json.Unmarshal([]byte(n.String("virtual-indices")), &indices)
	result.rows = make(map[int]int64, len(indices))
	result.indices = make(map[int64]int, len(indices))
	for position, index := range indices {
		if position < len(n.Children) {
			result.rows[index] = n.Children[position]
			result.indices[n.Children[position]] = index
		}
	}
	return result
}
func (source sparseCollection) row(n Node, index int) int64 {
	if source.lazy {
		return source.rows[index]
	}
	if index < 0 || index >= len(n.Children) {
		return 0
	}
	return n.Children[index]
}

// Placeholder keys cannot collide with mounted wire node IDs.
type collectionPlaceholderIndex int

// Measure shared tracks once before building rows. Row construction reads the
// retained result instead of rescanning its siblings.
func collectionTableColumns(rows []int64, row func(int64) Node) int {
	columns := 1
	for _, id := range rows {
		columns = max(columns, len(row(id).Children))
	}
	return columns
}

func collectionTuning(n Node) (int, float32) {
	overscan, extent := 5, float32(32)
	for _, record := range strings.Split(n.String("data-attrs"), "\x1e") {
		name, value, ok := strings.Cut(record, "\x1f")
		if !ok {
			continue
		}
		switch name {
		case "data-overscan":
			if parsed, err := strconv.Atoi(value); err == nil && parsed >= 0 {
				overscan = parsed
			}
		case "data-item-extent":
			if parsed, err := strconv.ParseFloat(value, 32); err == nil && parsed > 0 && !math.IsInf(parsed, 0) {
				extent = float32(parsed)
			}
		}
	}
	if value, ok := number(n.Props["overscan"]); ok {
		overscan = int(value)
	}
	if value, ok := number(n.Props["item-extent"]); ok {
		extent = float32(value)
	}
	return overscan, extent
}

func (b *Backend) renderCollections(c *ui.Context, n Node, s *controlState, appearances *[]Event) (ui.Element, bool) {
	switch n.Kind {
	case "table-cell":
		if len(n.Children) == 0 {
			return ui.Element{}, false
		}
		e := ui.Column(c)
		e.Children(func() {
			if text := n.String("text"); text != "" {
				ui.Text(c, text)
			}
			for _, id := range n.Children {
				b.render(c, id, appearances)
			}
		})
		return e, true
	case "table":
		e := ui.Column(c).FillWidth()
		e.Children(func() {
			for _, id := range n.Children {
				b.render(c, id, appearances)
			}
		})
		return e, true
	case "table-row":
		parent := b.nodes[n.Parent]
		if parent.Kind != "table" {
			return ui.Element{}, false
		}
		columns := b.state(parent).collection.tableColumns
		e := ui.Grid(c).Columns(columns).FillWidth()
		if n.Bool("selected") {
			e.Background(c.Theme().Accent)
		}
		e.Children(func() {
			for _, id := range n.Children {
				b.render(c, id, appearances)
			}
		})
		return e, true
	case "list", "virtual-list", "scroll":
	default:
		return ui.Element{}, false
	}
	state := &s.collection
	source := collectionSource(n)
	if state.rows == nil {
		state.rows = map[int64]*ui.Handle{}
	}
	for id := range state.rows {
		if child, ok := b.nodes[id]; !ok || child.Parent != n.ID {
			delete(state.rows, id)
		}
	}
	targetToken, hasToken := integer(n.Props["scroll-token"])
	if hasToken && (!state.tokenSet || state.token != targetToken) {
		s.scroll.Stop()
		if state.pending {
			if n.Bool("pointer-enabled") {
				b.emit(Event{Kind: "scroll-completed", Node: n.ID, Token: state.token, Outcome: "cancelled"})
			}
		}
		state.token, state.tokenSet, state.pending = targetToken, true, true
		state.target, state.anchor, state.animated = n.String("scroll-target"), n.String("scroll-anchor"), n.Bool("scroll-animated")
		state.targetIndex = -1
		state.issued = false
		for index, id := range n.Children {
			if b.nodes[id].String("key") == state.target {
				state.targetIndex = index
				break
			}
		}
	}
	if source.lazy && state.pending {
		state.targetIndex = int(n.Number("virtual-scroll-index", -1))
	}
	overscan, extent := collectionTuning(n)
	row := func(index int) {
		id := source.row(n, index)
		if id == 0 {
			ui.Box(c).Height(extent).Shrink(0).FillWidth()
			return
		}
		handle := state.rows[id]
		if handle == nil {
			handle = &ui.Handle{}
			state.rows[id] = handle
		}
		c.Key(id)
		wrapper := ui.Column(c).FillWidth().MinWidth(0).Bind(handle)
		grouped := n.String("style") == "inset-grouped"
		if grouped {
			wrapper.Background(c.Theme().Surface).Radius(8)
		}
		wrapper.Children(func() {
			marker := n.String("list-style")
			if explicit, ok := b.nodes[id].Props["list-style"].(string); ok {
				marker = explicit
			}
			if b.nodes[id].Kind == "list-item" && (marker == "disc" || marker == "decimal") {
				ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(8).Children(func() {
					text := "•"
					if marker == "decimal" {
						text = strconv.Itoa(index+1) + "."
					}
					ui.Text(c, text).MinWidth(20).TextAlign(ui.End)
					ui.Box(c).Grow(1).MinWidth(0).Children(func() { b.render(c, id, appearances) })
				})
			} else {
				b.render(c, id, appearances)
			}
			if b.nodes[id].String("separator") == "visible" {
				ui.Box(c).FillWidth().Height(1).Shrink(0).Background(c.Theme().Border)
			}
		})
	}
	virtual := n.Kind == "virtual-list"
	var e ui.Element
	if virtual {
		state.list.Key = func(index int) any {
			if id := source.row(n, index); id != 0 {
				return id
			}
			return collectionPlaceholderIndex(index)
		}
		if source.lazy {
			state.list.SetKeyIndex(func(key any) (int, bool) {
				id, ok := key.(int64)
				if !ok {
					return 0, false
				}
				index, found := source.indices[id]
				return index, found
			})
		} else {
			state.list.SetKeyIndex(nil)
		}
		state.list.SetOverscan(overscan)
		state.list.SetItemExtent(extent)
		if state.pending && state.targetIndex >= 0 && !state.issued {
			if state.animated {
				viewport := state.viewport.Bounds(c)
				height := viewport.H
				if height <= 0 {
					height = float32(n.Number("height", 0))
				}
				offset := float32(state.targetIndex) * (extent + float32(n.Number("gap", 0)))
				if state.anchor == "center" {
					offset -= (height - extent) / 2
				} else if state.anchor == "bottom" {
					offset -= height - extent
				}
				s.scroll.ScrollTo(0, max(0, offset), ui.Smooth)
			} else {
				align := ui.Start
				switch state.anchor {
				case "center":
					align = ui.Center
				case "bottom":
					align = ui.End
				}
				if state.anchor == "nearest" {
					state.list.ScrollIntoView(state.targetIndex)
				} else {
					state.list.ScrollTo(state.targetIndex, align)
				}
			}
			state.issued = true
		}
		e = ui.List(c, &state.list, source.total, row).FillWidth().TrackScroll(&s.scroll).Bind(&state.viewport)
		// Reading subscribes the builder to committed range changes.
		state.list.Visible()
		if source.lazy {
			state.list.Requested()
		}
	} else {
		if n.String("orientation") == "horizontal" {
			e = ui.ScrollHorizontal(c)
		} else {
			e = ui.Scroll(c)
		}
		e.TrackScroll(&s.scroll).Bind(&state.viewport).FillWidth()
		e.Children(func() {
			for index := range n.Children {
				row(index)
			}
		})
	}
	if appearance := n.String("style"); appearance == "inset" || appearance == "inset-grouped" {
		e.Padding(12)
	}
	if !b.probing {
		identity := s.identity
		c.AfterFrame(func() {
			if b.states[n.ID] != s || s.identity != identity {
				return
			}
			current, ok := b.nodes[n.ID]
			if !ok {
				return
			}
			if source.lazy {
				currentGeneration, _ := integer(current.Props["virtual-generation"])
				if currentGeneration != source.generation {
					c.Invalidate()
					return
				}
				requestedFirst, requestedLast, pinnedIndices := state.list.Requested()
				pins := make([]int64, 0, len(pinnedIndices))
				for _, index := range pinnedIndices {
					if id := source.row(n, index); id != 0 {
						pins = append(pins, id)
					}
				}
				slices.Sort(pins)
				if !state.windowSet || state.windowGeneration != source.generation || state.windowFirst != requestedFirst || state.windowLast != requestedLast || !slices.Equal(pins, state.windowPins) {
					state.windowSet, state.windowGeneration, state.windowFirst, state.windowLast, state.windowPins = true, source.generation, requestedFirst, requestedLast, slices.Clone(pins)
					b.emit(Event{Kind: "virtual-window", Node: n.ID, Generation: source.generation, First: int64(requestedFirst), Last: int64(requestedLast), Pins: pins})
					c.Invalidate()
				}
			}
			viewport := state.viewport.Bounds(c)
			first, last := 0, -1
			if virtual {
				first, last = state.list.Visible()
			} else {
				for index, id := range current.Children {
					if handle := state.rows[id]; handle != nil {
						bounds := handle.Bounds(c)
						if bounds.H > 0 && bounds.Y < viewport.Y+viewport.H-.01 && bounds.Y+bounds.H > viewport.Y+.01 {
							if last < first {
								first = index
							}
							last = index
						}
					}
				}
			}
			if current.Bool("pointer-enabled") && current.Bool("track-visible-range") && (!state.rangeSet || state.first != first || state.last != last) {
				state.rangeSet, state.first, state.last = true, first, last
				b.emit(Event{Kind: "visible-range", Node: n.ID, First: int64(first), Last: int64(last)})
			}
			atStart, atEnd := s.scroll.Y <= .5, s.scroll.Y >= s.scroll.MaxY-.5
			if !state.edgesSet || state.atStart != atStart || state.atEnd != atEnd {
				state.edgesSet, state.atStart, state.atEnd = true, atStart, atEnd
				if current.Bool("pointer-enabled") {
					b.emit(Event{Kind: "scroll-edges", Node: n.ID, AtStart: atStart, AtEnd: atEnd})
				}
			}
			if !state.pending {
				return
			}
			complete := func(outcome string) {
				state.pending = false
				if current.Bool("pointer-enabled") {
					b.emit(Event{Kind: "scroll-completed", Node: n.ID, Token: state.token, Outcome: outcome})
				}
			}
			index := -1
			for i, id := range current.Children {
				if b.nodes[id].String("key") == state.target {
					index = i
					break
				}
			}
			if source.lazy {
				index = int(current.Number("virtual-scroll-index", -1))
			}
			if index < 0 {
				complete("missing-target")
				return
			}
			if !virtual && !state.issued {
				handle := state.rows[current.Children[index]]
				if handle == nil {
					return
				}
				rect := handle.Bounds(c)
				offset := s.scroll.Y + rect.Y - viewport.Y
				switch state.anchor {
				case "center":
					offset -= (viewport.H - rect.H) / 2
				case "bottom":
					offset -= viewport.H - rect.H
				case "nearest":
					if rect.Y >= viewport.Y && rect.Y+rect.H <= viewport.Y+viewport.H {
						offset = s.scroll.Y
					} else if rect.Y+rect.H > viewport.Y+viewport.H {
						offset -= viewport.H - rect.H
					}
				}
				offset = max(0, min(s.scroll.MaxY, offset))
				if state.animated {
					s.scroll.ScrollTo(0, offset, ui.Smooth)
				} else {
					s.scroll.Y = offset
				}
				state.issued = true
				c.Invalidate()
				return
			}
			if s.scroll.Scrolling() {
				return
			}
			if index >= first && index <= last && source.row(n, index) != 0 {
				complete("succeeded")
			}
		})
	}
	return e, true
}
