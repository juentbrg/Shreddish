import XCTest

/// Parcours par user story, IA bouchonnée (`-uitest` : store en mémoire, transport simulé).
final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"] + extra
        app.launch()
        return app
    }

    private func onboard(_ app: XCUIApplication) {
        app.buttons["acceptDisclaimer"].tap()
        let height = app.textFields["height"]
        XCTAssertTrue(height.waitForExistence(timeout: 5))
        height.tap()
        height.typeText("180")
        let weight = app.textFields["weight"]
        weight.tap()
        weight.typeText("80")
        app.buttons["computeTargets"].tap()
    }

    /// US1 : disclaimer → profil → cibles 2207 kcal (homme 30 ans, 180 cm, 80 kg, modéré, sèche).
    func testOnboardingShowsReferenceTargets() {
        let app = launch()
        onboard(app)
        let target = app.staticTexts["targetKcal"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertTrue(target.label.contains("2"), "Cible affichée : \(target.label)")
        XCTAssertTrue(target.label.replacingOccurrences(of: "\u{202F}", with: "").replacingOccurrences(of: " ", with: "")
            .contains("2207"))
    }

    /// US1 : taille hors bornes refusée.
    func testOutOfRangeHeightIsRejected() {
        let app = launch()
        app.buttons["acceptDisclaimer"].tap()
        let height = app.textFields["height"]
        XCTAssertTrue(height.waitForExistence(timeout: 5))
        height.tap()
        height.typeText("30")
        let weight = app.textFields["weight"]
        weight.tap()
        weight.typeText("80")
        XCTAssertTrue(app.staticTexts["validationError"].waitForExistence(timeout: 3)
            || app.otherElements["validationError"].exists)
        XCTAssertFalse(app.buttons["computeTargets"].isEnabled)
    }

    /// US2 sans clé : invitation à saisir la clé.
    func testWithoutKeyInvitesToAddIt() {
        let app = launch(["-uitest-no-key"])
        onboard(app)
        app.tabBars.buttons["Semaine"].tap()
        XCTAssertTrue(app.buttons["addAPIKey"].waitForExistence(timeout: 5))
    }

    /// US2 + US5 : génération simulée → 7 jours, liste de courses remplie.
    func testGenerateWeekThenShoppingList() {
        let app = launch()
        onboard(app)
        app.tabBars.buttons["Semaine"].tap()
        let generate = app.buttons["generateWeek"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        generate.tap()
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Courses"].tap()
        XCTAssertTrue(app.staticTexts["Coût estimé"].waitForExistence(timeout: 5))
    }
}
