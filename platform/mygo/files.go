package luimygo

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image"
	"io"
	"mime"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/egoist/mygo"
	"github.com/egoist/mygo/ui"
	"github.com/go-pdfkit/reader"
	pdfrender "github.com/go-pdfkit/render"
)

// FileDialogOptions describes portable desktop selection constraints.
type FileDialogOptions struct {
	Multiple  bool
	Directory bool
	Accept    []string
	Types     []string
}

// FileServices is the operating-system dialog boundary. The backend keeps
// request correlation, retained lifetimes and event delivery on its UI thread.
// OpenFiles may block; implementations should observe cancellation where their
// native dialog API permits it. Nil paths represent user cancellation.
type FileServices interface {
	OpenFiles(context.Context, FileDialogOptions) ([]string, error)
}

type nativeFileServices struct{}

func (nativeFileServices) OpenFiles(ctx context.Context, options FileDialogOptions) ([]string, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if !mygo.App.IsReady() {
		return nil, fmt.Errorf("lui: native file dialog requires a running MyGo application")
	}
	paths, err := mygo.Dialog.OpenContext(ctx, mygo.OpenDialogOptions{Multiple: options.Multiple, Directory: options.Directory, Filters: fileFilters(options)})
	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	return paths, err
}
func fileFilters(options FileDialogOptions) []mygo.FileFilter {
	var extensions []string
	for _, accept := range options.Accept {
		accept = strings.TrimSpace(accept)
		switch {
		case strings.HasPrefix(accept, "."):
			extensions = append(extensions, strings.TrimPrefix(accept, "."))
		case accept == "image/*":
			extensions = append(extensions, "png", "jpg", "jpeg", "gif", "webp", "bmp")
		case accept == "text/*":
			extensions = append(extensions, "txt", "md", "csv", "json", "xml")
		default:
			if values, err := mime.ExtensionsByType(accept); err == nil {
				for _, value := range values {
					extensions = append(extensions, strings.TrimPrefix(value, "."))
				}
			}
		}
	}
	for _, uti := range options.Types {
		switch uti {
		case "public.image":
			extensions = append(extensions, "png", "jpg", "jpeg", "gif", "webp", "bmp")
		case "public.jpeg":
			extensions = append(extensions, "jpg", "jpeg")
		case "public.png":
			extensions = append(extensions, "png")
		case "public.plain-text":
			extensions = append(extensions, "txt")
		case "public.json":
			extensions = append(extensions, "json")
		case "com.adobe.pdf":
			extensions = append(extensions, "pdf")
		}
	}
	if len(extensions) == 0 {
		return nil
	}
	return []mygo.FileFilter{{Name: "Allowed files", Extensions: extensions}}
}

type fileToken struct {
	key   string
	value any
	valid bool
}

func fileRequest(value any) fileToken {
	if value == nil {
		return fileToken{}
	}
	encoded, err := json.Marshal(value)
	if err != nil {
		return fileToken{}
	}
	return fileToken{key: string(encoded), value: value, valid: true}
}

type fileNodeState struct {
	identity         uint64
	cancel           context.CancelFunc
	last, request    fileToken
	active, awaiting bool
	epoch            uint64
	path             string
	page, pageCount  int
	text             string
	bitmap           *ui.Bitmap
	loading, closed  bool
	started          bool
	err              error
}
type fileResult struct {
	node            int64
	identity, epoch uint64
	paths           []string
	text            string
	pixels          image.Image
	pageCount       int
	preview         bool
	err             error
}
type fileStore struct {
	states   map[int64]*fileNodeState
	mu       sync.Mutex
	results  []fileResult
	services ui.Services
}

var filePreviewWorkers = make(chan struct{}, 4)

func (b *Backend) retireFile(id int64) {
	if state := b.files.states[id]; state != nil {
		if state.cancel != nil {
			state.cancel()
		}
		delete(b.files.states, id)
		b.files.mu.Lock()
		retained := b.files.results[:0]
		for _, result := range b.files.results {
			if result.node != id {
				retained = append(retained, result)
			}
		}
		clear(b.files.results[len(retained):])
		b.files.results = retained
		b.files.mu.Unlock()
	}
}
func (b *Backend) resetFiles() {
	for id := range b.files.states {
		b.retireFile(id)
	}
}
func (b *Backend) closeFiles() {
	b.resetFiles()
	b.files.mu.Lock()
	b.files.results = nil
	b.files.mu.Unlock()
	b.files.services = ui.Services{}
}

func (b *Backend) fileState(n Node, s *controlState) *fileNodeState {
	if b.files.states == nil {
		b.files.states = make(map[int64]*fileNodeState)
	}
	state := b.files.states[n.ID]
	if state == nil || state.identity != s.identity {
		if state != nil && state.cancel != nil {
			state.cancel()
		}
		state = &fileNodeState{identity: s.identity, page: 1}
		b.files.states[n.ID] = state
	}
	return state
}
func (b *Backend) queueFileEvent(e Event) {
	if b.probing {
		return
	}
	if s := b.states[e.Node]; s != nil {
		e.incarnation = s.identity
	}
	b.queued = append(b.queued, e)
}
func (b *Backend) prepareFiles(c *ui.Context) {
	if b.probing {
		return
	}
	store := &b.files
	store.services = c.Services()
	for id, state := range store.states {
		if s := b.states[id]; s == nil || s.identity != state.identity {
			if state.cancel != nil {
				state.cancel()
			}
			delete(store.states, id)
		}
	}
	store.mu.Lock()
	results := store.results
	store.results = nil
	store.mu.Unlock()
	for _, result := range results {
		state := store.states[result.node]
		if state == nil || state.identity != result.identity || state.epoch != result.epoch {
			continue
		}
		n, ok := b.nodes[result.node]
		if !ok {
			continue
		}
		if state.cancel != nil {
			state.cancel()
			state.cancel = nil
		}
		if result.preview {
			state.loading = false
			state.text = result.text
			state.err = result.err
			state.pageCount = result.pageCount
			state.bitmap = nil
			if result.pixels != nil {
				state.bitmap = ui.NewBitmap(result.pixels)
			}
			continue
		}
		state.active = false
		if result.err != nil || len(result.paths) == 0 {
			b.queueFileEvent(Event{Kind: "dismiss", Node: n.ID})
			continue
		}
		type pickedFile struct {
			Path        string `json:"path"`
			Name        string `json:"name"`
			ContentType string `json:"content-type"`
		}
		files := make([]pickedFile, 0, len(result.paths))
		failures := 0
		for _, path := range result.paths {
			info, err := os.Stat(path)
			if err != nil {
				failures++
				continue
			}
			contentType := mime.TypeByExtension(strings.ToLower(filepath.Ext(path)))
			if info.IsDir() {
				contentType = "inode/directory"
			} else if contentType == "" {
				contentType = "application/octet-stream"
			}
			files = append(files, pickedFile{Path: path, Name: filepath.Base(path), ContentType: contentType})
		}
		payload, _ := json.Marshal(struct {
			Request  any          `json:"request"`
			Files    []pickedFile `json:"files"`
			Failures int          `json:"failures"`
		}{state.request.value, files, failures})
		state.awaiting = true
		b.queueFileEvent(Event{Kind: "picked", Node: n.ID, Payload: string(payload)})
	}
}

func (b *Backend) renderFiles(c *ui.Context, n Node, s *controlState, _ *[]Event) (ui.Element, bool) {
	if n.Kind != "file-picker" && n.Kind != "file-preview" {
		return ui.Element{}, false
	}
	if b.probing {
		return ui.Element{}, true
	}
	state := b.fileState(n, s)
	if n.Kind == "file-picker" {
		request := fileRequest(n.Props["request"])
		completion := fileRequest(n.Props["completion"])
		if completion.valid && state.request.valid && completion.key == state.request.key {
			if state.cancel != nil {
				state.cancel()
				state.cancel = nil
			}
			state.active = false
			state.awaiting = false
		}
		if !request.valid || request.key == completion.key || n.Props["enabled"] == false || state.active || state.awaiting || request.key == state.last.key {
			return ui.Element{}, true
		}
		// Services begin only after the selected view pass commits. Measurement
		// and discarded build passes never present native UI or start workers.
		identity, id := s.identity, n.ID
		c.AfterFrame(func() {
			current, ok := b.nodes[id]
			if !ok || b.states[id] == nil || b.states[id].identity != identity || current.Props["enabled"] == false {
				return
			}
			if state.active || state.awaiting || request.key == state.last.key {
				return
			}
			state.last = request
			state.request = request
			state.active = true
			state.epoch++
			epoch := state.epoch
			if source := current.String("source"); source != "" && source != "files" {
				state.active = false
				b.emit(Event{Kind: "dismiss", Node: id, incarnation: identity})
				return
			}
			ctx, cancel := context.WithCancel(context.Background())
			state.cancel = cancel
			options := FileDialogOptions{Multiple: current.Bool("multiple"), Directory: current.Bool("directory"), Accept: fileList(current.String("accept")), Types: fileList(current.String("types"))}
			service := b.config.FileServices
			if service == nil {
				service = nativeFileServices{}
			}
			store, services := &b.files, c.Services()
			go func() {
				paths, err := service.OpenFiles(ctx, options)
				if ctx.Err() != nil {
					return
				}
				store.mu.Lock()
				if ctx.Err() == nil {
					store.results = append(store.results, fileResult{node: id, identity: identity, epoch: epoch, paths: paths, err: err})
				}
				store.mu.Unlock()
				services.Invalidate()
			}()
		})
		return ui.Element{}, true
	}
	if path := n.String("path"); path != state.path {
		state.path = path
		state.page = 1
		state.closed = false
		b.startFilePreview(c, n, state)
	}
	if state.closed {
		return ui.Element{}, true
	}
	if state.loading && !state.started {
		b.scheduleFilePreview(c, n, state)
	}
	open := true
	panel := ui.Modal(c, &open, func() {
		ui.Row(c).AlignItems(ui.Center).Gap(12).Children(func() {
			ui.Text(c, filepath.Base(state.path)).Bold()
			ui.Button(c, "Close preview").OnClick(func() {
				if !state.closed {
					state.closed = true
					if state.cancel != nil {
						state.cancel()
					}
					b.emit(Event{Kind: "dismiss", Node: n.ID, incarnation: s.identity})
				}
			})
		})
		switch {
		case state.loading:
			ui.Text(c, "Loading preview…")
		case state.err != nil:
			ui.Text(c, "Cannot preview: "+state.err.Error())
		case state.bitmap != nil:
			ui.Image(c, state.bitmap).Label("Preview page").Fit(ui.Contain).MaxWidth(600).MaxHeight(360)
			if state.pageCount > 0 {
				ui.Row(c).AlignItems(ui.Center).Gap(8).Children(func() {
					ui.Button(c, "Previous page").Disabled(state.page <= 1).OnClick(func() { state.page--; b.startFilePreview(c, n, state) })
					ui.Text(c, fmt.Sprintf("Page %d of %d", state.page, state.pageCount))
					ui.Button(c, "Next page").Disabled(state.page >= state.pageCount).OnClick(func() { state.page++; b.startFilePreview(c, n, state) })
				})
			}
		default:
			ui.Scroll(c).MaxHeight(360).Children(func() { ui.Text(c, state.text).Selectable() })
		}
	})
	if panel.Dismissed() && !state.closed {
		state.closed = true
		if state.cancel != nil {
			state.cancel()
		}
		b.queueFileEvent(Event{Kind: "dismiss", Node: n.ID})
	}
	return panel, true
}
func fileList(value string) []string {
	var list []string
	for _, item := range strings.Split(value, ",") {
		if item = strings.TrimSpace(item); item != "" {
			list = append(list, item)
		}
	}
	return list
}
func (b *Backend) startFilePreview(c *ui.Context, n Node, state *fileNodeState) {
	if state.cancel != nil {
		state.cancel()
	}
	state.epoch++
	state.loading = true
	state.started = false
	state.bitmap = nil
	state.text = ""
	state.err = nil
	b.scheduleFilePreview(c, n, state)
}
func (b *Backend) scheduleFilePreview(c *ui.Context, n Node, state *fileNodeState) {
	ctx, cancel := context.WithCancel(context.Background())
	state.cancel = cancel
	id, identity, epoch, path, page := n.ID, state.identity, state.epoch, state.path, state.page
	store, services := &b.files, c.Services()
	c.AfterFrame(func() {
		if current := store.states[id]; current != state || state.closed || state.epoch != epoch || state.started {
			return
		}
		state.started = true
		go func() {
			result := fileResult{node: id, identity: identity, epoch: epoch, preview: true}
			select {
			case filePreviewWorkers <- struct{}{}:
			case <-ctx.Done():
				return
			}
			result.text, result.pixels, result.pageCount, result.err = readFilePreview(ctx, path, page)
			<-filePreviewWorkers
			if ctx.Err() != nil {
				return
			}
			store.mu.Lock()
			if ctx.Err() == nil {
				store.results = append(store.results, result)
			}
			store.mu.Unlock()
			services.Invalidate()
		}()
	})
}
func readFilePreview(ctx context.Context, path string, page int) (string, image.Image, int, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", nil, 0, err
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, maxResourceBytes+1))
	if err != nil {
		return "", nil, 0, err
	}
	if len(data) > maxResourceBytes {
		return "", nil, 0, fmt.Errorf("file exceeds the %d byte preview limit", maxResourceBytes)
	}
	if err := ctx.Err(); err != nil {
		return "", nil, 0, err
	}
	if strings.EqualFold(filepath.Ext(path), ".pdf") {
		document, err := reader.Open(data)
		if err != nil {
			return "", nil, 0, err
		}
		count := document.PageCount()
		if count < 1 {
			return "", nil, 0, fmt.Errorf("PDF has no pages")
		}
		pixels, err := pdfrender.Page(document, page, pdfrender.Options{Scale: 1, MaxPixels: 4 << 20, MaxDuration: 3 * time.Second})
		if err != nil {
			return "", nil, count, err
		}
		return "", pixels.ToNRGBA(), count, nil
	}
	if config, _, err := image.DecodeConfig(bytes.NewReader(data)); err == nil {
		if config.Width <= 0 || config.Height <= 0 || config.Width > maxResourcePixels/config.Height {
			return "", nil, 0, fmt.Errorf("image exceeds preview dimensions")
		}
		pixels, _, err := image.Decode(bytes.NewReader(data))
		return "", pixels, 0, err
	}
	if !utf8.Valid(data) || bytes.IndexByte(data, 0) >= 0 {
		return "", nil, 0, fmt.Errorf("unsupported file format")
	}
	return string(data), nil, 0, nil
}
