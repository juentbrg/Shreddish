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

    /// Sans clé dans le build : génération indisponible, aucune saisie (spec 009).
    func testWithoutKeyExplainsMissingBuildKey() {
        let app = launch(["-uitest-no-key"])
        onboard(app)
        app.tabBars.buttons["Semaine"].tap()
        XCTAssertTrue(app.staticTexts["missingAPIKey"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["generateWeek"].exists)
    }

    /// US2 + US5 : génération simulée → 7 jours, liste de courses remplie.
    func testGenerateWeekThenShoppingList() {
        let app = launch()
        onboard(app)
        app.tabBars.buttons["Semaine"].tap()
        let generate = app.buttons["generateWeek"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        generate.tap()
        let start = app.buttons["startGeneration"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        start.tap()
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Courses"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["weekCost"].waitForExistence(timeout: 5))
    }

    /// Étapes de recette : glisser vers la gauche passe à l'étape suivante, vers la droite revient.
    func testRecipeStepsSwipe() {
        let app = launch()
        onboard(app)
        app.tabBars.buttons["Semaine"].tap()
        app.buttons["generateWeek"].tap()
        let start = app.buttons["startGeneration"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        start.tap()
        let day = app.buttons["day-0"]
        XCTAssertTrue(day.waitForExistence(timeout: 10))
        day.tap()
        let meal = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Porridge'")).firstMatch
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        meal.tap()
        let card = app.descendants(matching: .any)["currentStep"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Étape 1 sur 4"].waitForExistence(timeout: 2))
        card.swipeLeft()
        XCTAssertTrue(app.staticTexts["Étape 2 sur 4"].waitForExistence(timeout: 2))
        app.descendants(matching: .any)["currentStep"].swipeRight()
        XCTAssertTrue(app.staticTexts["Étape 1 sur 4"].waitForExistence(timeout: 2))
    }

    /// Spec 007 : valeurs d'un complément selon sa nature (whey à macros, créatine en dose).
    func testSupplementProteinPerServing() {
        let app = launch()
        onboard(app)
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 5))
        app.buttons["settings"].tap()
        app.buttons["preferencesSettings"].tap()
        let whey = app.buttons["suggestion-Whey"]
        reveal(whey, in: app)
        whey.tap()
        let item = app.buttons["item-Whey"]
        reveal(item, in: app)
        item.tap()
        let serving = app.textFields["servingSize"]
        XCTAssertTrue(serving.waitForExistence(timeout: 3))
        serving.tap()
        serving.typeText("30")
        for (field, value) in [("kcalPerServing", "118"), ("proteinPerServing", "24"), ("carbsPerServing", "2"), ("fatPerServing", "2")] {
            let element = app.textFields[field]
            reveal(element, in: app)
            element.tap()
            element.typeText(value)
        }
        app.buttons["keyboardDone"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        let summary = app.buttons["item-Whey"]
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertTrue(summary.label.contains("Dose de 30 g · 118 kcal · P 24 g · G 2 g · L 2 g"), summary.label)

        // Créatine : dose simple, pas de protéines par dose.
        let creatine = app.buttons["suggestion-Créatine"]
        reveal(creatine, in: app)
        creatine.tap()
        let creatineItem = app.buttons["item-Créatine"]
        reveal(creatineItem, in: app)
        creatineItem.tap()
        let dose = app.textFields["doseAmount"]
        XCTAssertTrue(dose.waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["proteinPerServing"].exists)
        dose.tap()
        dose.typeText("5")
        app.buttons["keyboardDone"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(creatineItem.waitForExistence(timeout: 3))
        XCTAssertTrue(creatineItem.label.contains("5 g par prise, 1 fois par jour"), creatineItem.label)
    }

    /// Spec 006 : une semaine à venir se planifie sans remplacer celle en cours.
    func testPlanUpcomingWeek() {
        let app = launch()
        onboard(app)
        app.tabBars.buttons["Semaine"].tap()
        app.buttons["generateWeek"].tap()
        app.buttons["startGeneration"].tap()
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
        app.buttons["weekMenu"].tap()
        app.buttons["newWeek"].tap()
        let tomorrow = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Demain'")).firstMatch
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 3))
        tomorrow.tap()
        app.buttons["startGeneration"].tap()
        let upcoming = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'À venir'")).firstMatch
        XCTAssertTrue(upcoming.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'En cours'")).firstMatch.exists)
    }

    /// La semaine suivante se planifie depuis le bouton sous le planning, sans toucher à la semaine en cours.
    func testPlanNextWeekFromButton() {
        let app = launch()
        onboard(app)
        app.tabBars.buttons["Semaine"].tap()
        app.buttons["generateWeek"].tap()
        app.buttons["startGeneration"].tap()
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
        let next = app.buttons["planNextWeek"]
        for _ in 0..<5 where !next.isHittable { app.swipeUp() }
        // Pas de débordement horizontal de la semaine.
        XCTAssertLessThanOrEqual(next.frame.maxX, app.windows.firstMatch.frame.maxX)
        next.tap()
        let following = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Suite du planning'")).firstMatch
        XCTAssertTrue(following.waitForExistence(timeout: 3))
        XCTAssertTrue(following.isSelected)
        app.buttons["startGeneration"].tap()
        let upcoming = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'À venir'")).firstMatch
        XCTAssertTrue(upcoming.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'En cours'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["planNextWeek"].exists)
    }

    /// Spec 014 : un repas sauvegardé se retrouve dans Recettes et se replace dans la semaine suivante.
    func testSaveRecipeAndPlanItNextWeek() {
        let app = launch()
        onboard(app)
        app.tabBars.buttons["Semaine"].tap()
        app.buttons["generateWeek"].tap()
        app.buttons["startGeneration"].tap()
        let day = app.buttons["day-0"]
        XCTAssertTrue(day.waitForExistence(timeout: 10))
        day.tap()
        let meal = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Porridge'")).firstMatch
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        meal.tap()
        XCTAssertTrue(app.descendants(matching: .any)["currentStep"].waitForExistence(timeout: 15))
        let save = app.buttons["saveRecipe"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        save.tap()
        XCTAssertTrue(app.buttons["Retirer des recettes"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Recettes"].tap()
        let saved = app.buttons["savedRecipe"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 3))
        saved.tap()
        let queue = app.switches["queueRecipe"]
        XCTAssertTrue(queue.waitForExistence(timeout: 3))
        queue.switches.firstMatch.tap()
        XCTAssertEqual(queue.value as? String, "1")

        app.tabBars.buttons["Semaine"].tap()
        // Retour du détail du repas à la semaine.
        app.navigationBars.buttons.firstMatch.tap()
        let next = app.buttons["planNextWeek"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        for _ in 0..<5 where !next.isHittable { app.swipeUp() }
        next.tap()
        let pick = app.buttons["pickRecipe"].firstMatch
        for _ in 0..<5 where !(pick.exists && pick.isHittable) { app.swipeUp() }
        XCTAssertTrue(pick.isSelected)
        app.buttons["startGeneration"].tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'À venir'")).firstMatch.waitForExistence(timeout: 10))
    }

    /// Pesée depuis le profil, courbe et historique un écran plus loin.
    func testWeighInFromProfile() {
        let app = launch()
        onboard(app)
        app.tabBars.buttons["Profil"].tap()
        XCTAssertTrue(app.staticTexts["targetKcal"].waitForExistence(timeout: 5))
        app.buttons["Modifier mon profil"].firstMatch.tap()
        let input = app.textFields["weightInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("79,5")
        app.buttons["saveWeight"].tap()
        XCTAssertTrue(app.buttons["recalcTargets"].waitForExistence(timeout: 3))
        app.buttons["Plus tard"].tap()
        app.buttons["weightHistory"].tap()
        let entry = app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS '79,5 kg'")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
    }

    /// Spec 004 : le planning courant se supprime depuis le menu, après confirmation.
    func testDeleteCurrentPlan() {
        let app = launch()
        onboard(app)
        app.tabBars.buttons["Semaine"].tap()
        let generate = app.buttons["generateWeek"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        generate.tap()
        let start = app.buttons["startGeneration"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        start.tap()
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
        app.buttons["weekMenu"].tap()
        app.buttons["deletePlan"].tap()
        let confirm = app.buttons["Supprimer le planning"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.buttons["generateWeek"].waitForExistence(timeout: 5))
    }

    /// Spec 003 : suggestion d'équipement ajoutée puis supprimée, budget au montant rapide.
    func testEquipmentSuggestionAndBudgetPreset() {
        let app = launch()
        onboard(app)
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 5))
        app.buttons["settings"].tap()
        app.buttons["preferencesSettings"].tap()

        let preset = app.buttons["budgetPreset-80"]
        reveal(preset, in: app)
        preset.tap()
        XCTAssertEqual(app.textFields["weeklyBudget"].value as? String, "80")

        let suggestion = app.buttons["suggestion-Airfryer"]
        reveal(suggestion, in: app)
        suggestion.tap()
        let remove = app.buttons["Supprimer Airfryer"]
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        remove.tap()
        XCTAssertFalse(app.buttons["Supprimer Airfryer"].exists)
        XCTAssertTrue(app.buttons["suggestion-Airfryer"].exists)
    }

    /// Spec 015 : jeûne intermittent 12:00-19:30, repas de la semaine générée recalés dans la fenêtre.
    func testIntermittentFastingKeepsMealsInWindow() {
        let app = launch()
        onboard(app)
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 5))
        app.buttons["settings"].tap()
        app.buttons["preferencesSettings"].tap()
        let toggle = app.switches["fastingToggle"]
        reveal(toggle, in: app)
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '16 h 30 de jeûne'")).firstMatch
            .waitForExistence(timeout: 3))

        app.tabBars.buttons["Semaine"].tap()
        let generate = app.buttons["generateWeek"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        generate.tap()
        app.buttons["startGeneration"].tap()
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS '12:00'")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS '08:00'")).firstMatch.exists)
    }
}
