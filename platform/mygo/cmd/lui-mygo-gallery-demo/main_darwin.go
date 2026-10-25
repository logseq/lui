//go:build darwin && lui_native_smoke

// Record the actual OCaml Gallery in a visible MyGo window through WindowServer.
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"image"
	"image/color"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/egoist/mygo"
	"github.com/egoist/mygo/testing/native"
	"github.com/egoist/mygo/ui"
	luimygo "github.com/logseq/lui/platform/mygo"
)

type section struct {
	Name          string
	Node, Heading int64
}
type chapter struct {
	Name    string  `json:"name"`
	Seconds float64 `json:"seconds"`
	Node    int64   `json:"node,omitempty"`
}
type report struct {
	Library       string         `json:"library"`
	Capture       string         `json:"capture"`
	Source        string         `json:"sourceMovie"`
	Video         string         `json:"video"`
	WindowID      int            `json:"windowServerID"`
	Bounds        mygo.Rectangle `json:"windowBounds"`
	Sections      int            `json:"sections"`
	TotalSections int            `json:"totalGallerySections"`
	TimingOrigin  string         `json:"chapterTimingOrigin"`
	Chapters      []chapter      `json:"chapters"`
	Error         string         `json:"error,omitempty"`
}
type driver struct {
	b      *luimygo.Backend
	w      *mygo.Window
	handle uintptr
	wanted map[int64]bool
	bounds map[int64]ui.Rect
	frames int
	pause  time.Duration
	start  time.Time
	report *report
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
func run() error {
	library := flag.String("library", "../../_build/default/examples/components/native/liblui_components.dylib", "actual OCaml Components shared library")
	output := flag.String("output", "/tmp/lui-mygo-gallery-demo.mp4", "H.264 video output")
	pause := flag.Duration("pause", 2*time.Second, "readable pause per section and interaction")
	limit := flag.Int("limit-sections", 0, "limit sections for recorder qualification; zero records all")
	only := flag.String("section", "", "record one named source section for native gesture qualification")
	flag.Parse()
	if *pause < 500*time.Millisecond {
		return fmt.Errorf("pause must be at least 500ms")
	}
	absolute, err := filepath.Abs(*library)
	if err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(*output), 0755); err != nil {
		return err
	}
	r := report{Library: absolute, Capture: "macOS screencapture -v -l WindowServerID; actual window compositor, no headless frames", Source: *output + ".source.mov", Video: *output}
	r.TimingOrigin = "Elapsed automation seconds after capture startup; WindowServer source track has its own startup timing."
	b := luimygo.New(luimygo.Config{})
	defer b.Close()
	runtime, err := luimygo.OpenRuntime(absolute, b)
	if err != nil {
		return err
	}
	defer runtime.Close()
	pattern := image.NewRGBA(image.Rect(0, 0, 320, 192))
	for y := 0; y < 192; y++ {
		for x := 0; x < 320; x++ {
			pattern.SetRGBA(x, y, color.RGBA{uint8(30 + x*160/320), uint8(60 + y*140/192), uint8(180 + (x/32+y/32)%2*60), 255})
		}
	}
	if err = b.RegisterImage(1, pattern); err != nil {
		return err
	}
	if err = b.PresentMediaSurfaceFrame(1, pattern); err != nil {
		return err
	}
	d := &driver{b: b, wanted: map[int64]bool{}, bounds: map[int64]ui.Rect{}, pause: *pause, report: &r}
	sections := discover(b)
	r.TotalSections = len(sections)
	if len(sections) < 60 {
		return fmt.Errorf("expected the complete real Gallery, found %d sections", len(sections))
	}
	if *limit > 0 && *limit < len(sections) {
		sections = sections[:*limit]
	}
	if *only != "" {
		selected := []section{}
		for _, page := range sections {
			if page.Name == *only {
				selected = append(selected, page)
			}
		}
		if len(selected) != 1 {
			return fmt.Errorf("unknown or ambiguous Gallery section %q", *only)
		}
		sections = selected
	}
	r.Sections = len(sections)
	done := make(chan error, 1)
	mygo.App.SetName("LUI Component Gallery")
	mygo.App.WhenReady(func() {
		d.w = mygo.NewWindow(mygo.WindowOptions{Title: "LUI · MyGo · Complete Component Gallery", Width: 1100, Height: 820, UseContentSize: true, Content: ui.View(func(c *ui.Context) {
			b.View(c)
			c.AfterFrame(func() {
				for id := range d.wanted {
					d.bounds[id] = b.NativeDemoBounds(c, id)
				}
				d.frames++
			})
		})})
		d.w.Focus()
		d.handle = d.w.NativeHandle()
		go func() {
			err := d.record(sections, *output)
			if err != nil {
				r.Error = err.Error()
			}
			data, jsonErr := json.MarshalIndent(r, "", "  ")
			if jsonErr == nil {
				jsonErr = os.WriteFile(*output+".chapters.json", append(data, '\n'), 0644)
			}
			if err == nil {
				err = jsonErr
			}
			done <- err
			mygo.RunOnMain(func() { runtime.Close(); b.Close(); d.w.Close() })
		}()
	})
	mygo.App.OnWindowAllClosed(func() { mygo.App.Quit() })
	if err = mygo.App.Run(); err != nil {
		return err
	}
	select {
	case err = <-done:
		if err == nil {
			fmt.Printf("Recorded %d actual Gallery sections: %s\n", r.Sections, *output)
		}
		return err
	default:
		return fmt.Errorf("Gallery closed before recording completed")
	}
}

func discover(b *luimygo.Backend) []section {
	var found []section
	var walk func(int64)
	walk = func(id int64) {
		n, _ := b.Node(id)
		if n.Kind == "column" && len(n.Children) > 60 {
			var candidates []section
			for _, child := range n.Children {
				page, _ := b.Node(child)
				if len(page.Children) == 0 {
					continue
				}
				heading, _ := b.Node(page.Children[0])
				if heading.Kind == "heading" && heading.Number("heading-level", 0) == 2 {
					candidates = append(candidates, section{heading.String("text"), child, heading.ID})
				}
			}
			if len(candidates) > 60 {
				found = candidates
				return
			}
		}
		for _, child := range n.Children {
			if len(found) == 0 {
				walk(child)
			}
		}
	}
	for _, root := range b.Roots() {
		walk(root)
	}
	return found
}

func (d *driver) check() error { var err error; mygo.RunOnMain(func() { err = d.b.Err() }); return err }
func (d *driver) wait(name string, condition func() bool) error {
	for deadline := time.Now().Add(15 * time.Second); ; {
		ok := false
		var err error
		mygo.RunOnMain(func() { ok = condition(); err = d.b.Err() })
		if err != nil {
			return err
		}
		if ok {
			return nil
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("timed out: %s", name)
		}
		time.Sleep(20 * time.Millisecond)
	}
}
func (d *driver) frame() error {
	before := 0
	mygo.RunOnMain(func() { before = d.frames; d.w.Invalidate() })
	return d.wait("committed native frame", func() bool { return d.frames > before })
}
func (d *driver) rect(id int64) (ui.Rect, error) {
	mygo.RunOnMain(func() { d.wanted[id] = true })
	if err := d.frame(); err != nil {
		return ui.Rect{}, err
	}
	var r ui.Rect
	mygo.RunOnMain(func() { r = d.bounds[id] })
	return r, nil
}
func (d *driver) scroll(x, y, dy float64) error {
	ok := false
	mygo.RunOnMain(func() { ok = native.Scroll(d.handle, x, y, 0, dy) })
	if !ok {
		return fmt.Errorf("native wheel event unavailable")
	}
	time.Sleep(100 * time.Millisecond)
	return d.frame()
}
func (d *driver) reveal(id int64, top float32) error {
	for attempt := 0; attempt < 8; attempt++ {
		r, err := d.rect(id)
		if err != nil {
			return err
		}
		if r.H <= 0 {
			return fmt.Errorf("node %d has no committed native bounds: %+v", id, r)
		}
		delta := r.Y - top
		if math.Abs(float64(delta)) < 8 {
			return nil
		}
		if err = d.scroll(1080, 400, float64(delta)); err != nil {
			return err
		}
		next, err := d.rect(id)
		if err != nil {
			return err
		}
		if math.Abs(float64(next.Y-r.Y)) < 1 && next.Y >= 0 && next.Y+min(next.H, 40) <= 820 {
			return nil
		}
	}
	return fmt.Errorf("cannot reveal Gallery node %d through native scrolling", id)
}
func (d *driver) mark(name string, id int64) {
	d.report.Chapters = append(d.report.Chapters, chapter{name, time.Since(d.start).Seconds(), id})
	fmt.Println(name)
}
func (d *driver) find(root int64, match func(luimygo.Node) bool) int64 {
	n, ok := d.b.Node(root)
	if !ok {
		return 0
	}
	if match(n) {
		return root
	}
	for _, id := range n.Children {
		if found := d.find(id, match); found != 0 {
			return found
		}
	}
	return 0
}
func (d *driver) lookup(root int64, label string) int64 {
	var id int64
	mygo.RunOnMain(func() {
		id = d.find(root, func(n luimygo.Node) bool {
			return n.String("text") == label || n.String("title") == label || n.String("placeholder") == label || n.String("accessibility-label") == label
		})
	})
	return id
}
func (d *driver) click(root int64, label string) error {
	id := d.lookup(root, label)
	if id == 0 {
		return fmt.Errorf("missing actual Gallery control %q", label)
	}
	if err := d.reveal(id, 180); err != nil {
		return err
	}
	r, err := d.rect(id)
	if err != nil {
		return err
	}
	d.mark("Interact: "+label, id)
	mygo.RunOnMain(func() { native.Click(d.handle, float64(r.X+r.W/2), float64(r.Y+r.H/2)) })
	if err = d.frame(); err != nil {
		return err
	}
	time.Sleep(d.pause)
	return d.check()
}
func (d *driver) escape() error {
	mygo.RunOnMain(func() { native.Key(d.handle, 53, "\x1b") })
	if err := d.frame(); err != nil {
		return err
	}
	time.Sleep(d.pause / 2)
	return d.check()
}

func (d *driver) record(sections []section, output string) (result error) {
	if err := d.wait("WindowServer visibility", func() bool { return native.OnScreen(d.handle) }); err != nil {
		return err
	}
	mygo.RunOnMain(func() { d.report.WindowID = native.WindowNumber(d.handle); d.report.Bounds = d.w.Bounds() })
	// Window-specific recording excludes other applications and desktop content.
	var captureLog bytes.Buffer
	if err := os.Remove(d.report.Source); err != nil && !os.IsNotExist(err) {
		return err
	}
	capture := exec.Command("/usr/sbin/screencapture", "-v", "-x", fmt.Sprintf("-l%d", d.report.WindowID), d.report.Source)
	capture.Stdout = &captureLog
	capture.Stderr = &captureLog
	if err := capture.Start(); err != nil {
		return err
	}
	captureDone := make(chan error, 1)
	go func() { captureDone <- capture.Wait() }()
	stopped := false
	stop := func() error {
		if stopped {
			return nil
		}
		stopped = true
		capture.Process.Signal(os.Interrupt)
		select {
		case err := <-captureDone:
			return err
		case <-time.After(10 * time.Second):
			capture.Process.Kill()
			<-captureDone
			return fmt.Errorf("native screen recorder did not stop")
		}
	}
	defer func() {
		if !stopped {
			stop()
		}
	}()
	time.Sleep(time.Second)
	select {
	case err := <-captureDone:
		stopped = true
		return fmt.Errorf("native window capture startup failed (%v): %s", err, captureLog.String())
	default:
	}
	d.start = time.Now()
	for index, page := range sections {
		if err := d.reveal(page.Heading, 32); err != nil {
			return fmt.Errorf("section %s: %w", page.Name, err)
		}
		d.mark(page.Name, page.Node)
		time.Sleep(d.pause)
		if err := d.interact(page); err != nil {
			return fmt.Errorf("section %s: %w", page.Name, err)
		}
		// Tall compositions get overlapping additional views so the complete
		// section remains readable rather than merely showing its heading.
		if index+1 < len(sections) {
			for detail := 1; detail <= 8; detail++ {
				next, err := d.rect(sections[index+1].Heading)
				if err != nil {
					return err
				}
				if next.Y < 780 {
					break
				}
				if err = d.scroll(1080, 400, 600); err != nil {
					return err
				}
				d.mark(fmt.Sprintf("%s · detail %d", page.Name, detail), page.Node)
				time.Sleep(d.pause)
			}
		}
	}
	d.mark("Complete Gallery", 0)
	time.Sleep(d.pause)
	stopErr := stop()
	if _, err := os.Stat(d.report.Source); err != nil {
		return fmt.Errorf("WindowServer recording failed (%v): %s", stopErr, captureLog.String())
	}
	ffmpeg := exec.Command("ffmpeg", "-y", "-i", d.report.Source, "-vf", "scale=w=min(1920\\,iw):h=-2", "-r", "30", "-c:v", "libx264", "-preset", "fast", "-crf", "22", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an", output)
	if log, err := ffmpeg.CombinedOutput(); err != nil {
		return fmt.Errorf("encode compositor video: %w: %s", err, log)
	}
	return d.check()
}

func (d *driver) interact(page section) error {
	click := func(label string) error { return d.click(page.Node, label) }
	switch page.Name {
	case "Button":
		if err := click("Toggle disabled"); err != nil {
			return err
		}
		return click("Toggle disabled")
	case "Tabs":
		if err := click("Activity"); err != nil {
			return err
		}
		return click("Overview")
	case "Dialog":
		if err := click("Open dialog"); err != nil {
			return err
		}
		return d.escape()
	case "Sheet":
		if err := click("Open sheet"); err != nil {
			return err
		}
		return d.escape()
	case "Tree":
		if err := click("Documents"); err != nil {
			return err
		}
		mygo.RunOnMain(func() { native.Key(d.handle, 124, "\uf703"); native.Key(d.handle, 125, "\uf701") })
		time.Sleep(d.pause)
		return d.check()
	case "TextField":
		if err := click("Project name"); err != nil {
			return err
		}
		mygo.RunOnMain(func() { native.Compose(d.handle, "ni", 2, false) })
		time.Sleep(d.pause / 2)
		mygo.RunOnMain(func() { native.Compose(d.handle, "你好 · LUI", 8, true) })
		time.Sleep(d.pause)
		return d.check()
	case "DropdownMenu":
		if err := click("Choose environment"); err != nil {
			return err
		}
		mygo.RunOnMain(func() { native.Key(d.handle, 125, "\uf701"); native.Key(d.handle, 36, "\r") })
		time.Sleep(d.pause)
		return d.check()
	case "Checkbox":
		return click("Enable notifications")
	case "Switch":
		return click("Background sync")
	case "Toggle":
		return click("Bold formatting")
	case "RadioGroup":
		return click("Compact")
	case "Progress":
		return click("Advance progress")
	case "Stepper":
		return click("Advance stage")
	case "BottomTabs":
		if err := click("Search"); err != nil {
			return err
		}
		return click("Home")
	case "Split":
		var id int64
		mygo.RunOnMain(func() { id = d.find(page.Node, func(n luimygo.Node) bool { return n.Kind == "split" }) })
		if id == 0 {
			return fmt.Errorf("missing Gallery split")
		}
		if err := d.reveal(id, 160); err != nil {
			return err
		}
		r, err := d.rect(id)
		if err != nil {
			return err
		}
		var value float64
		mygo.RunOnMain(func() { n, _ := d.b.Node(id); value = n.Number("value", 0.5) })
		x, y := float64(r.X)+float64(r.W-8)*value+4, float64(r.Y+r.H/2)
		d.mark("Interact: Resize panes", id)
		mygo.RunOnMain(func() { native.AppPress(d.handle, x, y, true) })
		if err = d.frame(); err != nil {
			return err
		}
		for _, dx := range []float64{25, 50, 75, 100} {
			mygo.RunOnMain(func() { native.DragMove(d.handle, x+dx, y) })
			if err = d.frame(); err != nil {
				return err
			}
			time.Sleep(50 * time.Millisecond)
		}
		mygo.RunOnMain(func() { native.AppPress(d.handle, x+100, y, false) })
		if err = d.frame(); err != nil {
			return err
		}
		changed := false
		mygo.RunOnMain(func() { n, _ := d.b.Node(id); changed = math.Abs(n.Number("value", value)-value) > 0.01 })
		if !changed {
			return fmt.Errorf("native split drag did not reach actual OCaml fraction reducer")
		}
		time.Sleep(d.pause)
		return d.check()
	case "Accordion":
		return click("Do collapsed children stay retained?")
	case "Avatar":
		return click("Toggle registered image")
	case "Toast":
		if err := click("Show notifications"); err != nil {
			return err
		}
		return d.escape()
	case "Counter":
		return click("+")
	case "100k Virtual List":
		if err := click("Load 100k"); err != nil {
			return err
		}
		var id int64
		mygo.RunOnMain(func() { id = d.find(page.Node, func(n luimygo.Node) bool { return n.Kind == "virtual-list" }) })
		if err := d.reveal(id, 250); err != nil {
			return err
		}
		r, err := d.rect(id)
		if err != nil {
			return err
		}
		if err = d.scroll(float64(r.X+r.W/2), float64(r.Y+min(r.H/2, 150)), 4000); err != nil {
			return err
		}
		time.Sleep(d.pause)
		return click("Clear")
	case "Editor Input":
		if err := click("Type here — every keystroke round-trips the reducer"); err != nil {
			return err
		}
		mygo.RunOnMain(func() { native.Compose(d.handle, "OCaml ↔ MyGo · 你好", 17, true) })
		time.Sleep(d.pause)
		return d.check()
	case "Event payloads":
		if err := click("Inspect event"); err != nil {
			return err
		}
		return click("Toggle event")
	}
	return d.check()
}
