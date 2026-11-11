//! Adapter-only sparse update measurements; no native engine or frame timing.
use lui_nsh::{
    contract,
    store::{Node, Store},
    wire::{Batch, Operation},
};
use serde_json::json;
use std::{hint::black_box, sync::Arc, time::Instant};

struct Options {
    samples: usize,
    warmup: usize,
    reference: String,
}

impl Options {
    fn parse() -> Result<Self, String> {
        let mut result = Self {
            samples: 2_000,
            warmup: 200,
            reference: "local-reference".into(),
        };
        let mut arguments = std::env::args().skip(1);
        while let Some(argument) = arguments.next() {
            let value = arguments
                .next()
                .ok_or_else(|| format!("missing value for {argument}"))?;
            match argument.as_str() {
                "--samples" => result.samples = value.parse().map_err(|_| "invalid samples")?,
                "--warmup" => result.warmup = value.parse().map_err(|_| "invalid warmup")?,
                "--reference" => result.reference = value,
                _ => return Err(format!("unknown option {argument}")),
            }
        }
        if result.samples == 0 {
            return Err("samples must be positive".into());
        }
        Ok(result)
    }
}

fn batch(generation: u64, ops: Vec<Operation>) -> Batch {
    let mut batch = Batch::default();
    batch.generation = generation;
    batch.ops = ops;
    batch
}

fn fixture(count: u64) -> Result<Store, String> {
    let mut ops = Vec::with_capacity((count * 3) as usize);
    ops.push(Operation::CreateNode {
        id: 1,
        kind: "column".into(),
    });
    for id in 2..=count {
        ops.push(Operation::CreateNode {
            id,
            kind: "text".into(),
        });
        ops.push(Operation::SetProp {
            id,
            property: "text".into(),
            value: json!("initial"),
        });
        ops.push(Operation::InsertChild {
            parent: 1,
            child: id,
            index: (id - 2) as usize,
        });
    }
    let mut store = Store::default();
    // Keep ordinary sample generations at a constant five decimal digits.
    store.apply_snapshot(batch(10_000, ops))?;
    store.set_root(1)?;
    assert_eq!(store.nodes.len(), count as usize);
    Ok(store)
}

#[derive(Default)]
struct Samples {
    decode: Vec<u128>,
    final_validation: Vec<u128>,
    transaction: Vec<u128>,
}

impl Samples {
    fn report(mut self, retained: u64, operations: usize) {
        for (stage, values) in [
            ("decode", &mut self.decode),
            ("standalone_final_validation", &mut self.final_validation),
            ("transaction_including_validation", &mut self.transaction),
        ] {
            values.sort_unstable();
            let percentile = |percent: usize| {
                let rank = (values.len() * percent).div_ceil(100);
                values[rank.saturating_sub(1)] as f64 / 1_000.0
            };
            println!(
                "{retained},{operations},{stage},{},{:.3},{:.3},{:.3}",
                values.len(),
                percentile(50),
                percentile(95),
                percentile(99)
            );
        }
    }
}

fn qualify(retained: u64, operations: usize, options: &Options) -> Result<(), String> {
    let mut store = fixture(retained)?;
    let root = store.nodes[&1].clone();
    let unrelated = store.nodes[&retained].clone();
    let ids: Vec<u64> = (2..2 + operations as u64).collect();
    let mut samples = Samples::default();
    for sample in 0..options.warmup + options.samples {
        let value = if sample % 2 == 0 {
            "edited-a"
        } else {
            "edited-b"
        };
        let ops = ids
            .iter()
            .map(|&id| Operation::SetProp {
                id,
                property: "text".into(),
                value: json!(value),
            })
            .collect();
        // Serialization and preparing final-node validator inputs are outside
        // every timer. These are fresh per sample, rather than decoded caches.
        let json = serde_json::to_string(&batch(store.generation + 1, ops))
            .map_err(|error| error.to_string())?;
        let final_nodes: Vec<Node> = ids
            .iter()
            .map(|id| {
                let mut node = store.nodes[id].as_ref().clone();
                node.props.insert("text".into(), json!(value));
                node
            })
            .collect();

        let start = Instant::now();
        let decoded = Batch::decode(black_box(&json))?;
        let decode = start.elapsed().as_nanos();

        let start = Instant::now();
        for node in &final_nodes {
            black_box(contract::validate_node(black_box(node)))?;
        }
        let final_validation = start.elapsed().as_nanos();

        let start = Instant::now();
        let changes = black_box(store.apply(black_box(decoded)))?;
        let transaction = start.elapsed().as_nanos();

        // Assertions are untimed and inspect only touched nodes and fixed
        // unrelated witnesses. No complete-map scan occurs in a sample.
        assert_eq!(changes.updated.len(), operations);
        assert!(changes.updated.iter().copied().eq(ids.iter().copied()));
        assert!(changes.removed.is_empty());
        assert_eq!(store.nodes.len(), retained as usize);
        assert!(Arc::ptr_eq(&root, &store.nodes[&1]));
        assert!(Arc::ptr_eq(&root.children, &store.nodes[&1].children));
        assert!(Arc::ptr_eq(&unrelated, &store.nodes[&retained]));
        for node in &final_nodes {
            let current = &store.nodes[&node.id];
            assert_eq!(current.string("text"), value);
            assert_eq!(current.incarnation, node.incarnation);
            assert!(Arc::ptr_eq(&current.children, &node.children));
        }
        if sample >= options.warmup {
            samples.decode.push(decode);
            samples.final_validation.push(final_validation);
            samples.transaction.push(transaction);
        }
    }
    samples.report(retained, operations);
    Ok(())
}

fn main() -> Result<(), String> {
    let options = Options::parse()?;
    if cfg!(debug_assertions) {
        return Err("run this qualification with cargo run --release".into());
    }
    println!("# Reference: {}", options.reference);
    println!(
        "# Target: {}-{}",
        std::env::consts::ARCH,
        std::env::consts::OS
    );
    println!("# Warmup per case: {}", options.warmup);
    println!("# Timing unit: microseconds; nearest-rank percentiles");
    println!("# Standalone validation overlaps validation inside transaction; do not add stages.");
    println!(
        "# Excludes binding publication, NSH commit/layout, native frames and application work."
    );
    println!("retained_nodes,operations,stage,samples,median_us,p95_us,p99_us");
    for operations in [1, 100] {
        for retained in [1_000, 100_000] {
            qualify(retained, operations, &options)?;
        }
    }
    Ok(())
}
