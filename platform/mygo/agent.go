package luimygo

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"strings"
	"sync"
)

// AgentListenEnv names the loopback address a host opts into with
// ServeAgentFromEnv, e.g. LUI_AGENT_LISTEN=127.0.0.1:49380.
const AgentListenEnv = "LUI_AGENT_LISTEN"

const agentMaxLine = 1 << 20

// Agent answers one lui-agent request, a JSON object such as
// {"op":"press","selector":"text:Save"}, with the shared OCaml agent's reply
// object. Patches produced by an action are applied before it returns. A
// request the runtime refuses returns a *RuntimeError after the usual resync.
// Call it on the UI goroutine, like Dispatch.
func (r *Runtime) Agent(request string) (string, error) {
	if r.worker.functions.agent == nil {
		return "", fmt.Errorf("lui: the OCaml library does not export lui_ocaml_agent_utf8")
	}
	var reply string
	batches, err := r.invoke(func(f nativeFunctions) int32 {
		w := r.worker
		w.reply = ""
		accepted := f.agent(request, int32(len(request)), w.replyCallback)
		reply = w.reply
		w.reply = ""
		return accepted
	})
	if err != nil {
		var failure *RuntimeError
		if errors.As(err, &failure) && failure.Recovery == "resync" {
			if recoveryErr := r.Resync(); recoveryErr != nil {
				return "", fmt.Errorf("%w; snapshot failed: %v", err, recoveryErr)
			}
		}
		return "", err
	}
	if applyErr := r.receive(batches, false); applyErr != nil {
		if recoveryErr := r.Resync(); recoveryErr != nil {
			return "", fmt.Errorf("lui: delta rejected (%v), snapshot failed: %w", applyErr, recoveryErr)
		}
	}
	return reply, nil
}

// AgentServer carries newline-delimited lui-agent requests from one loopback
// TCP client at a time to Runtime.Agent and writes one reply line per request.
type AgentServer struct {
	listener net.Listener
	runtime  *Runtime
	onUI     func(func())
	done     chan struct{}
	mu       sync.Mutex
	conn     net.Conn
	closed   bool
}

// ServeAgent listens on a loopback address. onUI must run fn on the UI
// goroutine, wait for it, and schedule a redraw (mygo.RunOnMain followed by
// the window's Invalidate in an app).
func (r *Runtime) ServeAgent(address string, onUI func(func())) (*AgentServer, error) {
	if onUI == nil {
		return nil, fmt.Errorf("lui: agent server needs a UI executor")
	}
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return nil, fmt.Errorf("lui: agent address %q: %w", address, err)
	}
	if ip := net.ParseIP(host); host != "localhost" && (ip == nil || !ip.IsLoopback()) {
		return nil, fmt.Errorf("lui: agent address %q is not loopback", address)
	}
	listener, err := net.Listen("tcp", address)
	if err != nil {
		return nil, fmt.Errorf("lui: agent listen: %w", err)
	}
	s := &AgentServer{listener: listener, runtime: r, onUI: onUI, done: make(chan struct{})}
	go s.accept()
	return s, nil
}

// ServeAgentFromEnv starts ServeAgent on $LUI_AGENT_LISTEN and returns nil
// without listening when the variable is unset.
func (r *Runtime) ServeAgentFromEnv(onUI func(func())) (*AgentServer, error) {
	address := strings.TrimSpace(os.Getenv(AgentListenEnv))
	if address == "" {
		return nil, nil
	}
	return r.ServeAgent(address, onUI)
}

// Addr is the bound address, useful after listening on port 0.
func (s *AgentServer) Addr() string { return s.listener.Addr().String() }

// Close stops listening, drops the current client and waits for the server
// goroutine to finish.
func (s *AgentServer) Close() error {
	s.mu.Lock()
	if s.closed {
		s.mu.Unlock()
		return nil
	}
	s.closed = true
	if s.conn != nil {
		_ = s.conn.Close()
	}
	s.mu.Unlock()
	err := s.listener.Close()
	<-s.done
	return err
}

func (s *AgentServer) accept() {
	defer close(s.done)
	for {
		conn, err := s.listener.Accept()
		if err != nil {
			return
		}
		s.mu.Lock()
		if s.closed {
			s.mu.Unlock()
			_ = conn.Close()
			return
		}
		s.conn = conn
		s.mu.Unlock()
		s.serve(conn)
		s.mu.Lock()
		s.conn = nil
		s.mu.Unlock()
	}
}

func (s *AgentServer) serve(conn net.Conn) {
	defer conn.Close()
	reader := bufio.NewReaderSize(conn, 64<<10)
	for {
		line, err := readAgentLine(reader)
		if errors.Is(err, errAgentLineTooLong) {
			if _, err := conn.Write([]byte(agentFailure(err, nil) + "\n")); err != nil {
				return
			}
			continue
		}
		if err != nil {
			return
		}
		if strings.TrimSpace(line) == "" {
			continue
		}
		var reply string
		var failure error
		s.onUI(func() { reply, failure = s.runtime.Agent(line) })
		if failure != nil {
			var refused *RuntimeError
			if errors.As(failure, &refused) {
				reply = agentFailure(failure, refused)
			} else {
				reply = agentFailure(failure, nil)
			}
		}
		if _, err := conn.Write([]byte(reply + "\n")); err != nil {
			return
		}
	}
}

var errAgentLineTooLong = errors.New("lui: agent request exceeds 1 MiB")

// An oversized line is consumed to its end before it is refused, so the
// client keeps its connection and the next line starts cleanly.
func readAgentLine(reader *bufio.Reader) (string, error) {
	var line []byte
	tooLong := false
	for {
		chunk, isPrefix, err := reader.ReadLine()
		if err != nil {
			return "", err
		}
		if !tooLong {
			line = append(line, chunk...)
			if len(line) > agentMaxLine {
				tooLong, line = true, nil
			}
		}
		if !isPrefix {
			if tooLong {
				return "", errAgentLineTooLong
			}
			return string(line), nil
		}
	}
}

// Host-level failures share the agent's reply shape; a refusal also carries
// the runtime's diagnostic so the client can report what raised.
func agentFailure(err error, refused *RuntimeError) string {
	reply := map[string]any{"ok": false, "error": err.Error()}
	if refused != nil {
		reply["refused"] = true
		reply["error"] = refused.Message
		reply["diagnostic"] = refused
	}
	encoded, _ := json.Marshal(reply)
	return string(encoded)
}
