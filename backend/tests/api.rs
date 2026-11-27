//! Tests d'intégration sur vrai Postgres (`TEST_DATABASE_URL`, base de `compose.yaml`). Spec 022.

use std::sync::{Arc, OnceLock};

use axum::Router;
use axum::body::Body;
use axum::http::{Method, Request, StatusCode};
use chrono::{Duration, Utc};
use futures::future::join_all;
use http_body_util::BodyExt;
use sea_orm::{ConnectionTrait, Database, DatabaseConnection, DbBackend, Statement};
use sea_orm_migration::MigratorTrait;
use serde_json::{Value, json};
use shreddish_api::config::Limits;
use shreddish_api::entitlement::DevVerifier;
use shreddish_api::error::AppError;
use shreddish_api::migration::Migrator;
use shreddish_api::quota::{self, Kind};
use shreddish_api::{AppState, router};
use tower::ServiceExt;
use uuid::Uuid;

const LIMITS: Limits = Limits {
    week: 3,
    meal: 30,
    day: 10,
    recipe: 50,
};

fn database_url() -> String {
    dotenvy::from_filename(concat!(env!("CARGO_MANIFEST_DIR"), "/.env.example")).ok();
    std::env::var("TEST_DATABASE_URL")
        .expect("TEST_DATABASE_URL manquant : docker compose -f backend/compose.yaml up -d")
}

/// Migrations une seule fois par binaire de test, dans leur propre runtime.
fn migrate_once() {
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

async fn setup() -> (Router, DatabaseConnection) {
    migrate_once();
    let db = Database::connect(database_url()).await.unwrap();
    let state = AppState {
        db: db.clone(),
        limits: LIMITS,
        verifier: Arc::new(DevVerifier),
    };
    (router(state), db)
}

async fn call(
    app: &Router,
    method: Method,
    path: &str,
    token: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let (status, body, _) = call_full(app, method, path, token, body).await;
    (status, body)
}

async fn call_full(
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

async fn register(app: &Router) -> (Uuid, String) {
    let (status, body) = call(app, Method::POST, "/v1/installs", None, None).await;
    assert_eq!(status, StatusCode::CREATED);
    (
        body["install_id"].as_str().unwrap().parse().unwrap(),
        body["token"].as_str().unwrap().to_string(),
    )
}

async fn subscribe(app: &Router, token: &str) {
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

async fn exec(db: &DatabaseConnection, sql: &str, id: Uuid) {
    db.execute(Statement::from_sql_and_values(
        DbBackend::Postgres,
        sql,
        [id.into()],
    ))
    .await
    .unwrap();
}

// US1 : identité anonyme

#[tokio::test]
async fn registered_install_authenticates_and_bad_tokens_are_refused() {
    let (app, db) = setup().await;
    let (id, token) = register(&app).await;
    assert!(token.len() >= 43, "jeton de 256 bits");
    assert_eq!(
        call(&app, Method::GET, "/v1/quota", Some(&token), None)
            .await
            .0,
        StatusCode::OK
    );

    for bad in [None, Some("faux"), Some("")] {
        let (status, body) = call(&app, Method::GET, "/v1/quota", bad, None).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED);
        assert_eq!(body["error"]["code"], "unauthenticated");
    }

    exec(
        &db,
        "UPDATE installs SET revoked_at = now() WHERE id = $1",
        id,
    )
    .await;
    assert_eq!(
        call(&app, Method::GET, "/v1/quota", Some(&token), None)
            .await
            .0,
        StatusCode::UNAUTHORIZED
    );
}

#[tokio::test]
async fn token_is_stored_hashed() {
    let (app, db) = setup().await;
    let (id, token) = register(&app).await;
    let row = db
        .query_one(Statement::from_sql_and_values(
            DbBackend::Postgres,
            "SELECT token_hash FROM installs WHERE id = $1",
            [id.into()],
        ))
        .await
        .unwrap()
        .unwrap();
    let stored: Vec<u8> = row.try_get("", "token_hash").unwrap();
    assert_ne!(stored, token.as_bytes());
    assert_eq!(stored, shreddish_api::auth::token_hash(&token));
}

// US2 : quota

#[tokio::test]
async fn consume_stops_at_daily_limit() {
    let (app, _) = setup().await;
    let (_, token) = register(&app).await;
    subscribe(&app, &token).await;
    let body = json!({ "kind": "week" });
    for remaining in [2, 1, 0] {
        let (status, usage) = call(
            &app,
            Method::POST,
            "/v1/quota/consume",
            Some(&token),
            Some(body.clone()),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(usage["remaining"], remaining);
    }
    let (status, refused) = call(
        &app,
        Method::POST,
        "/v1/quota/consume",
        Some(&token),
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::TOO_MANY_REQUESTS);
    assert_eq!(refused["error"]["code"], "quota_exceeded");
    assert_eq!(refused["error"]["details"]["limit"], 3);
    assert_eq!(refused["error"]["details"]["used"], 3);
    assert!(
        refused["error"]["details"]["resets_at"]
            .as_str()
            .unwrap()
            .contains("T00:00:00")
    );

    let (_, snapshot) = call(&app, Method::GET, "/v1/quota", Some(&token), None).await;
    assert_eq!(
        snapshot["kinds"]["week"],
        json!({ "limit": 3, "used": 3, "remaining": 0 })
    );
    assert_eq!(
        snapshot["kinds"]["meal"],
        json!({ "limit": 30, "used": 0, "remaining": 30 })
    );
    let (_, again) = call(&app, Method::GET, "/v1/quota", Some(&token), None).await;
    assert_eq!(
        again["kinds"], snapshot["kinds"],
        "lecture sans consommation"
    );
}

#[tokio::test]
async fn unknown_kind_is_invalid() {
    let (app, _) = setup().await;
    let (_, token) = register(&app).await;
    let (status, body) = call(
        &app,
        Method::POST,
        "/v1/quota/consume",
        Some(&token),
        Some(json!({ "kind": "dessert" })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["error"]["code"], "invalid_request");
}

#[tokio::test]
async fn quota_resets_next_utc_day() {
    let (app, db) = setup().await;
    let (id, token) = register(&app).await;
    subscribe(&app, &token).await;
    let today = Utc::now();
    for _ in 0..3 {
        quota::consume(&db, id, Kind::Week, &LIMITS, today)
            .await
            .unwrap();
    }
    assert!(matches!(
        quota::consume(&db, id, Kind::Week, &LIMITS, today).await,
        Err(AppError::QuotaExceeded { .. })
    ));
    let tomorrow = quota::quota_day(today).1;
    assert_eq!(
        quota::consume(&db, id, Kind::Week, &LIMITS, tomorrow)
            .await
            .unwrap()
            .used,
        1
    );
}

#[tokio::test]
async fn concurrent_consumes_never_exceed_limit() {
    // SC-2201 : 1 000 demandes simultanées, limite 50.
    let (app, db) = setup().await;
    let (id, token) = register(&app).await;
    subscribe(&app, &token).await;
    let now = Utc::now();
    let results = join_all((0..1000).map(|_| {
        let db = db.clone();
        tokio::spawn(async move { quota::consume(&db, id, Kind::Recipe, &LIMITS, now).await })
    }))
    .await;
    let accepted = results.iter().filter(|r| matches!(r, Ok(Ok(_)))).count();
    let refused = results
        .iter()
        .filter(|r| matches!(r, Ok(Err(AppError::QuotaExceeded { .. }))))
        .count();
    assert_eq!((accepted, refused), (50, 950));
    let snapshot = call(&app, Method::GET, "/v1/quota", Some(&token), None)
        .await
        .1;
    assert_eq!(snapshot["kinds"]["recipe"]["used"], 50);
}

// US3 : droits

#[tokio::test]
async fn trial_allows_exactly_one_action_even_concurrently() {
    // SC-2202.
    let (app, db) = setup().await;
    let (id, token) = register(&app).await;
    let now = Utc::now();
    let results = join_all((0..20).map(|_| {
        let db = db.clone();
        tokio::spawn(async move { quota::consume(&db, id, Kind::Meal, &LIMITS, now).await })
    }))
    .await;
    let accepted = results.iter().filter(|r| matches!(r, Ok(Ok(_)))).count();
    let refused = results
        .iter()
        .filter(|r| matches!(r, Ok(Err(AppError::SubscriptionRequired))))
        .count();
    assert_eq!((accepted, refused), (1, 19));

    let (status, body) = call(
        &app,
        Method::POST,
        "/v1/quota/consume",
        Some(&token),
        Some(json!({ "kind": "meal" })),
    )
    .await;
    assert_eq!(status, StatusCode::PAYMENT_REQUIRED);
    assert_eq!(body["error"]["code"], "subscription_required");
    assert_eq!(
        call(&app, Method::GET, "/v1/quota", Some(&token), None)
            .await
            .1["entitlement"],
        "trial_used"
    );
}

#[tokio::test]
async fn expired_subscription_is_refused() {
    let (app, db) = setup().await;
    let (id, token) = register(&app).await;
    subscribe(&app, &token).await;
    exec(
        &db,
        "UPDATE installs SET subscription_expires_at = now() - interval '1 day' WHERE id = $1",
        id,
    )
    .await;
    let (status, _) = call(
        &app,
        Method::POST,
        "/v1/quota/consume",
        Some(&token),
        Some(json!({ "kind": "day" })),
    )
    .await;
    assert_eq!(status, StatusCode::PAYMENT_REQUIRED);
    assert_eq!(
        call(&app, Method::GET, "/v1/quota", Some(&token), None)
            .await
            .1["entitlement"],
        "trial_used"
    );
}

#[tokio::test]
async fn dev_proof_subscribes_and_bad_proof_is_refused() {
    let (app, _) = setup().await;
    let (_, token) = register(&app).await;
    let (status, body) = call(
        &app,
        Method::POST,
        "/v1/entitlements/verify",
        Some(&token),
        Some(json!({ "proof": "dev-subscription:30" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["entitlement"], "subscribed");
    let expires: chrono::DateTime<Utc> = body["expires_at"].as_str().unwrap().parse().unwrap();
    assert!(
        (expires - Utc::now() - Duration::days(30))
            .num_seconds()
            .abs()
            < 60
    );

    for proof in ["dev-subscription:0", "dev-subscription:abc", "receipt"] {
        let (status, body) = call(
            &app,
            Method::POST,
            "/v1/entitlements/verify",
            Some(&token),
            Some(json!({ "proof": proof })),
        )
        .await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{proof}");
        assert_eq!(body["error"]["code"], "invalid_request");
    }
}

// US4 : exploitation

#[tokio::test]
async fn errors_share_one_shape_and_requests_carry_an_id() {
    let (app, _) = setup().await;
    let (status, body, headers) = call_full(&app, Method::GET, "/nulle-part", None, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body["error"]["code"], "not_found");
    assert!(body["error"]["message"].is_string());
    assert!(headers.contains_key("x-request-id"));

    let (status, body) = call(&app, Method::POST, "/v1/installs", None, None).await;
    assert_eq!(status, StatusCode::CREATED);
    let (_, token) = (
        body["install_id"].clone(),
        body["token"].as_str().unwrap().to_string(),
    );
    let request = Request::post("/v1/quota/consume")
        .header("authorization", format!("Bearer {token}"))
        .header("content-type", "application/json")
        .body(Body::from("{pas du json"))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn health_reports_database() {
    let (app, _) = setup().await;
    let (status, body) = call(&app, Method::GET, "/health", None, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body, json!({ "status": "ok", "database": true }));
}
