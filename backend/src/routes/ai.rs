//! Proxy OpenAI : appel de génération avec la clé du serveur, dans un ticket d'appels (spec 023).

use axum::Router;
use axum::body::{Body, Bytes};
use axum::extract::{DefaultBodyLimit, State};
use axum::http::HeaderMap;
use axum::http::header::{CACHE_CONTROL, CONTENT_TYPE};
use axum::response::{IntoResponse, Response};
use axum::routing::post;
use chrono::Utc;
use serde::Deserialize;
use serde_json::{Value, json};
use uuid::Uuid;

use crate::auth::AuthInstall;
use crate::config::OpenAiConfig;
use crate::error::{ApiJson, AppError};
use crate::{AppState, prompts, ticket};

/// Corps admis (FR-2305) : tout autre champ (modèle, conservation, consignes de l'app…) est ignoré.
#[derive(Deserialize)]
struct ProxyRequest {
    input: String,
    text: TextFormat,
    #[serde(default)]
    stream: bool,
}

#[derive(Deserialize)]
struct TextFormat {
    format: Format,
}

#[derive(Deserialize)]
struct Format {
    #[serde(rename = "type")]
    kind: String,
    name: String,
    schema: Value,
}

const TICKET_HEADER: &str = "x-shreddish-ticket";

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/v1/ai/responses", post(responses))
        .layer(DefaultBodyLimit::max(256 * 1024))
}

async fn responses(
    State(state): State<AppState>,
    AuthInstall(install): AuthInstall,
    headers: HeaderMap,
    ApiJson(request): ApiJson<ProxyRequest>,
) -> Result<Response, AppError> {
    let ai = state.ai.as_ref().ok_or(AppError::AiUnavailable)?;
    let ticket_id = headers
        .get(TICKET_HEADER)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.parse::<Uuid>().ok())
        .ok_or_else(|| {
            AppError::InvalidRequest("En-tête X-Shreddish-Ticket absent ou invalide.".into())
        })?;
    if request.text.format.kind != "json_schema" {
        return Err(AppError::InvalidRequest(
            "Format de sortie json_schema exigé.".into(),
        ));
    }
    let schema = request.text.format.name.as_str();
    let kind = ticket::kind_of(&state.db, ticket_id, install.id).await?;
    let instructions = prompts::instructions(schema)
        .filter(|_| ticket::allows(kind, schema))
        .ok_or_else(|| AppError::InvalidRequest("Schéma non admis pour ce ticket.".into()))?;
    prompts::check_input(schema, &request.input)?;
    ticket::take_call(&state.db, ticket_id, install.id, Utc::now()).await?;

    let mut upstream = ai
        .http
        .post(format!(
            "{}/responses",
            ai.config.base_url.trim_end_matches('/')
        ))
        .bearer_auth(&ai.config.api_key)
        .json(&upstream_body(&ai.config, instructions, &request));
    if !request.stream {
        upstream = upstream.timeout(ai.config.timeout);
    }
    let failed = |error: AppError| async {
        // Appel en échec : rendu au ticket (US3). Échec de la restitution : journalisé seulement.
        if let Err(give_back) = ticket::give_back(&state.db, ticket_id).await {
            tracing::error!(?give_back, "restitution d'appel impossible");
        }
        Err(error)
    };
    let response = match upstream.send().await {
        Ok(response) => response,
        Err(error) => return failed(upstream_error(&error)).await,
    };
    if !response.status().is_success() {
        // Jamais l'erreur OpenAI brute : l'app lirait 401 comme « clé invalide » (FR-2308).
        tracing::warn!(status = %response.status(), "OpenAI en erreur");
        return failed(AppError::UpstreamError).await;
    }
    if request.stream {
        // Flux transmis au fil de l'eau ; client parti : flux abandonné, connexion OpenAI fermée (FR-2307).
        let body = Body::from_stream(response.bytes_stream());
        return Ok((
            [
                (CONTENT_TYPE, "text/event-stream"),
                (CACHE_CONTROL, "no-cache"),
            ],
            body,
        )
            .into_response());
    }
    let bytes: Bytes = match response.bytes().await {
        Ok(bytes) => bytes,
        Err(error) => return failed(upstream_error(&error)).await,
    };
    Ok(([(CONTENT_TYPE, "application/json")], bytes).into_response())
}

/// Requête OpenAI construite par le serveur (FR-2305, FR-2306), consignes du serveur (FR-2311).
fn upstream_body(config: &OpenAiConfig, instructions: &str, request: &ProxyRequest) -> Value {
    let mut body = json!({
        "model": config.model,
        "instructions": instructions,
        "input": request.input,
        "store": false,
        "max_output_tokens": config.max_output_tokens,
        "text": { "format": {
            "type": "json_schema",
            "name": request.text.format.name,
            "strict": true,
            "schema": request.text.format.schema,
        } },
    });
    if config.model.starts_with("gpt-5") || config.model.starts_with("gpt-6") {
        body["reasoning"] = json!({ "effort": "low" });
    }
    if request.stream {
        body["stream"] = json!(true);
    }
    body
}

fn upstream_error(error: &reqwest::Error) -> AppError {
    tracing::warn!(timeout = error.is_timeout(), "OpenAI injoignable");
    if error.is_timeout() {
        AppError::UpstreamTimeout
    } else {
        AppError::UpstreamError
    }
}
