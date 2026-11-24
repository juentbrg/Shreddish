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
    /// Jeûne intermittent (spec 015) : fenêtre de repas « HH:mm-HH:mm ».
    public var eatingWindow: String?
    /// Régimes (spec 017).
    public var diets: [Diet]?
    /// Langue de l'appareil (code ISO, ex. « en ») ; nil = français (spec 017, FR-1712).
    public var language: String?

    public init(
        mealsPerDay: Int, maxPrepMinutes: Int, weeklyBudgetEur: Double, budgetTolerance: Double,
        allergies: [String], dislikedFoods: [String], likedFoods: [String], equipment: [String],
        batchCooking: Bool, ingredientAvailability: IngredientAvailability,
        ownedSupplements: [OwnedSupplement] = [], trainingTime: String? = nil, trainingSessionsPerWeek: Int? = nil,
        eatingWindow: String? = nil, diets: [Diet]? = nil
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
        self.eatingWindow = eatingWindow
        self.diets = diets
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
    /// Goût du produit (ex. « chocolat »).
    public var flavor: String?

    public init(name: String, info: SupplementInfo = SupplementInfo()) {
        self.name = name
        let flavor = info.flavor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.flavor = flavor.isEmpty ? nil : flavor
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
        /// Nombre de jours d'une période (task "week").
        var dayCount: Int?
        var existingDayMeals: [MealSummary]?
        var mealTypeToReplace: MealType?
        var remainingTargets: TargetsPayload?
        var avoidMealNames: [String]?
        var costLimitEur: Double?
        /// Retour sur l'essai précédent (coût trop élevé), spec 004.
        var previousAttemptFeedback: String?
        /// Ingrédients déjà chez l'utilisateur, à écouler en priorité (spec 013).
        var ingredientsToUse: [PantryItem]?
        /// Recettes sauvegardées à replacer (spec 014).
        var recipesToInclude: [RecipeItem]?
    }

    /// Recette sauvegardée envoyée à l'IA : nom, type et ingrédients, sans étapes.
    struct RecipeItem: Encodable {
        var type: MealType
        var name: String
        var ingredients: [PantryItem]
    }

    static func recipesPayload(_ recipes: [MealDTO]) -> [RecipeItem]? {
        recipes.isEmpty ? nil : recipes.map { RecipeItem(type: $0.type, name: $0.name, ingredients: $0.ingredients.map(PantryItem.init)) }
    }

    /// Ingrédient à écouler envoyé à l'IA.
    struct PantryItem: Encodable {
        var name: String
        var quantity: Double
        var unit: String

        init(_ ingredient: IngredientDTO) {
            name = ingredient.name
            quantity = ingredient.quantity
            unit = ingredient.unit
        }
    }

    static func pantryPayload(_ pantry: [IngredientDTO]) -> [PantryItem]? {
        pantry.isEmpty ? nil : pantry.map(PantryItem.init)
    }

    public static func weekInput(
        targets: MacroTotals, goal: Goal, preferences: PromptPreferences, feedback: String? = nil,
        pantry: [IngredientDTO] = [], recipes: [MealDTO] = [], dayCount: Int = 7
    ) -> String {
        encode(Input(
            task: "week", targets: TargetsPayload(targets), goal: goal, preferences: preferences, dayCount: dayCount,
            previousAttemptFeedback: feedback, ingredientsToUse: pantryPayload(pantry), recipesToInclude: recipesPayload(recipes)
        ))
    }

    public static func dayInput(
        targets: MacroTotals, goal: Goal, preferences: PromptPreferences, dayOffset: Int, avoidMealNames: [String],
        costLimitEur: Double, feedback: String? = nil, pantry: [IngredientDTO] = [], recipes: [MealDTO] = []
    ) -> String {
        encode(Input(
            task: "day", targets: TargetsPayload(targets), goal: goal, preferences: preferences,
            dayOffset: dayOffset, avoidMealNames: avoidMealNames, costLimitEur: BudgetMath.cents(costLimitEur),
            previousAttemptFeedback: feedback, ingredientsToUse: pantryPayload(pantry), recipesToInclude: recipesPayload(recipes)
        ))
    }

    /// Message envoyé au nouvel essai quand le coût calculé par l'application dépasse le plafond (spec 018).
    public static func overBudgetFeedback(costEur: Double, ceilingEur: Double, expensive: [IngredientDTO] = []) -> String {
        let items = expensive.map { "\($0.name) \(String(format: "%.2f", $0.costEur)) €" }.joined(separator: ", ")
        return "Proposition précédente : \(BudgetMath.cents(costEur)) € au prix moyen en supermarché, pour un plafond de "
            + "\(BudgetMath.cents(ceilingEur)) €." + (items.isEmpty ? "" : " Les plus chers : \(items).")
            + " Remplace les produits chers (yaourt nature 0 % ou fromage blanc au lieu du skyr, œufs, légumineuses, "
            + "poulet entier ou cuisses, légumes surgelés), macros identiques."
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

    /// Jeûne intermittent (spec 015), règle du prompt système.
    static let fastingRules = """
        - eating_window : jeûne intermittent, tous les repas entre ces deux heures (premier et dernier repas \
        inclus). Pas de breakfast si la fenêtre commence après 10:00 : le premier repas est un lunch, \
        complète avec des snacks. Répartis les apports sur la fenêtre, repas du soir pas plus lourd que le déjeuner.
        """

    /// Régimes (spec 017), règle du prompt système ; langue des plats.
    static let dietRules = """
        - language : si présent, noms des plats (name) et étapes dans cette langue ; noms d'ingrédients \
        toujours en français, tels qu'achetés en France (table Ciqual).
        - diets : régimes cumulés, à respecter dans chaque ingrédient (vegetarian : ni viande ni poisson ; vegan : \
        aucun produit animal, ni œuf, lait, fromage, miel, whey ; pescatarian : poisson oui, viande non ; halal : \
        ni porc ni alcool ; kosher : ni porc ni fruits de mer, jamais viande et laitage dans le même repas ; \
        gluten_free : ni blé, pâtes, pain, semoule, avoine, sauf version « sans gluten » ; lactose_free : laitages \
        « sans lactose » ou végétaux). Protéines de substitution : œufs, tofu, tempeh, légumineuses, seitan si \
        autorisé, selon ingredient_availability.
        """

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
        \(dietRules)
        - Exactement meals_per_day repas par jour, collations incluses (types : breakfast, lunch, dinner, snack).
        - Macros par jour : kcal à ±5 % de targets.kcal, protéines ≥ targets.protein_g, glucides et lipides \
        à ±10 % de targets.carbs_g et targets.fat_g. Ne compense jamais un manque de protéines par des glucides.
        - Valeurs cohérentes : kcal ≈ 4 × protein_g + 4 × carbs_g + 9 × fat_g. L'application recalcule les \
        macros depuis la table Ciqual et ajuste les portions : nomme chaque ingrédient précisément, tel \
        qu'acheté (ex. « Riz basmati cru », « Lentilles vertes sèches », « Thon au naturel en boîte \
        égoutté », « Fromage blanc 0 % »).
        - Budget : weekly_budget_eur (task "week") ou cost_limit_eur (task "day", "replace_meal"), au prix moyen \
        en supermarché en France ; l'application calcule le coût. Budget serré : produits les moins chers par \
        gramme de protéine (œufs, yaourt nature 0 %, fromage blanc 0 %, lentilles, pois chiches, thon en boîte, \
        poulet entier ou cuisses, porc, légumes surgelés, riz, pâtes, flocons d'avoine) plutôt que premium (skyr, \
        saumon, avocat, fruits secs, portions individuelles). Jamais un motif d'infeasible.
        - previous_attempt_feedback : si présent, corrige ce qui y est signalé.
        - Produits frais et conserves entamés (viande, crème, conserve, brique) : finis le paquet sur des repas \
        proches plutôt que d'en laisser (ex. boîte de 400 g de pois chiches = 240 g égouttés sur 2 repas).
        - ingredients_to_use : ingrédients déjà chez l'utilisateur (quantités disponibles au plus), à utiliser \
        en priorité cette semaine, les plus périssables dans les premiers jours. L'application les déduit des \
        courses.
        - recipes_to_include : recettes que l'utilisateur veut revoir. Place chacune une fois sur les jours \
        générés, à son type de repas, avec le même nom et les mêmes ingrédients ; ajuste seulement les \
        quantités si les cibles l'exigent.
        - ingredient_availability : "everywhere" = uniquement des ingrédients basiques trouvables dans tout \
        supermarché et en hard discount (Lidl, Aldi), aucun produit de niche (tempeh, seitan, spiruline, levure \
        maltée, sirop d'agave, farines spéciales, superaliments) ; "supermarket" = rayon d'un grand \
        supermarché, sans magasin spécialisé ; "specialty" = magasins bio ou spécialisés acceptés.
        - Équipement : plaques, casserole, poêle et four toujours disponibles, en plus de equipment. Riz, pâtes, \
        semoule et pommes de terre se cuisent à la casserole : aucun cuiseur nécessaire, varie les féculents \
        (riz au moins 2 fois par semaine sauf si exclu).
        - owned_supplements : compléments déjà possédés, coût 0. kind "macro" (whey, gainer…) : utilise-le pour \
        atteindre les protéines quand c'est pertinent (collation, après l'entraînement), comme ingrédient en g, \
        aisle "autre". Si serving_g et les valeurs par dose sont présents, \
        macros du complément = quantité ÷ serving_g × kcal_per_serving, protein_g_per_serving, \
        carbs_g_per_serving, fat_g_per_serving ; indique la dose en scoops (ex. « 1 scoop de 30 g »). \
        kind "dose" (créatine, vitamines, oméga-3…) : ni macro ni ingrédient, la prise est ajoutée par \
        l'application. flavor : goût du produit, à n'utiliser que là où il va (ex. chocolat : sucré, jamais salé).
        - training_time et training_sessions_per_week : place la collation ou le repas protéiné autour de \
        l'entraînement ; sans heure connue, suppose une séance en fin de journée.
        - time : heure conseillée « HH:mm » de chaque repas, cohérente sur la journée (petit-déjeuner 7:00-9:00, \
        déjeuner 12:00-13:30, dîner 19:00-21:00, collation selon l'entraînement).
        \(fastingRules)
        - Quantités en g, ml ou piece, pesées crues / non cuites. unit "piece" seulement pour ce qui se compte \
        (œufs, fruits, tortillas), avec piece_g = poids d'une pièce en g ; sinon piece_g = null.
        - Semaine et jour : pas d'étapes, les recettes sont rédigées ensuite.
        - Variété : un même plat principal au plus 2 fois par semaine, sauf préparation batch cooking. Change \
        vraiment de plat, pas seulement de nom : la même association protéine principale + féculent (ex. \
        poulet + riz, thon + pâtes) au plus 2 fois par semaine sur les déjeuners et dîners.
        - Privilégie liked_foods. Avocat, banane, pomme, citron, poivron, oignon et autre fruit ou légume entamé : ½ pièce minimum.
        - task "week" : toujours day_count jours, day_offset 0 à day_count - 1 (0 = jour de génération), \
        weekly_budget_eur couvre ces jours. La période est fixe : jamais un motif d'infeasible.
        - batch_cooking vrai : 1 ou 2 prep_sessions (index 0, 1), et les repas issus d'une session ont \
        prep_session_ref = index de la session. batch_cooking faux : prep_sessions vide, prep_session_ref null.
        - task "day" : régénère uniquement le jour day_offset, différent de avoid_meal_names.
        - task "replace_meal" : propose un seul repas de type meal_type_to_replace, proche de remaining_targets, \
        différent de avoid_meal_names et de existing_day_meals, avec ses étapes. \(recipeRules)
        - Si allergies, exclusions et temps sont impossibles à respecter ensemble : remplis infeasible avec la \
        raison en une phrase, sans jamais ignorer une contrainte ; sinon infeasible = null. Jamais pour le \
        budget, le prix, la longueur ou le format de la réponse : produis tous les jours demandés.
        - Noms de plats, étapes et textes en français, sauf language indiqué.
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
        avec le JSON demandé par le schéma, en français sauf si language est indiqué : étapes dans cette langue.
        - Utilise exactement les ingrédients et quantités de meal.ingredients, sans en ajouter d'autres que \
        sel, poivre, épices, herbes et eau. Chaque quantité citée dans les étapes est celle de meal.ingredients, \
        jamais arrondie ni modifiée. pieces renseigné : écris la part, jamais les grammes (ex. « ½ avocat »).
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
            /// Fruit ou légume par moitié : nombre de pièces (0,5 = ½).
            var pieces: Double?
            /// Complément possédé : son goût.
            var flavor: String?
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
        var language: String?
    }

    /// Goût du complément possédé cité par cet ingrédient (« Whey » → « chocolat »).
    static func flavor(of ingredient: String, in supplements: [OwnedSupplement]) -> String? {
        let name = TextNormalizer.singular(ingredient)
        return supplements.first { name.contains(TextNormalizer.singular($0.name)) }?.flavor
    }

    public static func recipeInput(meal: MealDTO, supplementDoses: [String], preferences: PromptPreferences) -> String {
        let payload = RecipeInput.MealPayload(
            type: meal.type, name: meal.name, time: meal.time, prepMinutes: meal.prepMinutes,
            ingredients: meal.ingredients.map {
                .init(
                    name: $0.name, quantity: $0.quantity, unit: $0.unit, pieces: WholeProduce.pieces(of: $0),
                    flavor: flavor(of: $0.name, in: preferences.ownedSupplements)
                )
            }
        )
        return encodeAny(RecipeInput(
            meal: payload, supplementDoses: supplementDoses, equipment: preferences.equipment,
            trainingTime: preferences.trainingTime, language: preferences.language
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
