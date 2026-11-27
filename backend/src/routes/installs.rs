//! Enregistrement d'une installation (spec 022 FR-2201).

use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::post;
use axum::{Json, Router};
use chrono::Utc;
use sea_orm::{ActiveModelTrait, Set};
use serde::Serialize;
use uuid::Uuid;

use crate::AppState;
use crate::auth::{new_token, token_hash};
use crate::entities::installs;
use crate::error::ApiResult;

#[derive(Serialize)]
struct Registered {
    install_id: Uuid,
    token: String,
}

pub fn router() -> Router<AppState> {
    Router::new().route("/v1/installs", post(register))
}

async fn register(State(state): State<AppState>) -> ApiResult<(StatusCode, Json<Registered>)> {
    let token = new_token();
    let install = installs::ActiveModel {
        id: Set(Uuid::new_v4()),
        token_hash: Set(token_hash(&token)),
        entitlement: Set("trial".into()),
        subscription_expires_at: Set(None),
        created_at: Set(Utc::now()),
        revoked_at: Set(None),
    }
    .insert(&state.db)
    .await?;
    Ok((
        StatusCode::CREATED,
        Json(Registered {
            install_id: install.id,
            token,
        }),
    ))
}
