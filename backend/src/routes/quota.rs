//! Lecture et consommation du quota IA (spec 022 FR-2206, FR-2207).

use axum::extract::State;
use axum::routing::{get, post};
use axum::{Json, Router};
use chrono::Utc;
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::auth::AuthInstall;
use crate::error::{ApiJson, ApiResult};
use crate::quota::{self, Kind, Snapshot, Usage};

#[derive(Deserialize)]
struct ConsumeRequest {
    kind: Kind,
}

#[derive(Serialize)]
struct Consumed {
    kind: Kind,
    #[serde(flatten)]
    usage: Usage,
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/v1/quota", get(read))
        .route("/v1/quota/consume", post(consume))
}

async fn read(
    State(state): State<AppState>,
    AuthInstall(install): AuthInstall,
) -> ApiResult<Json<Snapshot>> {
    Ok(Json(
        quota::snapshot(&state.db, &install, &state.limits, Utc::now()).await?,
    ))
}

async fn consume(
    State(state): State<AppState>,
    AuthInstall(install): AuthInstall,
    ApiJson(request): ApiJson<ConsumeRequest>,
) -> ApiResult<Json<Consumed>> {
    let usage = quota::consume(
        &state.db,
        install.id,
        request.kind,
        &state.limits,
        Utc::now(),
    )
    .await?;
    Ok(Json(Consumed {
        kind: request.kind,
        usage,
    }))
}
