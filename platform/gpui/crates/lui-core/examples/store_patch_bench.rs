//! Store-only single-property patch benchmark; run this example in release mode.

use lui_core::{
    store::Store,
    wire::{Batch, Op, Value},
};
use std::time::Instant;
fn main() {
    for count in [100, 1000, 10000, 50000] {
        let mut ops = Vec::new();
        ops.push(Op::CreateNode {
            id: 1,
            kind: "root".into(),
        });
        for id in 2..count + 2 {
            ops.push(Op::CreateNode {
                id,
                kind: "text".into(),
            });
            ops.push(Op::SetProp {
                id,
                property: "text".into(),
                value: Value::Str("Example block contents, references and formatting".repeat(4)),
            });
            ops.push(Op::SetProp {
                id,
                property: "style-class".into(),
                value: Value::Str("text-sm px-2 py-1 bg-gray-100".into()),
            });
            ops.push(Op::InsertChild {
                parent: 1,
                child: id,
                index: id - 2,
            });
        }
        let mut store = Store::default();
        store.apply(&Batch { generation: 1, ops }).unwrap();
        let mut patch = Batch {
            generation: 2,
            ops: vec![Op::SetProp {
                id: 2,
                property: "text".into(),
                value: Value::Str("changed".into()),
            }],
        };
        for _ in 0..5 {
            store.apply(&patch).unwrap();
        }
        let started = Instant::now();
        for _ in 0..100 {
            patch.generation += 1;
            std::hint::black_box(store.apply(&patch).unwrap());
        }
        println!(
            "nodes={} single_prop_apply_us={:.1}",
            count,
            started.elapsed().as_secs_f64() * 1000000.0 / 100.0
        );
    }
}
