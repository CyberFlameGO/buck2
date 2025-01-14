/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under both the MIT license found in the
 * LICENSE-MIT file in the root directory of this source tree and the Apache
 * License, Version 2.0 found in the LICENSE-APACHE file in the root directory
 * of this source tree.
 */

use crate::BuckEvent;
use crate::ControlEvent;
use crate::EventSink;

/// A Sink implementation that wraps two EventSinks and sends events to both of them.
pub struct TeeSink<A, B>(A, B);

impl<A, B> TeeSink<A, B> {
    pub fn new(a: A, b: B) -> TeeSink<A, B> {
        TeeSink(a, b)
    }
}

impl<A: EventSink, B: EventSink> EventSink for TeeSink<A, B> {
    fn send(&self, event: BuckEvent) {
        self.0.send(event.clone());
        self.1.send(event);
    }

    fn send_control(&self, control_event: ControlEvent) {
        self.0.send_control(control_event.clone());
        self.1.send_control(control_event);
    }
}
