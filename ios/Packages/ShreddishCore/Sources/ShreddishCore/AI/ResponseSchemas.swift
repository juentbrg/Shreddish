import Foundation

/// Schémas JSON stricts envoyés à l'API (`text.format.json_schema`), copie de
/// contracts/ai-meal.schema.json. Strict : tout champ requis, `additionalProperties: false`.
public enum ResponseSchemas {
    public enum Kind: String, Sendable {
        case week = "WeekPlanResponse"
        case day = "DayPlanResponse"
        case meal = "MealReplacementResponse"
    }

    /// Schéma prêt pour `JSONSerialization` (dictionnaire).
    public static func schema(_ kind: Kind) -> [String: Any] {
        let root: String = switch kind {
        case .week:
            """
            {"type":"object","additionalProperties":false,"required":["infeasible","prep_sessions","days"],
             "properties":{"infeasible":{"$ref":"#/$defs/infeasible"},
              "prep_sessions":{"type":"array","items":{"$ref":"#/$defs/prep_session"}},
              "days":{"type":"array","items":{"$ref":"#/$defs/day"}}}}
            """
        case .day:
            """
            {"type":"object","additionalProperties":false,"required":["infeasible","day"],
             "properties":{"infeasible":{"$ref":"#/$defs/infeasible"},"day":{"$ref":"#/$defs/day"}}}
            """
        case .meal:
            """
            {"type":"object","additionalProperties":false,"required":["infeasible","meal"],
             "properties":{"infeasible":{"$ref":"#/$defs/infeasible"},"meal":{"$ref":"#/$defs/meal"}}}
            """
        }
        var object = parse(root)
        object["$defs"] = parse(definitions)
        return object
    }

    private static func parse(_ json: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    }

    private static let definitions = """
    {
     "ingredient":{"type":"object","additionalProperties":false,
      "required":["name","quantity","unit","aisle","unit_price_eur","cost_eur"],
      "properties":{"name":{"type":"string"},"quantity":{"type":"number"},
       "unit":{"type":"string","enum":["g","ml","piece"]},
       "aisle":{"type":"string","enum":["fruits_legumes","viande_poisson","cremerie","epicerie","surgeles","boulangerie","autre"]},
       "unit_price_eur":{"type":"number"},"cost_eur":{"type":"number"}}},
     "meal":{"type":"object","additionalProperties":false,
      "required":["type","name","ingredients","steps","prep_minutes","cost_eur","kcal","protein_g","carbs_g","fat_g",
       "prep_session_ref","time"],
      "properties":{"type":{"type":"string","enum":["breakfast","lunch","dinner","snack"]},
       "name":{"type":"string"},
       "ingredients":{"type":"array","items":{"$ref":"#/$defs/ingredient"}},
       "steps":{"type":"array","items":{"type":"string"}},
       "prep_minutes":{"type":"integer"},"cost_eur":{"type":"number"},"kcal":{"type":"number"},
       "protein_g":{"type":"number"},"carbs_g":{"type":"number"},"fat_g":{"type":"number"},
       "prep_session_ref":{"type":["integer","null"]},
       "time":{"type":["string","null"],"pattern":"^([01][0-9]|2[0-3]):[0-5][0-9]$"}}},
     "day":{"type":"object","additionalProperties":false,"required":["day_offset","meals"],
      "properties":{"day_offset":{"type":"integer"},"meals":{"type":"array","items":{"$ref":"#/$defs/meal"}}}},
     "prep_session":{"type":"object","additionalProperties":false,
      "required":["index","day_offset","title","duration_minutes","steps"],
      "properties":{"index":{"type":"integer"},"day_offset":{"type":"integer"},"title":{"type":"string"},
       "duration_minutes":{"type":"integer"},"steps":{"type":"array","items":{"type":"string"}}}},
     "infeasible":{"type":["string","null"]}
    }
    """
}
