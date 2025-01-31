/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under both the MIT license found in the
 * LICENSE-MIT file in the root directory of this source tree and the Apache
 * License, Version 2.0 found in the LICENSE-APACHE file in the root directory
 * of this source tree.
 */

#![feature(async_closure)]
#![feature(box_syntax)]
#![feature(try_blocks)]
#![feature(try_trait_v2)]

pub mod build_count;
pub mod cleanup_ctx;
pub mod client_cpu_tracker;
pub mod client_ctx;
pub mod command_outcome;
pub mod common;
pub mod console_interaction_stream;
pub mod daemon;
pub mod events_ctx;
pub mod exit_result;
pub mod file_tailer;
pub mod final_console;
pub mod find_certs;
pub mod manifold;
pub mod path_arg;
pub mod replayer;
pub mod stdin;
pub mod stdio;
pub mod stream_value;
pub mod streaming;
pub mod subscribers;
pub mod ticker;
pub mod verbosity;
pub mod version;
pub mod what_ran;

pub const LSP_COMMAND_NAME: &str = "lsp";
