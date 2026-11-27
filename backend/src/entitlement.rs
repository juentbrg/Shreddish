//! Droits d'accès par installation (spec 022 FR-2208 à FR-2210).

use async_trait::async_trait;
use chrono::{DateTime, Duration, Utc};
use serde::Serialize;

use crate::error::AppError;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Entitlement {
    /// Aucun abonnement actif.
    None,
    /// Abonnement payant ou offre d'introduction d'une semaine (spec 017 FR-1715), non expiré.
    Subscribed,
}

impl Entitlement {
    /// Droit effectif à `now` : abonnement expiré traité comme `None`.
    pub fn effective(stored: &str, expires_at: Option<DateTime<Utc>>, now: DateTime<Utc>) -> Self {
        match stored {
            "subscribed" if expires_at.is_some_and(|expiry| expiry > now) => Self::Subscribed,
            _ => Self::None,
        }
    }
}

/// Vérifie une preuve d'achat et renvoie la date d'expiration de l'abonnement.
#[async_trait]
pub trait Verifier: Send + Sync {
    async fn verify(&self, proof: &str, now: DateTime<Utc>) -> Result<DateTime<Utc>, AppError>;
}

/// Dev seulement : preuve `dev-subscription:<jours>`, 1 à 366 jours (essai : 7).
pub struct DevVerifier;

#[async_trait]
impl Verifier for DevVerifier {
    async fn verify(&self, proof: &str, now: DateTime<Utc>) -> Result<DateTime<Utc>, AppError> {
        proof
            .strip_prefix("dev-subscription:")
            .and_then(|days| days.parse::<i64>().ok())
            .filter(|days| (1..=366).contains(days))
            .map(|days| now + Duration::days(days))
            .ok_or_else(|| AppError::InvalidRequest("Preuve d'achat invalide.".into()))
    }
}

/// Aucune vérification possible (pas encore de vérification App Store).
pub struct NoVerifier;

#[async_trait]
impl Verifier for NoVerifier {
    async fn verify(&self, _proof: &str, _now: DateTime<Utc>) -> Result<DateTime<Utc>, AppError> {
        Err(AppError::InvalidRequest(
            "Vérification d'achat indisponible.".into(),
        ))
    }
}
