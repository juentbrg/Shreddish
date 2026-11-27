//! Erreurs de l'API : corps JSON uniforme `{"error": {"code", "message"}}` (spec 022 FR-2211).

use axum::Json;
use axum::extract::rejection::JsonRejection;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use chrono::{DateTime, Utc};
use sea_orm::DbErr;
use serde_json::{Value, json};

use crate::quota::Kind;

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("Jeton absent ou invalide.")]
    Unauthenticated,
    #[error("{0}")]
    InvalidRequest(String),
    #[error("Abonnement requis.")]
    SubscriptionRequired,
    #[error("Quota du jour atteint.")]
    QuotaExceeded {
        kind: Kind,
        limit: i32,
        used: i32,
        resets_at: DateTime<Utc>,
    },
    #[error("Ressource introuvable.")]
    NotFound,
    /// Détail journalisé, jamais renvoyé au client.
    #[error("Erreur interne.")]
    Internal(String),
}

impl AppError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::Unauthenticated => "unauthenticated",
            Self::InvalidRequest(_) => "invalid_request",
            Self::SubscriptionRequired => "subscription_required",
            Self::QuotaExceeded { .. } => "quota_exceeded",
            Self::NotFound => "not_found",
            Self::Internal(_) => "internal",
        }
    }

    fn status(&self) -> StatusCode {
        match self {
            Self::Unauthenticated => StatusCode::UNAUTHORIZED,
            Self::InvalidRequest(_) => StatusCode::BAD_REQUEST,
            Self::SubscriptionRequired => StatusCode::PAYMENT_REQUIRED,
            Self::QuotaExceeded { .. } => StatusCode::TOO_MANY_REQUESTS,
            Self::NotFound => StatusCode::NOT_FOUND,
            Self::Internal(_) => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        if let Self::Internal(detail) = &self {
            tracing::error!(%detail, "erreur interne");
        }
        let mut error = json!({ "code": self.code(), "message": self.to_string() });
        if let Self::QuotaExceeded {
            kind,
            limit,
            used,
            resets_at,
        } = &self
        {
            error["details"] =
                json!({ "kind": kind, "limit": limit, "used": used, "resets_at": resets_at });
        }
        (self.status(), Json(json!({ "error": error }))).into_response()
    }
}

impl From<DbErr> for AppError {
    fn from(error: DbErr) -> Self {
        Self::Internal(error.to_string())
    }
}

impl From<JsonRejection> for AppError {
    fn from(rejection: JsonRejection) -> Self {
        Self::InvalidRequest(rejection.body_text())
    }
}

/// Corps JSON dont le rejet passe par [`AppError`].
#[derive(axum::extract::FromRequest)]
#[from_request(via(axum::Json), rejection(AppError))]
pub struct ApiJson<T>(pub T);

pub type ApiResult<T = Value> = Result<T, AppError>;
