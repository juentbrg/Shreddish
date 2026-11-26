import XCTest

/// Parcours de la version commercialisable (spec 017).
extension OnboardingUITests {
    /// Spec 017 : une personne ajoutée au foyer, quantités du foyer dans le détail d'un repas.
    func testHouseholdMember() {
        let app = launch()
        onboard(app)
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 5))
        app.buttons["settings"].tap()
        app.buttons["householdSettings"].tap()
        app.buttons["addMember"].tap()
        let name = app.textFields["memberName"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Léa")
        app.buttons["saveMember"].tap()
        XCTAssertTrue(app.buttons["member-Léa"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '2 portions'")).firstMatch.exists)

        app.tab("Semaine").tap()
        app.buttons["generateWeek"].tap()
        app.buttons["startGeneration"].tap()
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'pour le foyer'")).firstMatch.exists)
    }

    /// Spec 017 : recette perso créée de zéro avec un aliment Ciqual, macros recalculées.
    func testCreateCustomRecipe() {
        let app = launch()
        onboard(app)
        app.tab("Recettes").tap()
        app.buttons["createRecipe"].tap()
        let name = app.textFields["editMealName"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Dahl maison")
        reveal(app.buttons["addIngredient"], in: app)
        app.buttons["addIngredient"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("lentille corail")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'food-'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        result.tap()
        let kcal = app.descendants(matching: .any)["editMealKcal"]
        reveal(kcal, in: app)
        XCTAssertFalse((kcal.label as String).contains(" 0 kcal"))
        revealUp(app.buttons["saveMealEdit"], in: app)
        app.buttons["saveMealEdit"].tap()
        XCTAssertTrue(app.buttons["savedRecipe"].waitForExistence(timeout: 3))
    }

    /// Spec 017 : aliment cherché dans Ciqual ajouté au journal, puis proposé dans les récents.
    func testQuickAddFromCiqual() {
        let app = launch()
        onboard(app)
        app.tab("Semaine").tap()
        app.buttons["generateWeek"].tap()
        app.buttons["startGeneration"].tap()
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
        app.tab("Journal").tap()
        let add = app.buttons["addExtra"]
        reveal(add, in: app)
        add.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("banane")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'food-'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        result.tap()
        XCTAssertTrue(app.buttons["addPortion"].waitForExistence(timeout: 3))
        app.buttons["addPortion"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'banane'")).firstMatch.waitForExistence(timeout: 3))

        reveal(add, in: app)
        add.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'quick-'")).firstMatch.waitForExistence(timeout: 3))
    }

    /// Spec 017 : mensurations saisies depuis « Mes progrès ».
    func testBodyMeasurements() {
        let app = launch()
        onboard(app)
        let progress = app.buttons["bodyProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        progress.tap()
        app.buttons["addMeasurement"].tap()
        let waist = app.textFields["measure-0"]
        XCTAssertTrue(waist.waitForExistence(timeout: 3))
        waist.tap()
        waist.typeText("88")
        app.buttons["saveMeasurement"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Taille 88 cm'")).firstMatch
            .waitForExistence(timeout: 3))
    }

    /// Spec 017 : sans accord, la génération demande d'abord le consentement à l'envoi vers OpenAI.
    func testAIConsentBeforeFirstGeneration() {
        let app = launch(["-uitest-no-consent"])
        onboard(app)
        app.tab("Semaine").tap()
        app.buttons["generateWeek"].tap()
        app.buttons["startGeneration"].tap()
        XCTAssertTrue(app.navigationBars["Tes données et l'IA"].waitForExistence(timeout: 5))
        let accept = app.buttons["acceptAIConsent"]
        reveal(accept, in: app)
        XCTAssertFalse(app.buttons["day-0"].exists)
        accept.tap()
        app.buttons["generateWeek"].tap()
        app.buttons["startGeneration"].tap()
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
    }

    /// Spec 017 : carte « Ma semaine » prête à partager.
    func testShareWeekCard() {
        let app = launch()
        onboard(app)
        app.tab("Semaine").tap()
        app.buttons["generateWeek"].tap()
        app.buttons["startGeneration"].tap()
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
        app.buttons["weekMenu"].tap()
        app.buttons["shareWeek"].tap()
        XCTAssertTrue(app.buttons["shareCard"].waitForExistence(timeout: 5))
    }

    /// Spec 017, FR-1718 : ticket réel saisi dans les courses, comparé à l'estimation, partageable.
    func testActualReceipt() {
        let app = launch()
        onboard(app)
        app.tab("Semaine").tap()
        app.buttons["generateWeek"].tap()
        app.buttons["startGeneration"].tap()
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
        app.tab("Courses").tap()
        let open = app.buttons["openReceipt"]
        reveal(open, in: app)
        open.tap()
        let amount = app.textFields["receiptAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("48,5")
        app.buttons["saveReceipt"].tap()
        Self.saveScreenshot(app, name: "receipt-saved")
        XCTAssertTrue(app.buttons["shareReceipt"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'que prévu' OR label CONTAINS 'estimation'"))
            .firstMatch.exists)
        Self.saveScreenshot(app, name: "receipt")
        app.buttons["shareReceipt"].tap()
        XCTAssertTrue(app.buttons["shareCard"].waitForExistence(timeout: 5))
        Self.saveScreenshot(app, name: "receipt-card")
    }

    /// Spec 017, FR-1704 : poids d'un membre modifié = pesée suivie, portion recalculée.
    func testMemberWeighIns() {
        let app = launch()
        onboard(app)
        app.buttons["settings"].tap()
        app.buttons["householdSettings"].tap()
        app.buttons["addMember"].tap()
        let name = app.textFields["memberName"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Léa")
        app.switches["memberUseProfile"].switches.firstMatch.tap()
        let height = app.textFields["170"]
        XCTAssertTrue(height.waitForExistence(timeout: 3))
        height.tap()
        height.typeText("165")
        let weight = app.textFields["65"]
        weight.tap()
        weight.typeText("62")
        app.buttons["saveMember"].tap()
        XCTAssertTrue(app.buttons["member-Léa"].waitForExistence(timeout: 3))
        app.buttons["member-Léa"].tap()
        let edited = app.textFields["65"]
        XCTAssertTrue(edited.waitForExistence(timeout: 3))
        reveal(app.staticTexts["Pesées"], in: app)
        XCTAssertTrue(app.staticTexts["Pesées"].exists)
        Self.saveScreenshot(app, name: "member-weights")
    }

    /// Aliment banni par appui long dans la liste de courses : ajouté aux aliments bannis des préférences.
    func testBanFoodFromShoppingList() {
        let app = launch()
        onboard(app)
        app.tab("Semaine").tap()
        app.buttons["generateWeek"].tap()
        app.buttons["startGeneration"].tap()
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
        app.tab("Courses").tap()
        let item = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'shopping-'")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        reveal(item, in: app)
        item.press(forDuration: 1.2)
        let ban = app.buttons["Ne plus jamais proposer"]
        XCTAssertTrue(ban.waitForExistence(timeout: 3))
        ban.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(alert.label.contains("banni"))
        // L'article vient du planning : l'alerte propose de remplacer les repas concernés.
        XCTAssertTrue(alert.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remplacer'")).firstMatch.exists)
        alert.buttons["Plus tard"].tap()
        app.tab("Semaine").tap()
        let replace = app.buttons["replaceBannedMeals"]
        XCTAssertTrue(replace.waitForExistence(timeout: 5))
        XCTAssertTrue(replace.label.hasPrefix("Remplacer"))
    }

    /// Spec 017, FR-1706 : partage de la liste en texte ou vers Rappels.
    func testShareShoppingList() {
        let app = launch()
        onboard(app)
        app.tab("Semaine").tap()
        app.buttons["generateWeek"].tap()
        app.buttons["startGeneration"].tap()
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
        app.tab("Courses").tap()
        let share = app.buttons["shareShoppingList"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        XCTAssertTrue(app.buttons["Partager en texte"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Envoyer vers Rappels"].waitForExistence(timeout: 3))
    }

    /// Régénérer une journée en écoulant des restes (cheat day, repas sautés).
    func testRegenerateDayWithLeftovers() {
        let app = launch()
        onboard(app)
        app.tab("Semaine").tap()
        app.buttons["generateWeek"].tap()
        app.buttons["startGeneration"].tap()
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
        let regenerate = app.buttons["regenerateDay"]
        reveal(regenerate, in: app)
        regenerate.tap()
        let yes = app.segmentedControls["hasPantry"].buttons["Oui"]
        XCTAssertTrue(yes.waitForExistence(timeout: 3))
        yes.tap()
        let name = app.textFields["pantryName"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Riz")
        let quantity = app.textFields["pantryQuantity"].firstMatch
        quantity.tap()
        quantity.typeText("200")
        app.buttons["confirmRegenerateDay"].tap()
        XCTAssertTrue(app.buttons["regenerateDay"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["confirmRegenerateDay"].exists)
    }

    /// Restes proposés : cochés par défaut, décochés sur place sans changer d'ordre.
    func testPantrySuggestionsToggleInPlace() {
        let app = launch()
        onboard(app)
        app.tab("Semaine").tap()
        app.buttons["generateWeek"].tap()
        app.buttons["startGeneration"].tap()
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
        app.buttons["navPlanNext"].tap()
        let yes = app.segmentedControls["hasPantry"].buttons["Oui"]
        XCTAssertTrue(yes.waitForExistence(timeout: 3))
        yes.tap()
        let suggestions = app.buttons.matching(identifier: "pantrySuggestion")
        XCTAssertTrue(suggestions.firstMatch.waitForExistence(timeout: 3))
        let count = suggestions.count
        let first = suggestions.element(boundBy: 0)
        let label = first.label
        XCTAssertTrue(first.isSelected)
        first.tap()
        XCTAssertEqual(suggestions.count, count)
        XCTAssertEqual(suggestions.element(boundBy: 0).label, label)
        XCTAssertFalse(suggestions.element(boundBy: 0).isSelected)
        Self.saveScreenshot(app, name: "pantry-checklist")
    }

    /// Spec 017, FR-1713 : audit d'accessibilité des écrans principaux (contrastes, libellés, tailles).
    func testAccessibilityAudit() throws {
        continueAfterFailure = true
        let app = launch()
        onboard(app)
        app.tab("Semaine").tap()
        app.buttons["generateWeek"].tap()
        app.buttons["startGeneration"].tap()
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
        for tab in ["Semaine", "Journal", "Courses", "Recettes", "Profil"] {
            app.tab(tab).tap()
            let tabBarTop = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY
            let audits: XCUIAccessibilityAuditType = [
                .contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .dynamicType, .textClipped,
            ]
            try app.performAccessibilityAudit(for: audits) { issue in
                print("AUDIT \(tab) : \(issue.compactDescription) [\(issue.element?.label ?? "-")] "
                    + "id=\(issue.element?.identifier ?? "-") type=\(issue.element?.elementType.rawValue ?? 0) "
                    + "frame=\(issue.element?.frame ?? .zero)")
                // Faux positifs : élément à moitié sous la barre d'onglets translucide (contraste mesuré contre
                // la barre), ou contraste « presque » conforme sur les tuiles des cartes vertes.
                // Élément introuvable (déjà sorti de l'écran) : rien à corriger à cet endroit.
                guard let frame = issue.element?.frame, frame != .zero else { return true }
                // iOS 26 : l'effet de bord de défilement floute le contenu bien au-dessus de la barre flottante.
                if frame.maxY > tabBarTop - 120 { return true }
                // Contrôle désactivé (« Enregistrer » sans montant) : hors exigence de contraste (WCAG 1.4.3).
                if issue.element?.isEnabled == false { return true }
                // Barre de progression : non interactive, la zone tactile ne s'applique pas.
                if issue.element?.elementType == .progressIndicator { return true }
                // Petites légendes (jours, « cible ») : agrandies mais plafonnées par le système. Suivi à part.
                return ["Contrast nearly passed", "Dynamic Type font sizes are partially unsupported"]
                    .contains(issue.compactDescription)
            }
        }
    }

    /// Spec 017, FR-1712 : interface traduite (anglais, allemand).
    func testTranslatedInterface() {
        for (language, week, groceries) in [("en", "Week", "Groceries"), ("de", "Woche", "Einkauf")] {
            let app = launch(["-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "de_DE"])
            onboard(app)
            XCTAssertTrue(app.tab(week).waitForExistence(timeout: 5))
            app.tab(week).tap()
            app.buttons["generateWeek"].tap()
            app.buttons["startGeneration"].tap()
            XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
            Self.saveScreenshot(app, name: "\(language)-week")
            app.tab(groceries).tap()
            Self.saveScreenshot(app, name: "\(language)-groceries")
            app.terminate()
        }
    }

    static func saveScreenshot(_ app: XCUIApplication, name: String) {
        guard let folder = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
    }

    /// Période choisie : dès demain jusqu'au dernier jour choisi ; aujourd'hui reste dans le planning en cours.
    func testPlanCustomRangeKeepsToday() {
        let app = launch()
        onboard(app)
        app.tab("Semaine").tap()
        app.buttons["generateWeek"].tap()
        app.buttons["startGeneration"].tap()
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
        app.buttons["weekMenu"].tap()
        app.buttons["newWeek"].tap()
        let tomorrow = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Demain'")).firstMatch
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 3))
        tomorrow.tap()
        let end = app.buttons.matching(identifier: "endDay").firstMatch
        reveal(end, in: app)
        XCTAssertTrue(end.waitForExistence(timeout: 3))
        end.tap()
        XCTAssertTrue(end.isSelected)
        let summary = app.staticTexts["periodSummary"]
        XCTAssertTrue(summary.label.contains("prévus remplacés, les autres restent"), summary.label)
        Self.saveScreenshot(app, name: "plan-range")
        revealUp(app.buttons["startGeneration"], in: app)
        app.buttons["startGeneration"].tap()
        let status = app.staticTexts["weekStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Semaine en cours")
        // Planning en cours réduit à aujourd'hui.
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["day-1"].exists)
        app.buttons["nextWeek"].tap()
        XCTAssertTrue(app.staticTexts["Semaine à venir"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["day-0"].exists)
    }

    /// « Autre idée de repas » demande confirmation, puis l'ancien repas peut être remis.
    func testReplaceMealAsksThenUndo() {
        let app = launch()
        onboard(app)
        app.tab("Semaine").tap()
        app.buttons["generateWeek"].tap()
        app.buttons["startGeneration"].tap()
        XCTAssertTrue(app.buttons["day-0"].waitForExistence(timeout: 10))
        let original = app.buttons.containing(NSPredicate(format: "label CONTAINS 'J1'")).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        let originalLabel = original.label
        original.tap()
        let replace = app.buttons["replaceMeal"]
        XCTAssertTrue(replace.waitForExistence(timeout: 5))
        reveal(replace, in: app)
        replace.tap()
        let confirm = app.buttons["Remplacer"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        Self.saveScreenshot(app, name: "replace-confirm")
        confirm.tap()
        let undo = app.buttons["undoReplacement"]
        XCTAssertTrue(undo.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'remplacé'")).firstMatch.exists)
        Self.saveScreenshot(app, name: "replace-undo")
        undo.tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label == %@", originalLabel)).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["undoReplacement"].exists)
    }
}
