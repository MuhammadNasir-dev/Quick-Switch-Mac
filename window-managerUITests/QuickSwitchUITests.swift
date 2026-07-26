import XCTest

/// UI tests are intentionally absent.
///
/// QuickSwitch is an `LSUIElement` background agent: no Dock icon, no ordinary
/// window, and its only interactive surface is a non-activating `NSPanel`
/// driven by a system-wide `CGEventTap`. XCUITest cannot drive any of that:
///
/// * `XCUIApplication().launch()` has no window to attach to, so snapshotting
///   fails with "Lost connection to the application";
/// * the switcher panel appears only in response to a global hotkey, which the
///   test runner cannot synthesise without Accessibility trust of its own;
/// * terminating an accessory app through XCUITest is unreliable — that is what
///   made the Xcode template's `testLaunchPerformance` hang for 84 seconds
///   before failing.
///
/// The template stubs that shipped in this target asserted nothing and failed
/// for those reasons, so they were removed rather than left permanently red.
/// This class exists only so the bundle has an executable to load.
///
/// Behaviour is covered by `window-managerTests`, which exercises the window
/// filter, enumerator, fuzzy matcher, MRU ordering, selection, layout geometry
/// and menu-header rendering directly — no window server required.
final class QuickSwitchUITests: XCTestCase {}
