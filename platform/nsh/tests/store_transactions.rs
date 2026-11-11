use lui_nsh::{
    store::Store,
    wire::{Batch, Operation},
};
use serde_json::json;
use std::sync::Arc;

fn batch(generation: u64, ops: Vec<Operation>) -> Batch {
    let mut result = Batch::default();
    result.generation = generation;
    result.ops = ops;
    result
}
fn create(id: u64, kind: &str) -> Operation {
    Operation::CreateNode {
        id,
        kind: kind.into(),
    }
}
fn insert(parent: u64, child: u64, index: usize) -> Operation {
    Operation::InsertChild {
        parent,
        child,
        index,
    }
}
fn text(id: u64, value: &str) -> Operation {
    Operation::SetProp {
        id,
        property: "text".into(),
        value: json!(value),
    }
}

#[test]
fn rejected_transaction_preserves_generation_identity_and_existing_nodes() {
    let mut store = Store::default();
    store
        .apply(batch(
            1,
            vec![
                create(1, "column"),
                create(2, "text"),
                text(2, "original"),
                insert(1, 2, 0),
            ],
        ))
        .unwrap();
    store.set_root(1).unwrap();
    let before = store.nodes.clone();
    assert!(
        store
            .apply(batch(2, vec![create(3, "text"), insert(1, 3, 99)]))
            .is_err()
    );
    assert_eq!(store.generation, 1);
    assert_eq!(store.root(), Some(1));
    assert_eq!(store.nodes, before);
    for (id, node) in &before {
        assert!(Arc::ptr_eq(node, &store.nodes[id]));
    }
    for property in ["unknown-property", "heading-level"] {
        assert!(
            store
                .apply(batch(
                    2,
                    vec![
                        text(2, "must roll back"),
                        Operation::RemoveProp {
                            id: 2,
                            property: property.into(),
                        },
                    ],
                ))
                .is_err(),
            "invalid remove-prop {property} was accepted"
        );
        assert_eq!(store.generation, 1);
        assert!(Arc::ptr_eq(&before[&2], &store.nodes[&2]));
        assert_eq!(store.nodes[&2].string("text"), "original");
    }
    store
        .apply(batch(2, vec![create(3, "text"), insert(1, 3, 1)]))
        .unwrap();
    assert_eq!(
        store.nodes[&3].incarnation, 3,
        "failed transaction consumed an incarnation"
    );
}

#[test]
fn snapshots_accept_current_generation_and_ordinary_batches_require_the_next() {
    let mut store = Store::default();
    store
        .apply(batch(1, vec![create(1, "text"), text(1, "first")]))
        .unwrap();
    let old = store.nodes[&1].incarnation;
    assert!(store.apply(batch(3, vec![text(1, "skipped")])).is_err());
    assert!(store.apply(batch(1, vec![text(1, "stale")])).is_err());
    store
        .apply_snapshot(batch(1, vec![create(1, "text"), text(1, "snapshot")]))
        .unwrap();
    assert!(store.nodes[&1].incarnation > old);
    assert_eq!(store.nodes[&1].string("text"), "snapshot");
    store.apply(batch(2, vec![text(1, "next")])).unwrap();
    let before = store.nodes.clone();
    assert!(
        store
            .apply_snapshot(batch(1, vec![create(1, "text"), text(1, "obsolete")]))
            .is_err()
    );
    assert!(Arc::ptr_eq(&before[&1], &store.nodes[&1]));
    assert!(
        store
            .apply_snapshot(batch(40, vec![create(2, "unknown")]))
            .is_err()
    );
    assert_eq!(store.nodes, before);
    assert_eq!(store.generation, 2);
    store
        .apply_snapshot(batch(40, vec![create(1, "text"), text(1, "recovered")]))
        .unwrap();
    assert_eq!(store.generation, 40);
    assert_eq!(store.nodes[&1].string("text"), "recovered");
    store.apply(batch(41, vec![text(1, "following")])).unwrap();
}

#[test]
fn moving_children_checks_cycles_and_detach_is_idempotent() {
    let mut store = Store::default();
    store
        .apply(batch(
            1,
            vec![
                create(1, "column"),
                create(2, "column"),
                create(3, "text"),
                text(3, "child"),
                insert(1, 2, 0),
                insert(2, 3, 0),
            ],
        ))
        .unwrap();
    store.set_root(1).unwrap();
    let before = store.nodes.clone();
    assert!(store.apply(batch(2, vec![insert(2, 1, 1)])).is_err());
    assert_eq!(store.nodes, before);
    store
        .apply(batch(2, vec![Operation::DetachSubtree { id: 2 }]))
        .unwrap();
    assert_eq!(store.nodes.len(), 1);
    assert!(store.nodes[&1].children.is_empty());
    store
        .apply(batch(3, vec![Operation::DetachSubtree { id: 2 }]))
        .unwrap();
    assert_eq!(store.root(), Some(1));
    store
        .apply(batch(4, vec![Operation::DetachSubtree { id: 1 }]))
        .unwrap();
    assert!(store.nodes.is_empty());
    assert_eq!(store.root(), None);
}

#[test]
fn wire_keeps_large_ocaml_ids_exact_and_rejects_ids_outside_the_ocaml_range() {
    let id = (1_u64 << 53) + 31;
    let json =
        format!(r#"{{"generation":1,"ops":[{{"op":"create-node","id":{id},"kind":"text"}}]}}"#);
    let mut store = Store::default();
    store.apply(Batch::decode(&json).unwrap()).unwrap();
    assert!(store.nodes.contains_key(&id));
    assert!(
        store
            .apply(batch(2, vec![create(1_u64 << 62, "text")]))
            .is_err()
    );
    assert_eq!(store.generation, 1);
    assert!(
        store
            .apply_snapshot(batch(1_u64 << 62, vec![create(1, "text")]))
            .is_err()
    );
    assert_eq!(store.generation, 1);
    assert!(store.nodes.contains_key(&id));
}

#[test]
fn wire_defaults_unknown_fields_and_duplicate_field_policy_are_explicit() {
    let mut store = Store::default();
    let empty = Batch::decode(r#"{"generation":1,"future":{"values":[1,"two"]}}"#).unwrap();
    assert!(empty.ops.is_empty());
    store.apply(empty).unwrap();
    let missing_generation = Batch::decode(r#"{"ops":[]}"#).unwrap();
    assert_eq!(missing_generation.generation, 0);
    assert!(store.apply(missing_generation).is_err());
    assert_eq!(store.generation, 1);
    let created = Batch::decode(
        r#"{"generation":2,"ops":[{"op":"create-node","id":1,"kind":"text","future":true}]}"#,
    )
    .unwrap();
    store.apply(created).unwrap();
    assert!(store.nodes.contains_key(&1));
    for malformed in [
        r#"{"generation":3,"generation":4,"ops":[]}"#,
        r#"{"generation":3,"ops":[{"op":"drop-node","id":1,"id":9}]}"#,
        r#"{"generation":3,"ops":[{"op":"future-operation"}]}"#,
    ] {
        assert!(Batch::decode(malformed).is_err());
    }
    assert_eq!(store.generation, 2);
    assert!(store.nodes.contains_key(&1));
}

#[test]
fn sparse_edit_keeps_unrelated_nodes_shared() {
    let mut store = Store::default();
    let ops = (1..=10_000)
        .flat_map(|id| [create(id, "text"), text(id, "before")])
        .collect();
    store.apply(batch(1, ops)).unwrap();
    let unaffected = store.nodes[&9_999].clone();
    let changes = store.apply(batch(2, vec![text(5, "after")])).unwrap();
    assert_eq!(changes.updated.into_iter().collect::<Vec<_>>(), vec![5]);
    assert!(changes.removed.is_empty());
    assert!(Arc::ptr_eq(&unaffected, &store.nodes[&9_999]));
}

#[test]
fn container_property_edits_share_the_existing_child_sequence() {
    for count in [1_000, 100_000] {
        let mut store = Store::default();
        let mut ops = Vec::with_capacity(1 + count * 2);
        ops.push(create(1, "column"));
        for index in 0..count {
            let id = index as u64 + 2;
            ops.push(create(id, "text"));
            ops.push(insert(1, id, index));
        }
        store.apply(batch(1, ops)).unwrap();
        let children = store.nodes[&1].children.clone();
        let unaffected = store.nodes[&(count as u64 + 1)].clone();
        let changes = store
            .apply(batch(
                2,
                vec![Operation::SetProp {
                    id: 1,
                    property: "opacity".into(),
                    value: json!(0.5),
                }],
            ))
            .unwrap();
        assert_eq!(changes.updated.into_iter().collect::<Vec<_>>(), [1]);
        assert!(Arc::ptr_eq(&children, &store.nodes[&1].children));
        assert!(Arc::ptr_eq(&unaffected, &store.nodes[&(count as u64 + 1)]));
        store
            .apply(batch(
                3,
                vec![Operation::RemoveChild {
                    parent: 1,
                    child: 2,
                }],
            ))
            .unwrap();
        assert_eq!(children.len(), count);
        assert_eq!(children[0], 2);
        assert_eq!(store.nodes[&1].children.len(), count - 1);
        assert_eq!(store.nodes[&1].children[0], 3);
    }
}
