// Spec 037 — native window smoke: the only suite that drives the REAL
// JuraDrop.app (real WKWebView, real IPC, real NSOpenPanel).
//
// Hermetic by construction: the app is launched with the debug-only
// JURADROP_OLLAMA_URL seam pointed at scripts/mock-ollama.py, so no real
// model is consulted and nothing is downloaded (FR-004).
//
// Env contract (provided by scripts/native-smoke.sh via TEST_RUNNER_*):
//   JURADROP_OLLAMA_URL        — mock endpoint base URL (required)
//   JURADROP_SMOKE_FIXTURE_DIR — temp dir containing dokument.txt (test02)
//   ZONE_TITLES_JSON           — runner-exported canonical titles (test01)
//
// All waits are bounded (FR-011) — no fixed sleeps.

import XCTest

final class NativeWindowSmokeTests: XCTestCase {
    private static let bundleId = "se.noisycricket.juradrop"
    private static let launchTimeout: TimeInterval = 30
    private static let pipelineTimeout: TimeInterval = 60
    private static let cannedResponse = "NATIV-SMOKE: sammanfattning klar."

    private var env: [String: String] { ProcessInfo.processInfo.environment }

    /// Launch the app under test with the hermetic seam, register teardown.
    private func launchJuraDrop() throws -> XCUIApplication {
        guard let mockURL = env["JURADROP_OLLAMA_URL"], !mockURL.isEmpty else {
            throw XCTSkip("JURADROP_OLLAMA_URL not set — run via scripts/native-smoke.sh")
        }
        let app = XCUIApplication(bundleIdentifier: Self.bundleId)
        app.launchEnvironment = ["JURADROP_OLLAMA_URL": mockURL]
        app.launch()
        addTeardownBlock {
            if app.state != .notRunning { app.terminate() }
        }
        return app
    }

    private func waitForWindow(_ app: XCUIApplication) {
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: Self.launchTimeout),
            "H-1: the JuraDrop window never appeared within \(Self.launchTimeout)s"
        )
    }

    // ── test00 — FR-009 probe: is the WKWebView content reachable? ───────

    func test00_probeAccessibilityExposure() throws {
        let app = try launchJuraDrop()
        waitForWindow(app)

        // Give the ready state a moment to arrive (mock reports the model
        // present, so zones should render enabled) — bounded, not a sleep.
        _ = app.staticTexts["Sammanfatta"].waitForExistence(timeout: Self.launchTimeout)

        // The dump IS the probe deliverable: inspected at T005 to decide
        // web_content_reachable vs chrome_only_fallback.
        print("===A11Y-PROBE-BEGIN===")
        print(app.debugDescription)
        print("===A11Y-PROBE-END===")

        XCTAssertGreaterThan(app.windows.count, 0, "window must exist")
    }

    // ── test01 — H-3/H-4: twelve zones + chrome in the real window ───────

    func test01_twelveZonesAndChromeRender() throws {
        guard let titlesPath = env["ZONE_TITLES_JSON"] else {
            throw XCTSkip("ZONE_TITLES_JSON not set — run via scripts/native-smoke.sh")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: titlesPath))
        let titles = try JSONDecoder().decode([String].self, from: data)
        XCTAssertEqual(titles.count, 12, "canonical title export must list twelve zones")

        let app = try launchJuraDrop()
        waitForWindow(app)

        // First title gets the long launch budget (app boot + ready state);
        // the rest are already rendered and get a short confirmation wait.
        XCTAssertTrue(
            app.staticTexts[titles[0]].waitForExistence(timeout: Self.launchTimeout),
            "zone title '\(titles[0])' not reachable in the a11y tree"
        )
        for title in titles.dropFirst() {
            XCTAssertTrue(
                app.staticTexts[title].waitForExistence(timeout: 5),
                "zone title '\(title)' not reachable in the a11y tree"
            )
        }

        // H-4 — chrome affordances (Swedish accessible labels from the app).
        XCTAssertTrue(
            app.buttons["Hjälp"].waitForExistence(timeout: 5),
            "help chrome affordance missing"
        )
        XCTAssertTrue(
            app.buttons["Inställningar"].waitForExistence(timeout: 5),
            "settings chrome affordance missing"
        )
    }

    // ── test02 — H-5/H-6: Välj fil → native picker → sidecar on disk ─────

    func test02_pickToSidecar() throws {
        guard let fixtureDir = env["JURADROP_SMOKE_FIXTURE_DIR"], !fixtureDir.isEmpty else {
            throw XCTSkip("JURADROP_SMOKE_FIXTURE_DIR not set — run via scripts/native-smoke.sh")
        }
        let fixture = URL(fileURLWithPath: fixtureDir).appendingPathComponent("dokument.txt")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixture.path),
            "runner must have created the fixture"
        )

        let app = try launchJuraDrop()
        waitForWindow(app)

        // Activate the spec-016 affordance (the a11y-drivable pick path).
        let pick = app.buttons["Välj fil för Sammanfatta"]
        XCTAssertTrue(
            pick.waitForExistence(timeout: Self.launchTimeout),
            "Välj fil affordance not reachable"
        )
        pick.click()

        // Drive the open panel via Go-to-Folder (research R5): the sheet
        // accepts a typed absolute path regardless of sidebar state.
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(
            panel.waitForExistence(timeout: 10),
            "native open panel never appeared"
        )
        app.typeKey("g", modifierFlags: [.command, .shift])
        let goto = panel.comboBoxes.firstMatch.exists
            ? panel.comboBoxes.firstMatch
            : panel.textFields.firstMatch
        XCTAssertTrue(goto.waitForExistence(timeout: 10), "Go-to-Folder field never appeared")
        goto.typeText(fixture.path)
        app.typeKey(.return, modifierFlags: [])   // accept the path
        app.typeKey(.return, modifierFlags: [])   // confirm the selection (Öppna)

        // H-6 / SC-002 — the sidecar appears next to the fixture and carries
        // the canned mock text (the pipeline genuinely ran).
        let sidecar = URL(fileURLWithPath: fixtureDir)
            .appendingPathComponent("dokument.sammanfattning.txt")
        let candidates = [
            sidecar,
            URL(fileURLWithPath: fixtureDir).appendingPathComponent("dokument.sammanfatta.txt"),
        ]
        let appeared = expectation(description: "sidecar file appears")
        let poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if candidates.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                timer.invalidate()
                appeared.fulfill()
            }
        }
        wait(for: [appeared], timeout: Self.pipelineTimeout)
        poll.invalidate()

        let found = candidates.first { FileManager.default.fileExists(atPath: $0.path) }
        let content = try String(contentsOf: XCTUnwrap(found), encoding: .utf8)
        XCTAssertTrue(
            content.contains(Self.cannedResponse),
            "sidecar must contain the canned mock response, got: \(content.prefix(200))"
        )
    }
}
