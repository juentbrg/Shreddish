//! Jeton d'installation : génération, empreinte, extracteur (spec 022 FR-2201, FR-2202).

use axum::extract::FromRequestParts;
use axum::http::header::AUTHORIZATION;
use axum::http::request::Parts;
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use sea_orm::{ColumnTrait, EntityTrait, QueryFilter};
use sha2::{Digest, Sha256};

use crate::AppState;
use crate::entities::installs;
use crate::error::AppError;

/// Jeton aléatoire de 256 bits, base64url.
pub fn new_token() -> String {
    URL_SAFE_NO_PAD.encode(rand::random::<[u8; 32]>())
}

pub fn token_hash(token: &str) -> Vec<u8> {
    Sha256::digest(token.as_bytes()).to_vec()
}

/// Installation authentifiée par `Authorization: Bearer <jeton>`, non révoquée.
pub struct AuthInstall(pub installs::Model);

impl FromRequestParts<AppState> for AuthInstall {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let token = parts
            .headers
            .get(AUTHORIZATION)
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.strip_prefix("Bearer "))
            .filter(|token| !token.is_empty())
            .ok_or(AppError::Unauthenticated)?;
        installs::Entity::find()
            .filter(installs::Column::TokenHash.eq(token_hash(token)))
            .filter(installs::Column::RevokedAt.is_null())
            .one(&state.db)
            .await?
            .map(Self)
            .ok_or(AppError::Unauthenticated)
    }
}
