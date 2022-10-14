/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under both the MIT license found in the
 * LICENSE-MIT file in the root directory of this source tree and the Apache
 * License, Version 2.0 found in the LICENSE-APACHE file in the root directory
 * of this source tree.
 */

use std::path::PathBuf;

use buck2_common::connection_endpoint::ConnectionType;

use crate::daemon::tcp_or_unix_listener::TcpOrUnixListener;

pub fn create_listener(daemon_dir: PathBuf) -> anyhow::Result<(ConnectionType, TcpOrUnixListener)> {
    #[cfg(unix)]
    {
        crate::daemon::daemon_unix::create_listener(daemon_dir)
    }
    #[cfg(windows)]
    {
        drop(daemon_dir);
        crate::daemon::daemon_tcp::create_listener()
    }
}