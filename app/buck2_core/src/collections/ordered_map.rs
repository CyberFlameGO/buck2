/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under both the MIT license found in the
 * LICENSE-MIT file in the root directory of this source tree and the Apache
 * License, Version 2.0 found in the LICENSE-APACHE file in the root directory
 * of this source tree.
 */

use std::hash::Hash;

use starlark_map::small_map;
use starlark_map::small_map::SmallMap;
use starlark_map::Equivalent;

/// Wrapper for `SmallMap` which consideres map equal if iteration order is equal.
#[derive(Debug, Default)]
pub struct OrderedMap<K, V>(SmallMap<K, V>);

impl<K, V> OrderedMap<K, V> {
    pub fn new() -> OrderedMap<K, V> {
        OrderedMap(SmallMap::new())
    }

    pub fn with_capacity(capacity: usize) -> OrderedMap<K, V> {
        OrderedMap(SmallMap::with_capacity(capacity))
    }

    pub fn len(&self) -> usize {
        self.0.len()
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    pub fn iter(&self) -> impl ExactSizeIterator<Item = (&K, &V)> {
        self.0.iter()
    }

    pub fn get<Q>(&self, k: &Q) -> Option<&V>
    where
        Q: Hash + Equivalent<K> + ?Sized,
    {
        self.0.get(k)
    }

    pub fn insert(&mut self, k: K, v: V) -> Option<V>
    where
        K: Hash + Eq,
    {
        self.0.insert(k, v)
    }

    pub fn entry(&mut self, k: K) -> small_map::Entry<'_, K, V>
    where
        K: Hash + Eq,
    {
        self.0.entry(k)
    }
}

impl<K: Eq, V: Eq> PartialEq for OrderedMap<K, V> {
    fn eq(&self, other: &Self) -> bool {
        self.0.eq_ordered(&other.0)
    }
}

impl<K: Eq, V: Eq> Eq for OrderedMap<K, V> {}

impl<K: Hash, V: Hash> Hash for OrderedMap<K, V> {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        self.0.hash_ordered(state)
    }
}