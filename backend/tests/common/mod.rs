//! Outils communs des tests d'intégration : vrai Postgres (`TEST_DATABASE_URL`, base de `compose.yaml`).
#![allow(dead_code)]

use std::sync::{Arc, OnceLock};

use axum::Router;
use axum::body::Body;
use axum::http::{Method, Request, StatusCode};
use http_body_util::BodyExt;
use sea_orm::{ConnectionTrait, Database, DatabaseConnection, DbBackend, Statement};
use sea_orm_migration::MigratorTrait;
use serde_json::{Value, json};
use shreddish_api::config::{Limits, TicketPolicy};
use shreddish_api::entitlement::DevVerifier;
use shreddish_api::migration::Migrator;
use shreddish_api::{AiClient, AppState, router};
use tower::ServiceExt;
use uuid::Uuid;

pub const LIMITS: Limits = Limits {
    week: 3,
    meal: 30,
    day: 10,
    recipe: 50,
};

pub fn database_url() -> String {
    dotenvy::from_filename(concat!(env!("CARGO_MANIFEST_DIR"), "/.env.example")).ok();
    std::env::var("TEST_DATABASE_URL")
        .expect("TEST_DATABASE_URL manquant : docker compose -f backend/compose.yaml up -d")
}

/// Migrations une seule fois par binaire de test, dans leur propre runtime.
pub fn migrate_once() {
    static DONE: OnceLock<()> = OnceLock::new();
    DONE.get_or_init(|| {
        std::thread::spawn(|| {
            tokio::runtime::Runtime::new().unwrap().block_on(async {
                let db = Database::connect(database_url()).await.unwrap();
                Migrator::up(&db, None).await.unwrap();
            });
        })
        .join()
        .unwrap();
    });
}

pub async fn setup() -> (Router, DatabaseConnection) {
    setup_with(None).await
}

/// `ai` : client OpenAI (simulé), absent = service IA coupé.
pub async fn setup_with(ai: Option<AiClient>) -> (Router, DatabaseConnection) {
    migrate_once();
    let db = Database::connect(database_url()).await.unwrap();
    let state = AppState {
        db: db.clone(),
        limits: LIMITS,
        tickets: TicketPolicy::default(),
        ai,
        verifier: Arc::new(DevVerifier),
    };
    (router(state), db)
}

pub async fn call(
    app: &Router,
    method: Method,
    path: &str,
    token: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let (status, body, _) = call_full(app, method, path, token, body).await;
    (status, body)
}

pub async fn call_full(
    app: &Router,
    method: Method,
    path: &str,
    token: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, Value, axum::http::HeaderMap) {
    let mut request = Request::builder().method(method).uri(path);
    if let Some(token) = token {
        request = request.header("authorization", format!("Bearer {token}"));
    }
    let request = match body {
        Some(body) => request
            .header("content-type", "application/json")
            .body(Body::from(body.to_string())),
        None => request.body(Body::empty()),
    }
    .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    let (status, headers) = (response.status(), response.headers().clone());
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
        headers,
    )
}

pub async fn register(app: &Router) -> (Uuid, String) {
    let (status, body) = call(app, Method::POST, "/v1/installs", None, None).await;
    assert_eq!(status, StatusCode::CREATED);
    (
        body["install_id"].as_str().unwrap().parse().unwrap(),
        body["token"].as_str().unwrap().to_string(),
    )
}

pub async fn subscribe(app: &Router, token: &str) {
    let proof = json!({ "proof": "dev-subscription:30" });
    let (status, _) = call(
        app,
        Method::POST,
        "/v1/entitlements/verify",
        Some(token),
        Some(proof),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
}

pub async fn exec(db: &DatabaseConnection, sql: &str, id: Uuid) {
    db.execute(Statement::from_sql_and_values(
        DbBackend::Postgres,
        sql,
        [id.into()],
    ))
    .await
    .unwrap();
}
