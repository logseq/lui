// lui-mygo hosts an OCaml LUI shared library in a native MyGo window.
package main

import (
	"flag"
	"fmt"
	"image/png"
	"log"
	"os"

	"github.com/egoist/mygo"
	"github.com/egoist/mygo/ui"
	luimygo "github.com/logseq/lui/platform/mygo"
)

func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}
func run() error {
	library := flag.String("library", "", "path to an OCaml library exporting lui_ocaml_*")
	title := flag.String("title", "LUI · MyGo", "window title")
	width := flag.Int("width", 800, "content width in DIPs")
	height := flag.Int("height", 600, "content height in DIPs")
	screenshot := flag.String("screenshot", "", "render a headless frame to this PNG and exit")
	flag.Parse()
	if *library == "" {
		return fmt.Errorf("-library is required; see platform/mygo/README.md")
	}
	if *width <= 0 || *height <= 0 {
		return fmt.Errorf("width and height must be positive")
	}
	b := luimygo.New(luimygo.Config{})
	defer b.Close()
	r, err := luimygo.OpenRuntime(*library, b)
	if err != nil {
		return err
	}
	defer r.Close()
	if *screenshot != "" {
		tester := ui.NewTester(b.View, *width, *height)
		if b.Err() != nil {
			return b.Err()
		}
		file, err := os.Create(*screenshot)
		if err != nil {
			return err
		}
		err = png.Encode(file, tester.Image())
		closeErr := file.Close()
		if err != nil {
			return err
		}
		return closeErr
	}
	mygo.App.SetName("LUI MyGo")
	mygo.App.WhenReady(func() {
		mygo.NewWindow(mygo.WindowOptions{Title: *title, Width: *width, Height: *height, UseContentSize: true, Content: ui.View(b.View)})
	})
	mygo.App.OnWindowAllClosed(func() { mygo.App.Quit() })
	return mygo.App.Run()
}
