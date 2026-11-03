//go:build !race

package luimygo

import (
	"fmt"
	"strings"
	"testing"
)

// Race instrumentation adds substantial per-field allocations. This budget
// measures the production decoder; behavioral tests also run under -race.
func decodeAllocationPayload(rows int) []byte {
	var data strings.Builder
	data.WriteString(`{"generation":1,"ops":[`)
	for i := 0; i < rows; i++ {
		if i > 0 {
			data.WriteByte(',')
		}
		fmt.Fprintf(&data, `{"op":"create-node","id":%d,"kind":"list-item"},{"op":"set-prop","id":%d,"property":"text","value":"row %d"},{"op":"insert-child","parent":1,"child":%d,"index":%d}`, i+2, i+2, i, i+2, i)
	}
	data.WriteString(`]}`)
	return []byte(data.String())
}

func TestDecodeBatchAllocationBudget(t *testing.T) {
	data := decodeAllocationPayload(1000)
	result := testing.Benchmark(func(b *testing.B) {
		for b.Loop() {
			batch, err := DecodeBatch(data)
			if err != nil || len(batch.Ops) != 3000 {
				b.Fatalf("actual public decoding failed: %d ops: %v", len(batch.Ops), err)
			}
		}
	})
	// Bound decoded allocation amplification, with room for stdlib variation.
	// This catches per-operation parse buffers, maps and repeated Ops growth.
	if got, limit := result.AllocedBytesPerOp(), int64(len(data))*8; got > limit {
		t.Fatalf("DecodeBatch allocates %d bytes for %d wire bytes; budget %d (8x wire)", got, len(data), limit)
	}
	t.Logf("wire_bytes=%d allocated_bytes=%d allocs=%d", len(data), result.AllocedBytesPerOp(), result.AllocsPerOp())
}

func BenchmarkDecodeBatchVirtualRows(b *testing.B) {
	data := decodeAllocationPayload(10000)
	b.SetBytes(int64(len(data)))
	b.ReportAllocs()
	b.ResetTimer()
	for b.Loop() {
		if _, err := DecodeBatch(data); err != nil {
			b.Fatal(err)
		}
	}
}
