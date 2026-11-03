package luimygo

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// A real native ABI fixture echoes the startup host into a committed wire
// property. Each child process owns exactly one loaded runtime library.
func TestRuntimeVirtualCapabilityProfile(t *testing.T) {
	if path := os.Getenv("LUI_MYGO_PROFILE_CHILD"); path != "" {
		expected := os.Getenv("LUI_MYGO_PROFILE_EXPECT")
		b := New(Config{})
		defer b.Close()
		r, err := OpenRuntime(path, b)
		if err != nil {
			t.Fatal(err)
		}
		defer r.Close()
		n, ok := b.Node(1)
		if !ok || n.String("text") != "host:"+expected {
			t.Fatalf("native startup profile: got%q want host:%s", n.String("text"), expected)
		}
		e := Event{Kind: "virtual-window", Node: 1, Generation: 9007199254740993, First: 0, Last: 10, Pins: []int64{5, 9007199254740995}}
		err = r.Dispatch(e)
		if expected == "0" {
			if err == nil || !strings.Contains(err.Error(), "unsupported runtime event") {
				t.Fatalf("missing optional export did not preserve eager profile: %v", err)
			}
		} else {
			if err != nil {
				t.Fatal(err)
			}
			n, _ = b.Node(1)
			if n.String("text") != "window:received" {
				t.Fatalf("native window ABI lost exact generation/pins: %q", n.String("text"))
			}
		}
		return
	}
	cc, err := exec.LookPath("cc")
	if err != nil {
		t.Skip("native profile boundary test requires a C compiler")
	}
	exe, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	for _, capable := range []bool{false, true} {
		t.Run(fmt.Sprint(capable), func(t *testing.T) {
			dir := t.TempDir()
			suffix := ".so"
			if runtime.GOOS == "darwin" {
				suffix = ".dylib"
			}
			if runtime.GOOS == "windows" {
				suffix = ".dll"
			}
			source := filepath.Join(dir, "profile.c")
			library := filepath.Join(dir, "profile"+suffix)
			code := `#include <stdint.h>
#include <stdio.h>
static void (*send_batch)(const char *);
int32_t lui_ocaml_start(void (*callback)(const char *),int32_t platform,int32_t host) {
 (void)platform; send_batch=callback;
 char batch[512];snprintf(batch,sizeof(batch),"{\"generation\":1,\"ops\":[{\"op\":\"create-node\",\"id\":1,\"kind\":\"text\"},{\"op\":\"set-prop\",\"id\":1,\"property\":\"text\",\"value\":\"host:%d\"}]}",host);
 send_batch(batch);return 1;
}
`
			for _, name := range strings.Fields("stop resync press_ex text_changed_utf8 toggle_changed toggle_changed_detail slider_changed extension_event_utf8 picked_utf8 visible_range scroll_completed scroll_edges navigation_key_utf8 press_detail_utf8 pointer_down_utf8 pointer_up_utf8 pointer_move_utf8 pointer_cancel_utf8 context_menu_press_utf8 press long_press submit dismiss double_press appear radio_changed pointer_enter pointer_leave load navigate_previous navigate_next") {
				code += "int32_t lui_ocaml_" + name + "(void) {return 1;}\n"
			}
			if capable {
				code += `int32_t lui_ocaml_virtual_window(int64_t node,int64_t generation,int64_t first,int64_t last,const int64_t *pins,int32_t count) {
 if(node!=1 || generation!=9007199254740993LL || first!=0 || last!=10 || count!=2 || pins==NULL || pins[0]!=5 || pins[1]!=9007199254740995LL)return 0;
 send_batch("{\"generation\":2,\"ops\":[{\"op\":\"set-prop\",\"id\":1,\"property\":\"text\",\"value\":\"window:received\"}]}");return 1;
}
`
			}
			if err := os.WriteFile(source, []byte(code), 0600); err != nil {
				t.Fatal(err)
			}
			if output, err := exec.Command(cc, "-shared", "-fPIC", "-o", library, source).CombinedOutput(); err != nil {
				t.Fatalf("compile native profile fixture: %s: %v", output, err)
			}
			expected := "0"
			if capable {
				expected = "5"
			}
			command := exec.Command(exe, "-test.run=^TestRuntimeVirtualCapabilityProfile$", "-test.count=1")
			command.Env = append(os.Environ(), "LUI_MYGO_PROFILE_CHILD="+library, "LUI_MYGO_PROFILE_EXPECT="+expected)
			if output, err := command.CombinedOutput(); err != nil {
				t.Fatalf("native profile%d boundary: %s: %v", map[bool]int{false: 0, true: 5}[capable], output, err)
			}
		})
	}
}
