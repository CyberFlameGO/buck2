/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under both the MIT license found in the
 * LICENSE-MIT file in the root directory of this source tree and the Apache
 * License, Version 2.0 found in the LICENSE-APACHE file in the root directory
 * of this source tree.
 */

use std::ffi::OsString;

use gazebo::dupe::Dupe;
use once_cell::sync::OnceCell;

#[derive(Copy, Clone, Dupe, Debug)]
pub struct EnvironmentInheritance {
    clear: bool,
    values: &'static [(&'static str, OsString)],
    exclusions: &'static [&'static str],
}

impl EnvironmentInheritance {
    pub fn test_allowlist() -> Self {
        // This is made to be a list of lists in case we want to include lists from different
        // provenances, like the test_env_allowlist::ENV_LIST_HACKY.
        let allowlists;

        #[cfg(fbcode_build)]
        {
            allowlists = &[test_env_allowlist::LEGACY_TESTPILOT_ALLOW_LIST];
        }

        #[cfg(not(fbcode_build))]
        {
            // NOTE: Not much thought has gone into this, since we don't actually use this
            // codepath. In theory we should probably omit PATH here, but we're likely to want
            // to use this for e.g. genrules and that will *not* be practical...
            allowlists = &[&["PATH", "USER", "LOGNAME", "HOME", "TMPDIR"]];
        }

        // We create this *once* since getenv is actually not cheap (being O(n) of the environment
        // size).
        static TEST_CELL: OnceCell<Vec<(&'static str, OsString)>> = OnceCell::new();

        let values = TEST_CELL.get_or_init(|| {
            let mut ret = Vec::new();
            for list in allowlists.iter() {
                for key in list.iter() {
                    if let Some(value) = std::env::var_os(key) {
                        ret.push((*key, value));
                    }
                }
            }
            ret
        });

        Self {
            clear: true,
            values,
            exclusions: &[],
        }
    }

    /// Exclude some vars that are known to cause issues. In an ideal world we should do a
    /// migration to lock this down everywhere.
    pub fn local_command_exclusions() -> Self {
        Self {
            clear: false,
            values: &[],
            exclusions: &[
                "PYTHONPATH",
                "PYTHONHOME",
                "PYTHONSTARTUP",
                "LD_LIBRARY_PATH",
                "LD_PRELOAD",
            ],
        }
    }

    pub fn empty() -> Self {
        Self {
            values: &[],
            exclusions: &[],
            clear: true,
        }
    }

    pub fn values(&self) -> impl Iterator<Item = (&'static str, &'static OsString)> {
        self.values.iter().map(|(k, v)| (*k, v))
    }

    pub fn exclusions(&self) -> impl Iterator<Item = &'static str> {
        self.exclusions.iter().copied()
    }

    pub fn clear(&self) -> bool {
        self.clear
    }
}
