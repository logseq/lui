//go:build !race

package luimygo

import (
	"fmt"
	"runtime"
	"testing"
)

func TestBackendMemoryBulkDetachAllocationBudget(t *testing.T) {
	for _, count := range []int{10_000, 100_000} {
		t.Run(fmt.Sprint(count), func(t *testing.T) {
			b := backendMemoryTree(t, count)
			defer b.Close()
			batch := Batch{Generation: 2, Ops: []Operation{{Op: "detach-subtree", ID: 1}}}
			var before, after runtime.MemStats
			runtime.ReadMemStats(&before)
			err := b.ApplyBatch(batch)
			runtime.ReadMemStats(&after)
			if err != nil {
				t.Fatal(err)
			}
			allocations, allocatedBytes := after.Mallocs-before.Mallocs, after.TotalAlloc-before.TotalAlloc
			t.Logf("detach %d rows: %d allocations, %d bytes", count, allocations, allocatedBytes)
			// The rollback journal grows by map groups, not a fresh property
			// map for every node that the transaction only deletes.
			if allocations > uint64(count/8+128) {
				t.Errorf("bulk deletion allocated %d objects; budget %d", allocations, count/8+128)
			}
			if allocatedBytes > uint64(count)*512+1<<20 {
				t.Errorf("bulk deletion allocated %d bytes; budget %d", allocatedBytes, uint64(count)*512+1<<20)
			}
			if b.Generation() != 2 || len(b.Roots()) != 0 {
				t.Fatal("bulk deletion did not remove the retained tree")
			}
		})
	}
}

func BenchmarkBackendMemoryAppendRows(b *testing.B) {
	for _, count := range []int{10_000, 100_000} {
		b.Run(fmt.Sprint(count), func(b *testing.B) {
			creates := make([]Operation, 0, count+1)
			creates = append(creates, create(1, "column"))
			inserts := make([]Operation, 0, count)
			for i := range count {
				id := int64(i + 2)
				creates = append(creates, create(id, "text"))
				inserts = append(inserts, insert(1, id, i))
			}
			b.ReportAllocs()
			b.ResetTimer()
			for range b.N {
				b.StopTimer()
				backend := New(Config{})
				if err := backend.ApplyBatch(Batch{Generation: 1, Ops: creates}); err != nil {
					b.Fatal(err)
				}
				b.StartTimer()
				if err := backend.ApplyBatch(Batch{Generation: 2, Ops: inserts}); err != nil {
					b.Fatal(err)
				}
				b.StopTimer()
				if node, _ := backend.Node(1); len(node.Children) != count {
					b.Fatal("lost inserted rows")
				}
				backend.Close()
				b.StartTimer()
			}
		})
	}
}
