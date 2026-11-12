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

    /// Ferme le clavier puis fait défiler jusqu'à l'élément (formulaire plus long que l'écran).
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if app.buttons["keyboardDone"].exists { app.buttons["keyboardDone"].tap() }
        var attempts = 0
        while !(element.exists && element.isHittable) && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
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
        let compute = app.buttons["computeTargets"]
        reveal(compute, in: app)
        compute.tap()
    }

    /// US1 : disclaimer → profil → cibles 1819 kcal (homme 30 ans, 180 cm, 80 kg, sèche ; défauts
    /// spec 002 : bureau, 3 séances de 60 min modérées).
    func testOnboardingShowsReferenceTargets() {
        let app = launch()
        onboard(app)
        let target = app.staticTexts["targetKcal"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        let digits = target.label.filter(\.isNumber)
        XCTAssertTrue(digits.hasPrefix("1819"), "Cible affichée : \(target.label)")
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
        let compute = app.buttons["computeTargets"]
        reveal(compute, in: app)
        XCTAssertTrue(app.staticTexts["validationError"].waitForExistence(timeout: 3)
            || app.otherElements["validationError"].exists)
        XCTAssertFalse(compute.isEnabled)
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
