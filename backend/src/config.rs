//! Configuration lue dans l'environnement.

use std::env;
use std::net::SocketAddr;

use crate::quota::Kind;

/// Limites quotidiennes par type d'action IA (spec 022 FR-2204). Valeurs par défaut : dev, non arrêtées.
#[derive(Clone, Copy, Debug)]
pub struct Limits {
    pub week: i32,
    pub meal: i32,
    pub day: i32,
    pub recipe: i32,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            week: 3,
            meal: 30,
            day: 10,
            recipe: 60,
        }
    }
}

impl Limits {
    pub fn of(&self, kind: Kind) -> i32 {
        match kind {
            Kind::Week => self.week,
            Kind::Meal => self.meal,
            Kind::Day => self.day,
            Kind::Recipe => self.recipe,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VerifierKind {
    /// Preuve de test acceptée (spec 022 FR-2210). Interdit en production.
    Dev,
    /// Aucune vérification d'achat possible.
    None,
}

pub struct Config {
    pub database_url: String,
    pub bind_addr: SocketAddr,
    pub limits: Limits,
    pub verifier: VerifierKind,
}

impl Config {
    pub fn from_env() -> Result<Self, String> {
        let database_url =
            env::var("DATABASE_URL").map_err(|_| "DATABASE_URL manquant".to_string())?;
        let bind_addr = var_or("BIND_ADDR", "127.0.0.1:8080")
            .parse()
            .map_err(|e| format!("BIND_ADDR invalide : {e}"))?;
        let defaults = Limits::default();
        let limits = Limits {
            week: limit("QUOTA_WEEK", defaults.week)?,
            meal: limit("QUOTA_MEAL", defaults.meal)?,
            day: limit("QUOTA_DAY", defaults.day)?,
            recipe: limit("QUOTA_RECIPE", defaults.recipe)?,
        };
        let verifier = match var_or("ENTITLEMENT_VERIFIER", "none").as_str() {
            "dev" => VerifierKind::Dev,
            "none" => VerifierKind::None,
            other => return Err(format!("ENTITLEMENT_VERIFIER inconnu : {other}")),
        };
        if verifier == VerifierKind::Dev && var_or("APP_ENV", "development") == "production" {
            return Err("ENTITLEMENT_VERIFIER=dev interdit en production".into());
        }
        Ok(Self {
            database_url,
            bind_addr,
            limits,
            verifier,
        })
    }
}

fn var_or(name: &str, default: &str) -> String {
    env::var(name).unwrap_or_else(|_| default.into())
}

fn limit(name: &str, default: i32) -> Result<i32, String> {
    match env::var(name) {
        Err(_) => Ok(default),
        Ok(value) => value
            .parse::<i32>()
            .ok()
            .filter(|v| *v >= 0)
            .ok_or(format!("{name} invalide : {value}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Une seule fonction : variables d'environnement partagées par tout le processus.
    #[test]
    fn reads_limits_and_refuses_dev_verifier_in_production() {
        // SAFETY : seul test du binaire qui touche l'environnement.
        unsafe {
            env::set_var("DATABASE_URL", "postgres://x");
            env::set_var("QUOTA_WEEK", "5");
            env::set_var("ENTITLEMENT_VERIFIER", "dev");
            env::set_var("APP_ENV", "development");
        }
        let config = Config::from_env().unwrap();
        assert_eq!((config.limits.week, config.limits.meal), (5, 30));
        assert_eq!(config.verifier, VerifierKind::Dev);

        unsafe { env::set_var("APP_ENV", "production") };
        assert!(Config::from_env().is_err());

        unsafe {
            env::set_var("APP_ENV", "development");
            env::set_var("QUOTA_WEEK", "-1");
        }
        assert!(Config::from_env().is_err());
    }
}
