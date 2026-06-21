import AppKit
import ApplicationServices
import CoreGraphics
import Testing
@testable import window_manager

@Suite("Window filtering")
struct WindowFilterTests {
    private let filter = WindowFilter(ownPID: 999)

    // MARK: - CoreGraphics-level rules

    @Test("Ordinary layer-0 windows are accepted")
    func acceptsNormalWindow() {
        #expect(filter.allowsCGWindow(
            layer: 0,
            alpha: 1,
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600)
        ))
    }

    @Test("Menu-bar and desktop layers are rejected")
    func rejectsNonZeroLayers() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        // 24 = menu bar, 20 = Dock, -2147483603 = desktop icons.
        for layer in [24, 20, 25, 1_000, -2_147_483_603] {
            #expect(!filter.allowsCGWindow(layer: layer, alpha: 1, bounds: bounds))
        }
    }

    @Test("Transparent helper windows are rejected")
    func rejectsTransparentWindows() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(!filter.allowsCGWindow(layer: 0, alpha: 0, bounds: bounds))
        #expect(!filter.allowsCGWindow(layer: 0, alpha: 0.01, bounds: bounds))
        #expect(filter.allowsCGWindow(layer: 0, alpha: 0.5, bounds: bounds))
    }

    @Test("Tiny decoration windows are rejected")
    func rejectsTinyWindows() {
        #expect(!filter.allowsCGWindow(layer: 0, alpha: 1, bounds: CGRect(x: 0, y: 0, width: 1, height: 1)))
        #expect(!filter.allowsCGWindow(layer: 0, alpha: 1, bounds: CGRect(x: 0, y: 0, width: 800, height: 10)))
    }

    // MARK: - Accessibility-level rules

    @Test("Standard windows are accepted, including untitled ones")
    func acceptsStandardWindows() {
        #expect(filter.allowsAXWindow(
            subrole: kAXStandardWindowSubrole as String,
            title: "GitHub",
            isMinimized: false,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        ))
        #expect(filter.allowsAXWindow(
            subrole: kAXStandardWindowSubrole as String,
            title: "",
            isMinimized: false,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        ))
    }

    @Test("Minimised windows bypass the geometry rule")
    func acceptsMinimizedWithoutGeometry() {
        // A minimised window reports a zero frame; the old on-screen-only
        // enumeration dropped these entirely.
        #expect(filter.allowsAXWindow(
            subrole: kAXStandardWindowSubrole as String,
            title: "Downloads",
            isMinimized: true,
            frame: .zero
        ))
    }

    @Test("Sheets, popovers and floating panels are rejected")
    func rejectsNonWindowSubroles() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        for subrole in ["AXUnknown", "AXFloatingWindow", "AXSheet", "AXDrawer"] {
            #expect(!filter.allowsAXWindow(subrole: subrole, title: "Anything", isMinimized: false, frame: frame))
        }
    }

    @Test("Dialogs count only when titled")
    func conditionalDialogs() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let subrole = kAXDialogSubrole as String
        #expect(filter.allowsAXWindow(subrole: subrole, title: "Save As", isMinimized: false, frame: frame))
        #expect(!filter.allowsAXWindow(subrole: subrole, title: "  ", isMinimized: false, frame: frame))
    }

    @Test("Subrole-less windows count only when titled")
    func requiresTitleWithoutSubrole() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        #expect(filter.allowsAXWindow(subrole: nil, title: "Editor", isMinimized: false, frame: frame))
        #expect(!filter.allowsAXWindow(subrole: nil, title: "", isMinimized: false, frame: frame))
    }

    @Test("Small non-minimised windows are rejected regardless of subrole")
    func rejectsSmallAXWindows() {
        #expect(!filter.allowsAXWindow(
            subrole: kAXStandardWindowSubrole as String,
            title: "Tiny",
            isMinimized: false,
            frame: CGRect(x: 0, y: 0, width: 10, height: 10)
        ))
    }

    // MARK: - Process rules

    @Test("Every system UI surface named in the brief is excluded")
    func excludesSystemProcesses() {
        let required = [
            "com.apple.dock",                 // Dock
            "com.apple.controlcenter",        // Control Center
            "com.apple.notificationcenterui", // Notification Center
            "com.apple.Spotlight",            // Spotlight
            "com.apple.loginwindow",          // LoginWindow
            "com.apple.WindowManager"         // Stage Manager
        ]
        for bundleID in required {
            #expect(
                WindowFilter.excludedBundleIdentifiers.contains(bundleID),
                "\(bundleID) must be excluded"
            )
        }
    }

    @Test("The switcher never lists its own windows")
    func excludesOwnProcess() {
        // `allowsApplication` short-circuits on PID before touching any other
        // property, so the running test process stands in for the app itself.
        let selfFilter = WindowFilter(ownPID: ProcessInfo.processInfo.processIdentifier)
        #expect(!selfFilter.allowsApplication(NSRunningApplication.current))
    }

    @Test("Exclusions are keyed on bundle identifier, not localised name")
    func exclusionsAreLocaleIndependent() {
        // The original filter listed "Control Centre", which only matched in
        // en-GB. Guard against a regression to name-based matching.
        #expect(!WindowFilter.excludedProcessNames.contains("Control Centre"))
        #expect(!WindowFilter.excludedProcessNames.contains("Control Center"))
        #expect(WindowFilter.excludedBundleIdentifiers.contains("com.apple.controlcenter"))
    }
}
