/*
 * Copyright 2018 The Starlark in Rust Authors.
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// TODO(nga): also enable if cargo build and nightly.
#[cfg(rust_nightly)]
pub(crate) use std::intrinsics::likely;
#[cfg(rust_nightly)]
pub(crate) use std::intrinsics::unlikely;

#[cfg(not(rust_nightly))]
#[inline]
pub(crate) fn likely(b: bool) -> bool {
    b
}

#[cfg(not(rust_nightly))]
#[inline]
pub(crate) fn unlikely(b: bool) -> bool {
    b
}
