package luimygo

import (
	"bufio"
	"encoding/json"
	"errors"
	"net"
	"os"
	"strings"
	"testing"
)

func TestAgentFailureShape(t *testing.T) {
	node := int64(7)
	refused := &RuntimeError{Bridge: "Components", Phase: "agent", Node: &node, Message: "handler boom", Recovery: "resync"}
	var reply map[string]any
	if err := json.Unmarshal([]byte(agentFailure(refused, refused)), &reply); err != nil {
		t.Fatal(err)
	}
	if reply["ok"] != false || reply["refused"] != true || reply["error"] != "handler boom" {
		t.Fatalf("refusal reply = %v", reply)
	}
	if diagnostic, _ := reply["diagnostic"].(map[string]any); diagnostic["phase"] != "agent" || diagnostic["node"] != float64(7) {
		t.Fatalf("refusal diagnostic = %v", reply["diagnostic"])
	}
	if err := json.Unmarshal([]byte(agentFailure(errors.New("lui: OCaml session is closed"), nil)), &reply); err != nil {
		t.Fatal(err)
	}
	if reply["ok"] != false || reply["error"] != "lui: OCaml session is closed" {
		t.Fatalf("host failure reply = %v", reply)
	}
}

func TestAgentLinesAreBounded(t *testing.T) {
	reader := bufio.NewReaderSize(strings.NewReader(strings.Repeat("x", agentMaxLine+1)+"\n"+`{"op":"tree"}`+"\n"), 4096)
	if _, err := readAgentLine(reader); !errors.Is(err, errAgentLineTooLong) {
		t.Fatalf("oversized request: %v", err)
	}
	if line, err := readAgentLine(reader); err != nil || line != `{"op":"tree"}` {
		t.Fatalf("request after an oversized one = %q, %v", line, err)
	}
	line, err := readAgentLine(bufio.NewReaderSize(strings.NewReader(`{"op":"hello"}`+"\n"), 16))
	if err != nil || line != `{"op":"hello"}` {
		t.Fatalf("split request = %q, %v", line, err)
	}
}

func TestAgentServerListensOnlyOnLoopback(t *testing.T) {
	r := &Runtime{}
	for _, address := range []string{"0.0.0.0:0", "192.0.2.1:0", "example.com:0", "nonsense"} {
		if server, err := r.ServeAgent(address, func(fn func()) { fn() }); err == nil {
			server.Close()
			t.Fatalf("%s was accepted", address)
		}
	}
	t.Setenv(AgentListenEnv, "")
	if server, err := r.ServeAgentFromEnv(func(fn func()) { fn() }); server != nil || err != nil {
		t.Fatalf("unset %s started a server: %v", AgentListenEnv, err)
	}
}

// The shared OCaml agent answers through the real Components library: the
// same request a script sends to any host reaches the Gallery reducer, and
// the action's patches land in this backend before the reply returns.
func TestOCamlComponentsAgent(t *testing.T) {
	path := os.Getenv("LUI_MYGO_COMPONENTS_LIBRARY")
	if path == "" {
		t.Skip("run tooling/test_mygo.sh for separate Components integration")
	}
	b := New(Config{})
	defer b.Close()
	runtime, err := OpenRuntime(path, b)
	if err != nil {
		t.Fatal(err)
	}
	defer runtime.Close()
	status := func() string {
		for _, node := range b.nodes {
			if node.String("accessibility-identifier") == "events-status" {
				return node.String("text")
			}
		}
		t.Fatal("missing Gallery events-status")
		return ""
	}
	agent := func(request string) map[string]any {
		t.Helper()
		reply, err := runtime.Agent(request)
		if err != nil {
			t.Fatal(err)
		}
		var decoded map[string]any
		if err := json.Unmarshal([]byte(reply), &decoded); err != nil {
			t.Fatalf("reply %q: %v", reply, err)
		}
		return decoded
	}
	if hello := agent(`{"op":"hello"}`); hello["protocol"] != "lui-agent" || hello["version"] != float64(1) {
		t.Fatalf("hello = %v", hello)
	}
	if reply := agent(`{"op":"press","selector":"prop:accessibility-identifier=events-button"}`); reply["ok"] != true {
		t.Fatalf("press = %v", reply)
	}
	if got := status(); got != "Event: press" {
		t.Fatalf("agent press reached the reducer as %q", got)
	}
	generation := b.Generation()
	if reply := agent(`{"op":"type","selector":"prop:accessibility-identifier=events-editor","text":"agent 你好"}`); reply["ok"] != true {
		t.Fatalf("type = %v", reply)
	}
	if got := status(); got != "Event: text-changed:agent 你好" || b.Generation() == generation {
		t.Fatalf("typed patches were not applied: %q", got)
	}
	if reply := agent(`{"op":"press","selector":"text:No such control"}`); reply["ok"] != false {
		t.Fatalf("unmatched selector = %v", reply)
	}

	jobs := make(chan func())
	server, err := runtime.ServeAgent("127.0.0.1:0", func(fn func()) {
		done := make(chan struct{})
		jobs <- func() { defer close(done); fn() }
		<-done
	})
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	replies := make(chan []string, 1)
	go func() {
		conn, err := net.Dial("tcp", server.Addr())
		if err != nil {
			replies <- []string{err.Error()}
			return
		}
		defer conn.Close()
		reader := bufio.NewReader(conn)
		var lines []string
		for _, request := range []string{`{"op":"hello"}`, `{"op":"press","selector":"prop:accessibility-identifier=events-button"}`, `not json`} {
			if _, err := conn.Write([]byte(request + "\n")); err != nil {
				break
			}
			line, err := reader.ReadString('\n')
			if err != nil {
				break
			}
			lines = append(lines, strings.TrimSpace(line))
		}
		replies <- lines
	}()
	var lines []string
	for lines == nil {
		select {
		case job := <-jobs:
			job()
		case lines = <-replies:
		}
	}
	if len(lines) != 3 || !strings.Contains(lines[0], `"protocol":"lui-agent"`) ||
		!strings.Contains(lines[1], `"ok":true`) || !strings.Contains(lines[2], `"error":"bad request`) {
		t.Fatalf("socket replies = %q", lines)
	}
	if got := status(); got != "Event: press" {
		t.Fatalf("socket press reached the reducer as %q", got)
	}
	if b.Err() != nil {
		t.Fatal(b.Err())
	}
}
