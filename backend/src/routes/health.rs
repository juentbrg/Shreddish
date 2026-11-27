//! État du service, sans jeton (spec 022 FR-2212).

use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;

use crate::AppState;

#[derive(Serialize)]
struct Health {
    status: &'static str,
    database: bool,
}

pub fn router() -> Router<AppState> {
    Router::new().route("/health", get(health))
}

async fn health(State(state): State<AppState>) -> (StatusCode, Json<Health>) {
    let database = state.db.ping().await.is_ok();
    let code = if database {
        StatusCode::OK
    } else {
        StatusCode::SERVICE_UNAVAILABLE
    };
    (
        code,
        Json(Health {
            status: if database { "ok" } else { "degraded" },
            database,
        }),
    )
}
