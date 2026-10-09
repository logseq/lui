//! Batch-local indexed child order. A parent publishes its Vec only once.
use std::collections::BTreeMap;

struct Entry {
    id: i64,
    priority: u64,
    left: Option<usize>,
    right: Option<usize>,
    parent: Option<usize>,
    size: usize,
}

pub(crate) struct Order {
    entries: Vec<Entry>,
    handles: BTreeMap<i64, usize>,
    root: Option<usize>,
}

impl Order {
    pub(crate) fn new(ids: &[i64]) -> Self {
        let mut order = Self {
            entries: Vec::with_capacity(ids.len()),
            handles: BTreeMap::new(),
            root: None,
        };
        for &id in ids {
            order.insert(order.len(), id);
        }
        order
    }
    fn size(&self, node: Option<usize>) -> usize {
        node.map_or(0, |n| self.entries[n].size)
    }
    pub(crate) fn len(&self) -> usize {
        self.size(self.root)
    }
    fn parent(&mut self, child: Option<usize>, parent: Option<usize>) {
        if let Some(child) = child {
            self.entries[child].parent = parent;
        }
    }
    fn update(&mut self, node: usize) {
        let left = self.entries[node].left;
        let right = self.entries[node].right;
        self.parent(left, Some(node));
        self.parent(right, Some(node));
        self.entries[node].size = 1 + self.size(left) + self.size(right);
    }
    fn merge(&mut self, left: Option<usize>, right: Option<usize>) -> Option<usize> {
        let result = match (left, right) {
            (None, other) | (other, None) => other,
            (Some(left), Some(right))
                if self.entries[left].priority <= self.entries[right].priority =>
            {
                let tail = self.entries[left].right;
                self.entries[left].right = self.merge(tail, Some(right));
                self.update(left);
                Some(left)
            }
            (Some(left), Some(right)) => {
                let head = self.entries[right].left;
                self.entries[right].left = self.merge(Some(left), head);
                self.update(right);
                Some(right)
            }
        };
        self.parent(result, None);
        result
    }
    fn split(&mut self, root: Option<usize>, index: usize) -> (Option<usize>, Option<usize>) {
        let Some(node) = root else {
            return (None, None);
        };
        let size = self.size(self.entries[node].left);
        let result = if index <= size {
            let (left, middle) = self.split(self.entries[node].left, index);
            self.entries[node].left = middle;
            self.update(node);
            (left, Some(node))
        } else {
            let (middle, right) = self.split(self.entries[node].right, index - size - 1);
            self.entries[node].right = middle;
            self.update(node);
            (Some(node), right)
        };
        self.parent(result.0, None);
        self.parent(result.1, None);
        result
    }
    pub(crate) fn index(&self, id: i64) -> Option<usize> {
        let mut node = *self.handles.get(&id)?;
        let mut index = self.size(self.entries[node].left);
        while let Some(parent) = self.entries[node].parent {
            if self.entries[parent].right == Some(node) {
                index += 1 + self.size(self.entries[parent].left);
            }
            node = parent;
        }
        Some(index)
    }
    fn insert_entry(&mut self, index: usize, node: usize) {
        self.entries[node].left = None;
        self.entries[node].right = None;
        self.entries[node].parent = None;
        self.entries[node].size = 1;
        let (left, right) = self.split(self.root, index);
        let middle = self.merge(left, Some(node));
        self.root = self.merge(middle, right);
        self.handles.insert(self.entries[node].id, node);
    }
    pub(crate) fn insert(&mut self, index: usize, id: i64) {
        assert!(index <= self.len() && !self.handles.contains_key(&id));
        let mut priority = (id as u64).wrapping_add(0x9e3779b97f4a7c15);
        priority = (priority ^ (priority >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
        priority = (priority ^ (priority >> 27)).wrapping_mul(0x94d049bb133111eb);
        priority ^= priority >> 31;
        let node = self.entries.len();
        self.entries.push(Entry {
            id,
            priority,
            left: None,
            right: None,
            parent: None,
            size: 1,
        });
        self.insert_entry(index, node);
    }
    pub(crate) fn remove(&mut self, id: i64) -> bool {
        let Some(index) = self.index(id) else {
            return false;
        };
        let (left, tail) = self.split(self.root, index);
        let (_, right) = self.split(tail, 1);
        self.root = self.merge(left, right);
        self.handles.remove(&id);
        true
    }
    pub(crate) fn move_to(&mut self, id: i64, index: usize) {
        let node = self.handles[&id];
        assert!(index < self.len());
        assert!(self.remove(id));
        self.insert_entry(index, node);
    }
    pub(crate) fn ids(&self) -> Vec<i64> {
        let mut result = Vec::with_capacity(self.len());
        let mut stack = Vec::new();
        let mut current = self.root;
        loop {
            if let Some(node) = current {
                stack.push(node);
                current = self.entries[node].left;
            } else if let Some(node) = stack.pop() {
                result.push(self.entries[node].id);
                current = self.entries[node].right;
            } else {
                break;
            }
        }
        result
    }
}
