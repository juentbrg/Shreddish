//! API Shreddish, lot 1 (spec 022) : installations anonymes, quota IA, droits d'accès.

pub mod auth;
pub mod config;
pub mod entities;
pub mod entitlement;
pub mod error;
pub mod migration;
pub mod quota;
mod routes;

use std::sync::Arc;

use axum::Router;
use axum::extract::Request;
use axum::http::HeaderName;
use sea_orm::DatabaseConnection;
use tower_http::request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer};
use tower_http::trace::{DefaultOnResponse, TraceLayer};
use tracing::Level;

use crate::config::Limits;
use crate::entitlement::Verifier;
use crate::error::AppError;

#[derive(Clone)]
pub struct AppState {
    pub db: DatabaseConnection,
    pub limits: Limits,
    pub verifier: Arc<dyn Verifier>,
}

const REQUEST_ID: HeaderName = HeaderName::from_static("x-request-id");

/// Routes et couches. Traces : méthode, chemin sans requête, statut, durée, identifiant ; jamais les en-têtes
/// (jeton) ni les corps (FR-2213).
pub fn router(state: AppState) -> Router {
    Router::new()
        .merge(routes::health::router())
        .merge(routes::installs::router())
        .merge(routes::quota::router())
        .merge(routes::entitlements::router())
        .fallback(|| async { AppError::NotFound })
        .with_state(state)
        .layer(PropagateRequestIdLayer::new(REQUEST_ID))
        .layer(
            TraceLayer::new_for_http()
                .make_span_with(|request: &Request| {
                    let id = request.headers().get(REQUEST_ID).and_then(|v| v.to_str().ok()).unwrap_or("-");
                    tracing::info_span!("request", method = %request.method(), path = %request.uri().path(), id)
                })
                .on_response(DefaultOnResponse::new().level(Level::INFO)),
        )
        .layer(SetRequestIdLayer::new(REQUEST_ID, MakeRequestUuid))
}
