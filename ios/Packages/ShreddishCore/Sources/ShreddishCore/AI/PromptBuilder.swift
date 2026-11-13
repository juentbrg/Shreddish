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
    /// Nom de l'enseigne : produits et prix de ce magasin (spec 003).
    public var store: String
    /// Compléments déjà possédés (spec 004), avec protéines par dose (spec 007).
    public var ownedSupplements: [OwnedSupplement]
    /// Heure d'entraînement habituelle « HH:mm ».
    public var trainingTime: String?
    /// Séances par semaine, depuis le profil.
    public var trainingSessionsPerWeek: Int?
    /// Secteur des courses (spec 005) : « Toulouse, France » ou « France ».
    public var location: String

    public init(
        mealsPerDay: Int, maxPrepMinutes: Int, weeklyBudgetEur: Double, budgetTolerance: Double,
        allergies: [String], dislikedFoods: [String], likedFoods: [String], equipment: [String],
        batchCooking: Bool, ingredientAvailability: IngredientAvailability, store: String,
        ownedSupplements: [OwnedSupplement] = [], trainingTime: String? = nil, trainingSessionsPerWeek: Int? = nil,
        location: String = "France"
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
        self.store = store
        self.ownedSupplements = ownedSupplements
        self.trainingTime = trainingTime
        self.trainingSessionsPerWeek = trainingSessionsPerWeek
        self.location = location
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
    }

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
        - Valeurs cohérentes : kcal ≈ 4 × protein_g + 4 × carbs_g + 9 × fat_g.
        - Budget : objectif, jamais bloquant. Coût total de la semaine ≤ weekly_budget_eur ; dépassement au plus de budget_tolerance \
        (0,1 = 10 %), à éviter. task "day" ou "replace_meal" : coût total ≤ cost_limit_eur. Budget serré : \
        choisis les produits les moins chers par gramme de protéine (œufs, yaourt nature 0 %, fromage blanc 0 %, \
        lentilles, pois chiches, thon en boîte, poulet entier ou cuisses, porc, légumes surgelés, riz, pâtes, \
        flocons d'avoine) plutôt que les produits premium (skyr, saumon, avocat, fruits secs, portions individuelles). \
        Ne remplis jamais infeasible pour le budget ou le prix : propose le planning le moins cher possible, \
        l'application recalcule le coût et prévient si besoin.
        - previous_attempt_feedback : si présent, corrige ce qui y est signalé.
        - Prix (store, location) : n'utilise que des produits vendus dans l'enseigne store, marque distributeur \
        en priorité. Pour chaque ingrédient, unit_price_eur = prix réaliste en rayon cette année dans cette \
        enseigne autour de location, en € par kg (unit "g"), par litre (unit "ml") ou par pièce (unit "piece"), \
        pour le format le plus économique couramment vendu. Tiens compte du positionnement de l'enseigne \
        (hard discount et hypermarché moins chers, proximité et centre-ville plus chers) et du secteur \
        (grande ville concurrentielle moins chère ; petite ville, montagne ou zone touristique plus chère, \
        souvent +10 à +25 % en supérette). cost_eur = quantity × unit_price_eur (÷ 1000 pour g et ml).
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
        kind "dose" (créatine, vitamines, oméga-3…) : aucune macro, ni ingrédient ; ajoute la prise dans les \
        étapes du repas le plus adapté, avec dose × doses_per_day exactement (ex. « Prends 5 g de créatine \
        avec ce repas »), une fois par jour sauf doses_per_day > 1. Indique le moment de prise dans les étapes \
        (ex. « dans les 60 min après la séance », « créatine 5 g, à n'importe quel repas »).
        - training_time et training_sessions_per_week : place la collation ou le repas protéiné autour de \
        l'entraînement ; sans heure connue, suppose une séance en fin de journée.
        - time : heure conseillée « HH:mm » de chaque repas, cohérente sur la journée (petit-déjeuner 7:00-9:00, \
        déjeuner 12:00-13:30, dîner 19:00-21:00, collation selon l'entraînement).
        - Quantités en g, ml ou piece, pesées crues / non cuites. cost_eur = coût de la quantité utilisée, \
        recalculé par l'application depuis unit_price_eur.
        - Étapes détaillées pour cuisiner sans expérience : 4 à 12 étapes selon le plat (2 à 3 pour une \
        collation sans cuisson). Chaque étape précise quantités, ustensile, intensité du feu ou température, \
        durée et repère visuel (ex. « Rince 80 g de riz à l'eau froide, puis verse-le dans une casserole avec \
        160 ml d'eau salée. Porte à ébullition à feu vif, couvre, baisse à feu doux 12 min sans soulever le \
        couvercle, puis laisse reposer 5 min hors du feu. »). Inclus l'assaisonnement.
        - Variété : un même plat principal au plus 2 fois par semaine, sauf préparation batch cooking.
        - Privilégie liked_foods.
        - day_offset 0 = jour de génération ; une semaine couvre les jours 0 à 6.
        - batch_cooking vrai : 1 ou 2 prep_sessions (index 0, 1), et les repas issus d'une session ont \
        prep_session_ref = index de la session. batch_cooking faux : prep_sessions vide, prep_session_ref null.
        - task "day" : régénère uniquement le jour day_offset, différent de avoid_meal_names.
        - task "replace_meal" : propose un seul repas de type meal_type_to_replace, proche de remaining_targets, \
        différent de avoid_meal_names et de existing_day_meals.
        - Si allergies, exclusions et temps sont impossibles à respecter ensemble : remplis infeasible avec la \
        raison en une phrase, sans jamais ignorer une contrainte ; sinon infeasible = null. Jamais pour le \
        budget, le prix, la longueur ou le format de la réponse : produis tous les jours demandés.
        - Noms de plats, étapes et textes en français.
        """
    }
}
