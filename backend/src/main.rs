use std::sync::Arc;

use sea_orm::Database;
use sea_orm_migration::MigratorTrait;
use shreddish_api::config::{Config, VerifierKind};
use shreddish_api::entitlement::{DevVerifier, NoVerifier, Verifier};
use shreddish_api::migration::Migrator;
use shreddish_api::{AiClient, AppState, router};
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();
    let config = Config::from_env()?;
    let db = Database::connect(&config.database_url).await?;
    Migrator::up(&db, None).await?;
    let verifier: Arc<dyn Verifier> = match config.verifier {
        VerifierKind::Dev => Arc::new(DevVerifier),
        VerifierKind::None => Arc::new(NoVerifier),
    };
    let listener = tokio::net::TcpListener::bind(config.bind_addr).await?;
    tracing::info!("écoute sur {}", config.bind_addr);
    let ai = config.openai.clone().map(AiClient::new).transpose()?;
    if ai.is_none() {
        tracing::warn!("OPENAI_API_KEY absent : service IA coupé");
    }
    let state = AppState {
        db,
        limits: config.limits,
        tickets: config.tickets,
        ai,
        verifier,
    };
    axum::serve(listener, router(state))
        .with_graceful_shutdown(async {
            tokio::signal::ctrl_c().await.ok();
        })
        .await?;
    Ok(())
}
