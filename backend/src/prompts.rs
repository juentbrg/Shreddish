//! Consignes système imposées par le serveur et contrôle de l'entrée (spec 023 FR-2311, FR-2312).
//! Copies de `PromptBuilder` (app iOS), gardées en phase par `PromptExportTests`.

use serde_json::Value;

use crate::error::AppError;

const SYSTEM: &str = include_str!("../prompts/system.txt");
const RECIPE: &str = include_str!("../prompts/recipe.txt");
const FOOD_MATCH: &str = include_str!("../prompts/food_match.txt");

/// Entrée de plus de 32 Ko : refus.
pub const MAX_INPUT_BYTES: usize = 32 * 1024;
/// Texte de plus de 1 000 caractères dans l'entrée : refus.
pub const MAX_STRING_CHARS: usize = 1_000;

/// Consignes système d'un schéma de réponse ; `None` : schéma inconnu.
pub fn instructions(schema: &str) -> Option<&'static str> {
    match schema {
        "WeekPlanResponse" | "DayPlanResponse" | "MealReplacementResponse" => Some(SYSTEM),
        "RecipeResponse" => Some(RECIPE),
        "FoodMatchResponse" => Some(FOOD_MATCH),
        _ => None,
    }
}

/// Entrée attendue : JSON de contexte construit par l'app, tâche conforme au schéma, textes courts.
pub fn check_input(schema: &str, input: &str) -> Result<(), AppError> {
    let invalid = |reason: &str| {
        Err(AppError::InvalidRequest(format!(
            "Entrée refusée : {reason}."
        )))
    };
    if input.len() > MAX_INPUT_BYTES {
        return invalid("trop longue");
    }
    let Ok(Value::Object(object)) = serde_json::from_str::<Value>(input) else {
        return invalid("JSON de contexte attendu");
    };
    let task = object.get("task").and_then(Value::as_str);
    let expected = match schema {
        "WeekPlanResponse" => task == Some("week"),
        "DayPlanResponse" => task == Some("day"),
        "MealReplacementResponse" => task == Some("replace_meal"),
        "FoodMatchResponse" => task == Some("food_match"),
        "RecipeResponse" => {
            task == Some("recipe") && object.get("meal").is_some_and(Value::is_object)
        }
        _ => false,
    };
    if !expected {
        return invalid("tâche non conforme au schéma");
    }
    if !short_strings(&Value::Object(object)) {
        return invalid("texte trop long");
    }
    Ok(())
}

fn short_strings(value: &Value) -> bool {
    match value {
        Value::String(text) => text.chars().count() <= MAX_STRING_CHARS,
        Value::Array(items) => items.iter().all(short_strings),
        Value::Object(map) => map
            .iter()
            .all(|(key, item)| key.chars().count() <= 64 && short_strings(item)),
        _ => true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_admitted_schema_has_server_instructions() {
        for schema in [
            "WeekPlanResponse",
            "DayPlanResponse",
            "MealReplacementResponse",
            "RecipeResponse",
            "FoodMatchResponse",
        ] {
            assert!(
                instructions(schema).is_some_and(|text| text.len() > 100),
                "{schema}"
            );
        }
        assert!(instructions("Autre").is_none());
    }

    /// Entrées types de l'app (`PromptExportTests`, `tests/fixtures/inputs/`) : toutes acceptées.
    #[test]
    fn real_app_inputs_are_accepted() {
        let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/inputs");
        let mut count = 0;
        for entry in std::fs::read_dir(dir).unwrap() {
            let path = entry.unwrap().path();
            let schema = path.file_stem().unwrap().to_str().unwrap().to_string();
            let input = std::fs::read_to_string(&path).unwrap();
            assert!(check_input(&schema, &input).is_ok(), "{schema} refusé");
            count += 1;
        }
        assert_eq!(count, 5);
    }

    #[test]
    fn input_must_be_the_app_context() {
        assert!(check_input("WeekPlanResponse", r#"{"task":"week","day_count":7}"#).is_ok());
        assert!(
            check_input(
                "RecipeResponse",
                r#"{"task":"recipe","meal":{"name":"Riz"}}"#
            )
            .is_ok()
        );
        for (schema, input) in [
            ("WeekPlanResponse", "Écris-moi un poème."),
            ("WeekPlanResponse", r#"{"task":"day"}"#),
            ("RecipeResponse", r#"{"task":"week","meal":{}}"#),
            ("DayPlanResponse", r#"["task","day"]"#),
        ] {
            assert!(check_input(schema, input).is_err(), "{input}");
        }
        let long = format!(
            r#"{{"task":"day","previous_attempt_feedback":"{}"}}"#,
            "x".repeat(1_001)
        );
        assert!(check_input("DayPlanResponse", &long).is_err());
        let huge = format!(
            r#"{{"task":"day","avoid":[{}]}}"#,
            vec!["\"x\""; 20_000].join(",")
        );
        assert!(check_input("DayPlanResponse", &huge).is_err());
    }
}
