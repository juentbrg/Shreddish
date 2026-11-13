import Foundation

/// Préférences transmises à l'IA. Seules données utilisateur envoyées avec les cibles (FR-021).
public struct PromptPreferences: Codable, Sendable, Equatable {
    public var mealsPerDay: Int
    public var maxPrepMinutes: Int
    public var weeklyBudgetEur: Double
    public var budgetTolerance: Double
    public var allergies: [String]
    public var dislikedFoods: [String]
    public var likedFoods: [String]
    public var equipment: [String]
    public var batchCooking: Bool
    public var ingredientAvailability: IngredientAvailability
    /// Compléments déjà possédés (spec 004), avec protéines par dose (spec 007).
    public var ownedSupplements: [OwnedSupplement]
    /// Heure d'entraînement habituelle « HH:mm ».
    public var trainingTime: String?
    /// Séances par semaine, depuis le profil.
    public var trainingSessionsPerWeek: Int?

    public init(
        mealsPerDay: Int, maxPrepMinutes: Int, weeklyBudgetEur: Double, budgetTolerance: Double,
        allergies: [String], dislikedFoods: [String], likedFoods: [String], equipment: [String],
        batchCooking: Bool, ingredientAvailability: IngredientAvailability,
        ownedSupplements: [OwnedSupplement] = [], trainingTime: String? = nil, trainingSessionsPerWeek: Int? = nil
    ) {
        self.mealsPerDay = mealsPerDay
        self.maxPrepMinutes = maxPrepMinutes
        self.weeklyBudgetEur = weeklyBudgetEur
        self.budgetTolerance = budgetTolerance
        self.allergies = allergies
        self.dislikedFoods = dislikedFoods
        self.likedFoods = likedFoods
        self.equipment = equipment
        self.batchCooking = batchCooking
        self.ingredientAvailability = ingredientAvailability
        self.ownedSupplements = ownedSupplements
        self.trainingTime = trainingTime
        self.trainingSessionsPerWeek = trainingSessionsPerWeek
    }
}

/// Complément possédé envoyé à l'IA (spec 007). `kind` "macro" : valeurs par dose ; "dose" : prise simple.
public struct OwnedSupplement: Codable, Sendable, Equatable {
    public var name: String
    public var kind: SupplementKind
    public var servingG: Double?
    public var kcalPerServing: Double?
    public var proteinGPerServing: Double?
    public var carbsGPerServing: Double?
    public var fatGPerServing: Double?
    /// « 5 g », « 1 gelule ».
    public var dose: String?
    public var dosesPerDay: Int?

    public init(name: String, info: SupplementInfo = SupplementInfo()) {
        self.name = name
        kind = info.resolvedKind(for: name)
        switch kind {
        case .macro:
            servingG = info.servingG
            kcalPerServing = info.kcalPerServing
            proteinGPerServing = info.proteinPerServingG
            carbsGPerServing = info.carbsPerServingG
            fatGPerServing = info.fatPerServingG
        case .dose:
            if let amount = info.doseAmount {
                let value = amount.rounded() == amount ? String(Int(amount)) : String(amount)
                dose = "\(value) \((info.doseUnit ?? .g).rawValue)"
            }
            dosesPerDay = info.dosesPerDay
        }
    }
}

/// Construction des messages envoyés à l'IA (contracts/ai-requests.md).
public enum PromptBuilder {
    struct TargetsPayload: Encodable {
        var kcal: Int
        var proteinG: Int
        var carbsG: Int
        var fatG: Int

        init(_ totals: MacroTotals) {
            kcal = Int(max(0, totals.kcal).rounded())
            proteinG = Int(max(0, totals.proteinG).rounded())
            carbsG = Int(max(0, totals.carbsG).rounded())
            fatG = Int(max(0, totals.fatG).rounded())
        }
    }

    struct MealSummary: Encodable {
        var type: MealType
        var name: String
        var kcal: Int
        var proteinG: Int
        var carbsG: Int
        var fatG: Int
    }

    struct Input: Encodable {
        var task: String
        var targets: TargetsPayload
        var goal: Goal
        var preferences: PromptPreferences
        var dayOffset: Int?
        var existingDayMeals: [MealSummary]?
        var mealTypeToReplace: MealType?
        var remainingTargets: TargetsPayload?
        var avoidMealNames: [String]?
        var costLimitEur: Double?
        /// Retour sur l'essai précédent (coût trop élevé), spec 004.
        var previousAttemptFeedback: String?
        /// Prix de référence en France (spec 011), pour estimer le budget comme l'application.
        var referencePricesEurPerKg: String? = PromptBuilder.referencePrices
    }

    /// Aliments de base et leur prix au kg mangé (table de prix), envoyés avec les tâches de planification.
    static let referenceFoods: [(label: String, code: Int)] = [
        ("poulet filet", 36017), ("poulet cuisse", 36002), ("bœuf haché 5 %", 6250), ("porc filet", 28204),
        ("thon au naturel égoutté", 26039), ("œuf", 22000), ("fromage blanc 0 %", 19644), ("lait demi-écrémé", 19041),
        ("emmental", 12115), ("riz", 9100), ("pâtes", 9810), ("semoule", 9610), ("flocons d'avoine", 32140),
        ("lentilles", 20585), ("pois chiches égouttés", 20532), ("pomme de terre", 4008), ("haricots verts", 20061),
        ("banane", 13005), ("pomme", 13039), ("avocat", 13004), ("huile de colza", 17130), ("huile d'olive", 17270),
        ("amandes", 15000), ("graines de chia", 15047), ("beurre de cacahuète", 15202), ("pain complet", 7110),
        ("tofu", 20904),
    ]

    static let referencePrices: String? = {
        let catalog = PriceCatalog.shared
        let items = referenceFoods.compactMap { item in
            catalog.price(code: item.code).map { "\(item.label) \(String(format: "%.1f", $0.eurPerEdibleKg))" }
        }
        return items.isEmpty ? nil : items.joined(separator: " ; ")
    }()

    public static func weekInput(
        targets: MacroTotals, goal: Goal, preferences: PromptPreferences, feedback: String? = nil
    ) -> String {
        encode(Input(
            task: "week", targets: TargetsPayload(targets), goal: goal, preferences: preferences,
            previousAttemptFeedback: feedback
        ))
    }

    public static func dayInput(
        targets: MacroTotals, goal: Goal, preferences: PromptPreferences, dayOffset: Int, avoidMealNames: [String],
        costLimitEur: Double, feedback: String? = nil
    ) -> String {
        encode(Input(
            task: "day", targets: TargetsPayload(targets), goal: goal, preferences: preferences,
            dayOffset: dayOffset, avoidMealNames: avoidMealNames, costLimitEur: BudgetMath.cents(costLimitEur),
            previousAttemptFeedback: feedback
        ))
    }

    /// Message envoyé au nouvel essai quand le coût dépasse le plafond.
    public static func overBudgetFeedback(costEur: Double, ceilingEur: Double) -> String {
        "Proposition précédente : \(BudgetMath.cents(costEur)) € pour un plafond de \(BudgetMath.cents(ceilingEur)) €. "
            + "Remplace les produits chers (marque distributeur, yaourt nature 0 % ou fromage blanc au lieu du skyr, "
            + "œufs, légumineuses, poulet entier ou cuisses, légumes surgelés), macros identiques."
    }

    /// Retour pour un jour hors cible après ajustement des portions (spec 010), valeurs Ciqual.
    public static func offTargetFeedback(totals: MacroTotals, targets: MacroTotals) -> String {
        func gap(_ value: Double, _ target: Double, _ label: String, _ unit: String) -> String? {
            let difference = Int((value - target).rounded())
            guard target > 0, abs(Double(difference)) / target > 0.1 else { return nil }
            return "\(label) \(difference > 0 ? "+" : "")\(difference) \(unit)"
        }
        let gaps = [
            gap(totals.kcal, targets.kcal, "kcal", "kcal"), gap(totals.proteinG, targets.proteinG, "protéines", "g"),
            gap(totals.carbsG, targets.carbsG, "glucides", "g"), gap(totals.fatG, targets.fatG, "lipides", "g"),
        ].compactMap(\.self)
        return "Valeurs réelles (table Ciqual) de ta proposition précédente pour ce jour, écart à la cible : "
            + gaps.joined(separator: ", ") + ". Change la composition des repas pour corriger ces écarts."
    }

    /// Retour pour un jour aux déjeuners ou dîners trop répétés (spec 010).
    public static func varietyFeedback(_ signatures: [[String]]) -> String {
        let combos = signatures.map { $0.joined(separator: " + ") }.joined(separator: ", ")
        return "Déjeuner ou dîner trop proche des autres jours (\(combos) déjà 2 fois cette semaine) : "
            + "change la protéine principale ou le féculent."
    }

    /// Message envoyé au nouvel essai quand l'IA a refusé à cause du budget (spec 008).
    public static func budgetRefusalFeedback(reason: String) -> String {
        "Refus précédent : « \(reason) ». Le budget n'est jamais un motif de refus : infeasible = null, "
            + "planning le moins cher possible, même au-dessus du budget."
    }

    public static func replaceMealInput(
        targets: MacroTotals, goal: Goal, preferences: PromptPreferences, dayOffset: Int,
        existingDayMeals: [MealDTO], mealTypeToReplace: MealType, avoidMealNames: [String], costLimitEur: Double,
        feedback: String? = nil
    ) -> String {
        let remaining = targets - Totals.planned(existingDayMeals)
        let summaries = existingDayMeals.map {
            MealSummary(
                type: $0.type, name: $0.name, kcal: Int($0.kcal.rounded()), proteinG: Int($0.proteinG.rounded()),
                carbsG: Int($0.carbsG.rounded()), fatG: Int($0.fatG.rounded())
            )
        }
        return encode(Input(
            task: "replace_meal", targets: TargetsPayload(targets), goal: goal, preferences: preferences,
            dayOffset: dayOffset, existingDayMeals: summaries, mealTypeToReplace: mealTypeToReplace,
            remainingTargets: TargetsPayload(remaining), avoidMealNames: avoidMealNames,
            costLimitEur: BudgetMath.cents(costLimitEur), previousAttemptFeedback: feedback
        ))
    }

    private static func encode(_ input: Input) -> String {
        guard let data = try? AIResponseDecoder.encoder.encode(input) else { return "{}" }
        return String(bytes: data, encoding: .utf8) ?? "{}"
    }

    /// Prompt système : règles imposées à l'IA (contracts/ai-requests.md). Enums, unités et format d'heure sont
    /// imposés par le schéma strict ; tirets et rayons sont corrigés par l'application.
    public static func systemInstructions() -> String {
        """
        Tu es un assistant de planification de repas pour une personne qui suit un objectif physique \
        (goal : cut = sèche, bulk = prise de masse, recomp = recomposition). Tu reçois un JSON de contexte \
        et tu réponds uniquement avec le JSON demandé par le schéma.

        Règles strictes :
        - Repas simples et économiques, mais copieux et bons.
        - Respecte strictement max_prep_minutes pour chaque repas.
        - allergies : aucun de ces aliments, ni trace, ni dérivé, ni ingrédient qui en contient souvent \
        (ex. arachide → beurre de cacahuète, huile d'arachide ; lait → beurre, fromage, crème).
        - disliked_foods : jamais, sous aucune forme.
        - Exactement meals_per_day repas par jour, collations incluses (types : breakfast, lunch, dinner, snack).
        - Macros par jour : kcal à ±5 % de targets.kcal, protéines ≥ targets.protein_g, glucides et lipides \
        à ±10 % de targets.carbs_g et targets.fat_g. Ne compense jamais un manque de protéines par des glucides.
        - Valeurs cohérentes : kcal ≈ 4 × protein_g + 4 × carbs_g + 9 × fat_g. L'application recalcule les \
        macros depuis la table Ciqual et ajuste les portions : nomme chaque ingrédient précisément, tel \
        qu'acheté (ex. « Riz basmati cru », « Lentilles vertes sèches », « Thon au naturel en boîte \
        égoutté », « Fromage blanc 0 % »).
        - Budget : objectif, jamais bloquant. Coût total de la semaine ≤ weekly_budget_eur ; dépassement au plus de budget_tolerance \
        (0,1 = 10 %), à éviter. task "day" ou "replace_meal" : coût total ≤ cost_limit_eur. Budget serré : \
        choisis les produits les moins chers par gramme de protéine (œufs, yaourt nature 0 %, fromage blanc 0 %, \
        lentilles, pois chiches, thon en boîte, poulet entier ou cuisses, porc, légumes surgelés, riz, pâtes, \
        flocons d'avoine) plutôt que les produits premium (skyr, saumon, avocat, fruits secs, portions individuelles). \
        Ne remplis jamais infeasible pour le budget ou le prix : propose le planning le moins cher possible, \
        l'application recalcule le coût et prévient si besoin.
        - previous_attempt_feedback : si présent, corrige ce qui y est signalé.
        - Prix : prix moyens en supermarché en France, marque distributeur. reference_prices_eur_per_kg donne \
        le prix au kg mangé des aliments courants : base-toi dessus pour le budget. Pour chaque ingrédient, \
        unit_price_eur en € par kg (unit "g"), par litre (unit "ml") ou par pièce (unit "piece"). \
        cost_eur = quantity × unit_price_eur (÷ 1000 pour g et ml). L'application recalcule les prix.
        - ingredient_availability : "everywhere" = uniquement des ingrédients basiques trouvables dans tout \
        supermarché et en hard discount (Lidl, Aldi), aucun produit de niche (tempeh, seitan, spiruline, levure \
        maltée, sirop d'agave, farines spéciales, superaliments) ; "supermarket" = rayon d'un grand \
        supermarché, sans magasin spécialisé ; "specialty" = magasins bio ou spécialisés acceptés.
        - Équipement : plaques, casserole, poêle et four toujours disponibles, en plus de equipment. Riz, pâtes, \
        semoule et pommes de terre se cuisent à la casserole : aucun cuiseur nécessaire, varie les féculents \
        (riz au moins 2 fois par semaine sauf si exclu).
        - owned_supplements : compléments déjà possédés, coût 0. kind "macro" (whey, gainer…) : utilise-le pour \
        atteindre les protéines quand c'est pertinent (collation, après l'entraînement), comme ingrédient en g, \
        unit_price_eur = 0, cost_eur = 0, aisle "autre". Si serving_g et les valeurs par dose sont présents, \
        macros du complément = quantité ÷ serving_g × kcal_per_serving, protein_g_per_serving, \
        carbs_g_per_serving, fat_g_per_serving ; indique la dose en scoops (ex. « 1 scoop de 30 g »). \
        kind "dose" (créatine, vitamines, oméga-3…) : ni macro ni ingrédient, la prise est ajoutée par \
        l'application.
        - training_time et training_sessions_per_week : place la collation ou le repas protéiné autour de \
        l'entraînement ; sans heure connue, suppose une séance en fin de journée.
        - time : heure conseillée « HH:mm » de chaque repas, cohérente sur la journée (petit-déjeuner 7:00-9:00, \
        déjeuner 12:00-13:30, dîner 19:00-21:00, collation selon l'entraînement).
        - Quantités en g, ml ou piece, pesées crues / non cuites. unit "piece" seulement pour ce qui se compte \
        (œufs, fruits, tortillas), avec piece_g = poids d'une pièce en g ; sinon piece_g = null. cost_eur = \
        coût de la quantité utilisée, recalculé par l'application depuis unit_price_eur.
        - Semaine et jour : pas d'étapes, les recettes sont rédigées ensuite.
        - Variété : un même plat principal au plus 2 fois par semaine, sauf préparation batch cooking. Change \
        vraiment de plat, pas seulement de nom : la même association protéine principale + féculent (ex. \
        poulet + riz, thon + pâtes) au plus 2 fois par semaine sur les déjeuners et dîners.
        - Privilégie liked_foods.
        - day_offset 0 = jour de génération ; une semaine couvre les jours 0 à 6.
        - batch_cooking vrai : 1 ou 2 prep_sessions (index 0, 1), et les repas issus d'une session ont \
        prep_session_ref = index de la session. batch_cooking faux : prep_sessions vide, prep_session_ref null.
        - task "day" : régénère uniquement le jour day_offset, différent de avoid_meal_names.
        - task "replace_meal" : propose un seul repas de type meal_type_to_replace, proche de remaining_targets, \
        différent de avoid_meal_names et de existing_day_meals, avec ses étapes. \(recipeRules)
        - Si allergies, exclusions et temps sont impossibles à respecter ensemble : remplis infeasible avec la \
        raison en une phrase, sans jamais ignorer une contrainte ; sinon infeasible = null. Jamais pour le \
        budget, le prix, la longueur ou le format de la réponse : produis tous les jours demandés.
        - Noms de plats, étapes et textes en français.
        """
    }

    // MARK: Recettes (spec 010)

    static let recipeRules = """
    Étapes détaillées pour cuisiner sans expérience : 4 à 12 étapes selon le plat (2 à 3 pour une collation \
    sans cuisson). Chaque étape précise quantités, ustensile, intensité du feu ou température, durée et repère \
    visuel (ex. « Rince 80 g de riz à l'eau froide, puis verse-le dans une casserole avec 160 ml d'eau salée. \
    Porte à ébullition à feu vif, couvre, baisse à feu doux 12 min sans soulever le couvercle, puis laisse \
    reposer 5 min hors du feu. »). Inclus l'assaisonnement. Plaques, casserole, poêle et four disponibles, \
    en plus de equipment.
    """

    public static func recipeInstructions() -> String {
        """
        Tu rédiges la recette d'un repas déjà composé. Tu reçois un JSON de contexte et tu réponds uniquement \
        avec le JSON demandé par le schéma, en français.
        - Utilise exactement les ingrédients et quantités de meal.ingredients, sans en ajouter d'autres que \
        sel, poivre, épices, herbes et eau.
        - Respecte meal.prep_minutes.
        - \(recipeRules)
        - supplement_doses : ajoute une étape pour chaque prise, avec la dose exacte et le moment \
        (ex. « Prends 5 g de créatine avec ce repas »).
        - Complément en poudre (whey…) : dose en scoops dans l'étape (ex. « 1 scoop de 30 g »).
        """
    }

    struct RecipeInput: Encodable {
        struct Item: Encodable {
            var name: String
            var quantity: Double
            var unit: String
        }

        struct MealPayload: Encodable {
            var type: MealType
            var name: String
            var time: String?
            var prepMinutes: Int
            var ingredients: [Item]
        }

        var task = "recipe"
        var meal: MealPayload
        var supplementDoses: [String]
        var equipment: [String]
        var trainingTime: String?
    }

    public static func recipeInput(meal: MealDTO, supplementDoses: [String], preferences: PromptPreferences) -> String {
        let payload = RecipeInput.MealPayload(
            type: meal.type, name: meal.name, time: meal.time, prepMinutes: meal.prepMinutes,
            ingredients: meal.ingredients.map { .init(name: $0.name, quantity: $0.quantity, unit: $0.unit) }
        )
        return encodeAny(RecipeInput(
            meal: payload, supplementDoses: supplementDoses, equipment: preferences.equipment,
            trainingTime: preferences.trainingTime
        ))
    }

    // MARK: Choix Ciqual (spec 010)

    public static func foodMatchInstructions() -> String {
        """
        Pour chaque ingrédient de items, choisis dans ses candidates l'aliment de la table Ciqual qui \
        correspond le mieux à l'ingrédient tel qu'acheté et pesé : cru sauf mention contraire, sec pour les \
        légumineuses et féculents secs, appertisé égoutté pour une conserve. Réponds uniquement avec le JSON du \
        schéma : une entrée par ingrédient, index identique, code = code du candidat choisi, ou null si aucun \
        candidat ne convient.
        """
    }

    struct FoodMatchInput: Encodable {
        var task = "food_match"
        var items: [FoodQuestion]
    }

    public static func foodMatchInput(_ questions: [FoodQuestion]) -> String {
        encodeAny(FoodMatchInput(items: questions))
    }

    private static func encodeAny(_ value: some Encodable) -> String {
        guard let data = try? AIResponseDecoder.encoder.encode(value) else { return "{}" }
        return String(bytes: data, encoding: .utf8) ?? "{}"
    }
}
