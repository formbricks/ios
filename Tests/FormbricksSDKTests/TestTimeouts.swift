import Foundation

/// The cap on waiting for an event that is already on its way: a main-queue hop, a background
/// completion, a timer that is due.
///
/// CI's iOS simulator freezes the test process for seconds at a time while WebKit cold-launches
/// its helper processes for the WebView tests. The GPU process alone took 57s and 108s to launch
/// in two runs. A 1–5s cap failed tests whose code was fine. The wait still returns as soon as
/// the event arrives, so a passing test is no slower.
///
/// This is only for waits on a real event. A test must never sleep and then check, because a
/// stall lets the sleep finish first.
let eventTimeout: TimeInterval = 30
