//go:build !race

package luimygo

import (
	"strings"
	"testing"
)

func TestBackendStreamOperationAllocationBudget(t *testing.T) {
	const rows = 10_000
	source := strings.Replace(string(decodeAllocationPayload(rows)), `"ops":[`, `"ops":[{"op":"create-node","id":1,"kind":"virtual-list"},`, 1)
	data := []byte(source)
	measure := func(stream bool) testing.BenchmarkResult {
		return testing.Benchmark(func(b *testing.B) {
			for b.Loop() {
				backend := New(Config{})
				var err error
				if stream {
					err = backend.ApplyJSON(data, false)
				} else {
					var batch Batch
					batch, err = DecodeBatch(data)
					if err == nil {
						err = backend.ApplyBatch(batch)
					}
				}
				if err != nil {
					b.Fatal(err)
				}
				root, ok := backend.Node(1)
				if !ok || len(root.Children) != rows {
					b.Fatal("actual transaction lost retained rows")
				}
				backend.Close()
			}
		})
	}
	staged, streamed := measure(false), measure(true)
	saved := staged.AllocedBytesPerOp() - streamed.AllocedBytesPerOp()
	// Three operations per row otherwise need a wide Operation backing array.
	// Retained nodes and the rollback journal are required in both paths.
	if minimum := int64(rows * 256); saved < minimum {
		t.Fatalf("streaming %d rows saves %d allocation bytes over staged DecodeBatch/ApplyBatch; require at least %d", rows, saved, minimum)
	}
	t.Logf("wire_bytes=%d staged_allocated=%d streamed_allocated=%d saved=%d", len(source), staged.AllocedBytesPerOp(), streamed.AllocedBytesPerOp(), saved)
}
