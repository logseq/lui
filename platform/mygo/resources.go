package luimygo

import (
	"bytes"
	"context"
	"embed"
	"encoding/base64"
	"fmt"
	"image"
	"image/draw"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"net/url"
	"os"
	"reflect"
	"strings"
	"sync"
	"time"

	"github.com/egoist/mygo/ui"
	xdraw "golang.org/x/image/draw"
)

//go:embed icons/*.svg
var builtInIcons embed.FS

const maxResourceBytes = 32 << 20
const maxResourcePixels = 32 << 20

var imageWorkers = make(chan struct{}, 8)

type resourceAsset struct {
	pixels *image.RGBA
	bitmap *ui.Bitmap
}
type nodeResourceState struct {
	maxPixel int
	source   string
	epoch    uint64
	asset    *resourceAsset
	cancel   context.CancelFunc
}
type resourceResult struct {
	node            int64
	identity, epoch uint64
	pixels          image.Image
	err             error
}
type resourceStore struct {
	closed           bool
	probeStates      map[int64]*controlState
	images, surfaces map[int64]*resourceAsset
	icons            map[string]*ui.SVG
	jobs             map[int64]*controlState
	mu               sync.Mutex
	results          map[int64]resourceResult
	services         ui.Services
}

func (r *resourceStore) init() {
	if r.jobs == nil {
		r.jobs = map[int64]*controlState{}
	}
	if r.images == nil {
		r.images = map[int64]*resourceAsset{}
		r.surfaces = map[int64]*resourceAsset{}
		r.icons = map[string]*ui.SVG{}
		r.jobs = map[int64]*controlState{}
	}
}
func copyResource(pixels image.Image) (*resourceAsset, error) {
	if pixels == nil || reflect.ValueOf(pixels).Kind() == reflect.Pointer && reflect.ValueOf(pixels).IsNil() {
		return nil, fmt.Errorf("lui: image pixels must not be nil")
	}
	bounds := pixels.Bounds()
	if bounds.Dx() <= 0 || bounds.Dy() <= 0 || bounds.Dx() > maxResourcePixels/bounds.Dy() {
		return nil, fmt.Errorf("lui: invalid or oversized image dimensions")
	}
	owned := image.NewRGBA(image.Rect(0, 0, bounds.Dx(), bounds.Dy()))
	draw.Draw(owned, owned.Bounds(), pixels, bounds.Min, draw.Src)
	return &resourceAsset{pixels: owned, bitmap: ui.NewBitmap(owned)}, nil
}

// RegisterImage copies pixels into a host-owned resource. Call it on the UI
// goroutine; retained nodes reference the resource independently of their lives.
func (b *Backend) RegisterImage(id int64, pixels image.Image) error {
	if b.resources.closed {
		return fmt.Errorf("lui: backend resources are closed")
	}
	if id <= 0 {
		return fmt.Errorf("lui: image id must be positive")
	}
	asset, err := copyResource(pixels)
	if err != nil {
		return err
	}
	b.resources.init()
	b.resources.images[id] = asset
	b.resources.services.Invalidate()
	return nil
}
func (b *Backend) UnregisterImage(id int64) {
	b.resources.init()
	delete(b.resources.images, id)
	b.resources.services.Invalidate()
}

// NaturalImageSize reports cached decoded pixel dimensions for a retained image,
// file-image or avatar. Call on the UI goroutine. It does not start decoding or
// use layout, crop dimensions, avatar fallbacks or assets from retired nodes.
func (b *Backend) NaturalImageSize(id int64) (width, height float32, ready bool) {
	if b.closed || b.resources.closed || b.probing {
		return 0, 0, false
	}
	n, exists := b.nodes[id]
	if !exists {
		return 0, 0, false
	}
	var asset *resourceAsset
	var source string
	switch n.Kind {
	case "image", "avatar":
		source = n.String("url")
		if source == "" {
			asset = b.resources.images[int64(n.Number("image", 0))]
		}
	case "file-image":
		source = n.String("path")
	default:
		return 0, 0, false
	}
	if source != "" {
		state := b.states[id]
		if state == nil || state.resource.source != source || state.resource.maxPixel != int(n.Number("max-pixel-size", 0)) {
			return 0, 0, false
		}
		asset = state.resource.asset
	}
	if asset == nil || asset.pixels == nil {
		return 0, 0, false
	}
	bounds := asset.pixels.Bounds()
	return float32(bounds.Dx()), float32(bounds.Dy()), true
}

// PresentMediaSurfaceFrame copies an immutable frame into the named surface.
// Replacement keeps the existing toolkit texture allocation where possible.
func (b *Backend) PresentMediaSurfaceFrame(id int64, pixels image.Image) error {
	if b.resources.closed {
		return fmt.Errorf("lui: backend resources are closed")
	}
	if id <= 0 {
		return fmt.Errorf("lui: media surface id must be positive")
	}
	asset, err := copyResource(pixels)
	if err != nil {
		return err
	}
	b.resources.init()
	if previous := b.resources.surfaces[id]; previous != nil {
		previous.bitmap.Update(asset.pixels)
		previous.pixels = asset.pixels
	} else {
		b.resources.surfaces[id] = asset
	}
	b.resources.services.Invalidate()
	return nil
}
func (b *Backend) UnregisterMediaSurface(id int64) {
	b.resources.init()
	delete(b.resources.surfaces, id)
	b.resources.services.Invalidate()
}

func (b *Backend) prepareResources(c *ui.Context) {
	store := &b.resources
	if store.closed {
		return
	}
	store.init()
	store.services = c.Services()
	for id, state := range store.jobs {
		if b.states[id] != state {
			if state.resource.cancel != nil {
				state.resource.cancel()
			}
			delete(store.jobs, id)
		}
	}
	store.mu.Lock()
	results := store.results
	store.results = nil
	store.mu.Unlock()
	for _, result := range results {
		state := b.states[result.node]
		if state == nil || state.identity != result.identity || state.resource.epoch != result.epoch {
			continue
		}
		delete(store.jobs, result.node)
		state.resource.cancel = nil
		current, exists := b.nodes[result.node]
		currentSource := current.String("url")
		if current.Kind == "file-image" {
			currentSource = current.String("path")
		}
		if !exists || currentSource != state.resource.source || int(current.Number("max-pixel-size", 0)) != state.resource.maxPixel {
			continue
		}
		if result.err != nil {
			continue
		}
		asset, err := copyResource(result.pixels)
		if err != nil {
			continue
		}
		state.resource.asset = asset
		if n, ok := b.nodes[result.node]; ok && n.Kind == "image" {
			b.emit(Event{Kind: "load", Node: result.node})
		}
	}
}

func (b *Backend) loadResource(c *ui.Context, n Node, s *controlState, source string) *resourceAsset {
	state := &s.resource
	maxPixel := int(n.Number("max-pixel-size", 0))
	if b.probing {
		if previous := b.resources.probeStates[n.ID]; previous != nil && previous.resource.source == source && previous.resource.maxPixel == maxPixel {
			return previous.resource.asset
		}
		return nil
	}
	if b.resources.closed {
		return nil
	}
	if source == state.source && state.maxPixel == maxPixel {
		return state.asset
	}
	if state.cancel != nil {
		state.cancel()
	}
	state.source, state.asset, state.maxPixel = source, nil, maxPixel
	state.epoch++
	if source == "" || b.probing {
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	state.cancel = cancel
	b.resources.jobs[n.ID] = s
	epoch, identity, node := state.epoch, s.identity, n.ID
	store, services := &b.resources, c.Services()
	go func() {
		defer cancel()
		select {
		case imageWorkers <- struct{}{}:
		case <-ctx.Done():
			return
		}
		defer func() { <-imageWorkers }()
		pixels, err := decodeResource(ctx, source, maxPixel)
		if ctx.Err() != nil {
			return
		}
		store.mu.Lock()
		if ctx.Err() != nil {
			store.mu.Unlock()
			return
		}
		if store.results == nil {
			store.results = map[int64]resourceResult{}
		}
		store.results[node] = resourceResult{node: node, identity: identity, epoch: epoch, pixels: pixels, err: err}
		store.mu.Unlock()
		services.Invalidate()
	}()
	return nil
}

// lazyResource starts work only after the image intersects every committed
// clipping ancestor. Measuring an unselected fitting candidate never publishes.
func (b *Backend) lazyResource(c *ui.Context, n Node, s *controlState, source string) *resourceAsset {
	if b.probing {
		return b.loadResource(c, n, s, source)
	}
	if s.resource.source == source && s.resource.maxPixel == int(n.Number("max-pixel-size", 0)) {
		return s.resource.asset
	}
	if s.resource.source != "" {
		b.loadResource(c, n, s, "")
	}
	width, height := c.Size()
	c.AfterFrame(func() {
		if b.resources.closed || b.states[n.ID] != s {
			return
		}
		current, ok := b.nodes[n.ID]
		if !ok || current.String("url") != source {
			return
		}
		rect := s.handle.Bounds(c)
		intersect := func(clip ui.Rect) {
			left, top := max(rect.X, clip.X), max(rect.Y, clip.Y)
			right, bottom := min(rect.X+rect.W, clip.X+clip.W), min(rect.Y+rect.H, clip.Y+clip.H)
			rect = ui.Rect{X: left, Y: top, W: max(0, right-left), H: max(0, bottom-top)}
		}
		intersect(ui.Rect{W: width, H: height})
		for parent := current.Parent; parent != 0; {
			ancestor, exists := b.nodes[parent]
			if !exists {
				break
			}
			clipped := ancestor.Kind == "scroll" || ancestor.Kind == "list" || ancestor.Kind == "virtual-list" || ancestor.String("overflow") == "hidden" || ancestor.String("overflow") == "auto"
			if clipped {
				if state := b.states[parent]; state != nil {
					intersect(state.handle.Bounds(c))
				}
			}
			parent = ancestor.Parent
		}
		if rect.W > 0 && rect.H > 0 {
			b.loadResource(c, current, s, source)
		}
	})
	return nil
}

func decodeResource(ctx context.Context, source string, maxPixel int) (image.Image, error) {
	var reader io.ReadCloser
	switch {
	case strings.HasPrefix(source, "data:"):
		header, payload, ok := strings.Cut(source, ",")
		if !ok {
			return nil, fmt.Errorf("lui: malformed image URI")
		}
		var data []byte
		var err error
		if strings.HasSuffix(header, ";base64") {
			data, err = base64.StdEncoding.DecodeString(payload)
		} else {
			var decoded string
			decoded, err = url.PathUnescape(payload)
			data = []byte(decoded)
		}
		if err != nil {
			return nil, err
		}
		reader = io.NopCloser(bytes.NewReader(data))
	case strings.HasPrefix(source, "http://") || strings.HasPrefix(source, "https://"):
		request, err := http.NewRequestWithContext(ctx, http.MethodGet, source, nil)
		if err != nil {
			return nil, err
		}
		response, err := http.DefaultClient.Do(request)
		if err != nil {
			return nil, err
		}
		if response.StatusCode < 200 || response.StatusCode >= 300 {
			response.Body.Close()
			return nil, fmt.Errorf("lui: image HTTP status %d", response.StatusCode)
		}
		reader = response.Body
	default:
		path := strings.TrimPrefix(source, "file:")
		if strings.HasPrefix(source, "file://") {
			parsed, err := url.Parse(source)
			if err != nil {
				return nil, err
			}
			path = parsed.Path
		}
		file, err := os.Open(path)
		if err != nil {
			return nil, err
		}
		reader = file
	}
	defer reader.Close()
	data, err := io.ReadAll(io.LimitReader(reader, maxResourceBytes+1))
	if err != nil {
		return nil, err
	}
	if len(data) > maxResourceBytes {
		return nil, fmt.Errorf("lui: image exceeds encoded size limit")
	}
	config, _, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	if config.Width <= 0 || config.Height <= 0 || config.Width > maxResourcePixels/config.Height {
		return nil, fmt.Errorf("lui: decoded image exceeds pixel limit")
	}
	pixels, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	if maxPixel > 0 && (config.Width > maxPixel || config.Height > maxPixel) {
		scale := float64(maxPixel) / float64(max(config.Width, config.Height))
		resized := image.NewRGBA(image.Rect(0, 0, max(1, int(float64(config.Width)*scale)), max(1, int(float64(config.Height)*scale))))
		xdraw.BiLinear.Scale(resized, resized.Bounds(), pixels, pixels.Bounds(), draw.Src, nil)
		pixels = resized
	}
	return pixels, nil
}

func (b *Backend) renderResources(c *ui.Context, n Node, s *controlState, _ *[]Event) (ui.Element, bool) {
	switch n.Kind {
	case "icon", "image", "file-image", "media-surface", "avatar":
	default:
		return ui.Element{}, false
	}
	b.resources.init()
	if n.Kind == "icon" {
		extent := float32(18)
		switch n.String("size") {
		case "sm":
			extent = 16
		case "lg":
			extent = 24
		}
		icon := b.icon(n.String("name"))
		if strings.HasPrefix(n.String("name"), "app:") {
			return ui.Image(c, icon).Size(extent, extent).Fit(ui.Contain), true
		}
		return ui.Icon(c, icon).Size(extent, extent), true
	}
	var asset *resourceAsset
	switch n.Kind {
	case "media-surface":
		asset = b.resources.surfaces[int64(n.Number("surface", 0))]
	case "image", "avatar":
		asset = b.resources.images[int64(n.Number("image", 0))]
		if uri := n.String("url"); uri != "" {
			if n.String("loading") == "lazy" {
				asset = b.lazyResource(c, n, s, uri)
			} else {
				asset = b.loadResource(c, n, s, uri)
			}
		} else if s.resource.source != "" {
			b.loadResource(c, n, s, "")
		}
	case "file-image":
		asset = b.loadResource(c, n, s, n.String("path"))
	}
	if n.Kind == "avatar" && asset == nil {
		e := ui.Box(c).Size(40, 40).Center().Radius(20).Clip().Background(c.Theme().Surface).Role(ui.RoleImage)
		e.Children(func() { ui.Text(c, n.String("text")).Bold() })
		return e, true
	}
	source := ui.Rect{W: 24, H: 24}
	if asset != nil {
		source.W, source.H = float32(asset.pixels.Bounds().Dx()), float32(asset.pixels.Bounds().Dy())
	}
	if n.Number("source-width", 0) > 0 {
		source = ui.Rect{X: float32(n.Number("source-x", 0)), Y: float32(n.Number("source-y", 0)), W: float32(n.Number("source-width", 0)), H: float32(n.Number("source-height", 0))}
	}
	e := ui.Box(c).Width(source.W).AspectRatio(source.W / source.H).Role(ui.RoleImage)
	if label := n.String("alt"); label != "" {
		e.Label(label)
	}
	if n.Kind == "avatar" {
		e.Size(40, 40).Radius(20).Clip()
	}
	if asset != nil {
		cover := n.Kind == "avatar" || n.String("image-fit") == "fill"
		e.Draw(func(p *ui.Painter, box ui.Rect) {
			scale := min(box.W/source.W, box.H/source.H)
			if cover {
				scale = max(box.W/source.W, box.H/source.H)
			}
			destination := ui.Rect{X: box.X + (box.W-source.W*scale)/2, Y: box.Y + (box.H-source.H*scale)/2, W: source.W * scale, H: source.H * scale}
			if (n.Kind == "image" || n.Kind == "media-surface") && n.String("image-fit") == "" {
				destination = box
			}
			radius := float32(0)
			if n.Kind == "avatar" {
				radius = min(box.W, box.H) / 2
			}
			p.Clip(box, radius, func() { p.ImageRegion(asset.bitmap, source, destination, ui.ImageOptions{}) })
		})
	}
	return e, true
}

func (b *Backend) icon(name string) *ui.SVG {
	b.resources.init()
	name = strings.ReplaceAll(name, "_", "-")
	if icon := b.resources.icons[name]; icon != nil {
		return icon
	}
	if data, err := builtInIcons.ReadFile("icons/" + name + ".svg"); err == nil {
		icon, _ := ui.ParseSVG(data)
		if !b.probing {
			b.resources.icons[name] = icon
		}
		return icon
	}
	return nil
}

func (b *Backend) retireResource(id int64) {
	store := &b.resources
	state := store.jobs[id]
	if state == nil {
		state = b.states[id]
	}
	if state != nil {
		state.resource.epoch++
		if state.resource.cancel != nil {
			state.resource.cancel()
			state.resource.cancel = nil
		}
		state.resource.asset = nil
	}
	delete(store.jobs, id)
	store.mu.Lock()
	delete(store.results, id)
	store.mu.Unlock()
}

// resetResources disposes node-owned asynchronous work; host registrations
// intentionally survive snapshots and are released explicitly by their owner.
func (b *Backend) resetResources() {
	cancelState := func(state *controlState) {
		state.resource.epoch++
		if state.resource.cancel != nil {
			state.resource.cancel()
			state.resource.cancel = nil
		}
		state.resource.asset = nil
	}
	for _, state := range b.states {
		cancelState(state)
	}
	for _, state := range b.resources.jobs {
		cancelState(state)
	}
	b.resources.jobs = nil
	b.resources.mu.Lock()
	clear(b.resources.results)
	b.resources.results = nil
	b.resources.mu.Unlock()
}

func (b *Backend) closeResources() {
	b.resetResources()
	b.resources.closed = true
	b.resources.images = nil
	b.resources.surfaces = nil
	b.resources.icons = nil
	b.resources.services = ui.Services{}
}

// RegisterIcon registers an application SVG under a canonical app:slug name.
// Parsing owns the document; later mutation of the supplied bytes is harmless.
func (b *Backend) RegisterIcon(name string, svg []byte) error {
	if b.resources.closed {
		return fmt.Errorf("lui: backend resources are closed")
	}
	if !strings.HasPrefix(name, "app:") || !propertyValueSupported("icon", "name", name) {
		return fmt.Errorf("lui: custom icon name must use canonical app:slug")
	}
	if len(svg) > 1<<20 {
		return fmt.Errorf("lui: SVG exceeds document size limit")
	}
	icon, err := ui.ParseSVG(append([]byte(nil), svg...))
	if err != nil {
		return err
	}
	width, height := icon.Size()
	if width <= 0 || height <= 0 {
		return fmt.Errorf("lui: SVG dimensions must be positive")
	}
	b.resources.init()
	b.resources.icons[name] = icon
	b.resources.services.Invalidate()
	return nil
}
func (b *Backend) UnregisterIcon(name string) {
	if strings.HasPrefix(name, "app:") {
		delete(b.resources.icons, name)
		b.resources.services.Invalidate()
	}
}
