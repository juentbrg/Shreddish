//! Preuve d'achat : l'installation devient abonnée (spec 022 FR-2210).

use axum::extract::State;
use axum::routing::post;
use axum::{Json, Router};
use chrono::{DateTime, Utc};
use sea_orm::{ActiveModelTrait, IntoActiveModel, Set};
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::auth::AuthInstall;
use crate::entitlement::Entitlement;
use crate::error::{ApiJson, ApiResult};

#[derive(Deserialize)]
struct VerifyRequest {
    proof: String,
}

#[derive(Serialize)]
struct Verified {
    entitlement: Entitlement,
    expires_at: DateTime<Utc>,
}

pub fn router() -> Router<AppState> {
    Router::new().route("/v1/entitlements/verify", post(verify))
}

async fn verify(
    State(state): State<AppState>,
    AuthInstall(install): AuthInstall,
    ApiJson(request): ApiJson<VerifyRequest>,
) -> ApiResult<Json<Verified>> {
    let expires_at = state.verifier.verify(&request.proof, Utc::now()).await?;
    let mut install = install.into_active_model();
    install.entitlement = Set("subscribed".into());
    install.subscription_expires_at = Set(Some(expires_at));
    install.update(&state.db).await?;
    Ok(Json(Verified {
        entitlement: Entitlement::Subscribed,
        expires_at,
    }))
}
