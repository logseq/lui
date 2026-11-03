//go:build !race

package luimygo

import (
	"strings"
	"testing"
)

func TestRuntimeReceiveOwnedStringAllocationBudget(t *testing.T) {
	payload := strings.Repeat("café 你好 👋", 64*1024)
	owned := `{"generation":1,"ops":[{"op":"create-node","id":1,"kind":"text"},{"op":"set-prop","id":1,"property":"text","value":"` + payload + `"}]}`
	data := []byte(owned)
	measure := func(receive bool) testing.BenchmarkResult {
		return testing.Benchmark(func(b *testing.B) {
			for b.Loop() {
				backend := New(Config{})
				var err error
				if receive {
					err = (&Runtime{backend: backend}).receive([]string{owned}, true)
				} else {
					err = backend.ApplyJSON(data, true)
				}
				if err != nil {
					b.Fatal(err)
				}
				node, ok := backend.Node(1)
				if !ok || node.String("text") != payload {
					b.Fatal("actual receive path lost the owned text")
				}
				backend.Close()
			}
		})
	}
	bytesResult, stringResult := measure(false), measure(true)
	extra := stringResult.AllocedBytesPerOp() - bytesResult.AllocedBytesPerOp()
	// Both routes decode and retain the same large scalar. Receiving its
	// already-owned C string must not allocate another complete wire copy.
	if limit := int64(len(owned)/4 + 64*1024); extra > limit {
		t.Fatalf("receiving an owned %d-byte wire string adds %d allocation bytes over the byte API; budget %d", len(owned), extra, limit)
	}
	t.Logf("wire_bytes=%d byte_api_allocated=%d string_receive_allocated=%d extra=%d", len(owned), bytesResult.AllocedBytesPerOp(), stringResult.AllocedBytesPerOp(), extra)
}
