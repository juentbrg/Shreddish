//! Tickets d'appels IA : une action consommée ouvre un nombre borné d'appels, pendant une durée courte
//! (spec 023 FR-2301 à FR-2304).

use chrono::{DateTime, Utc};
use sea_orm::{ConnectionTrait, DatabaseBackend, DatabaseConnection, Statement};
use serde::Serialize;
use uuid::Uuid;

use crate::config::TicketPolicy;
use crate::error::AppError;
use crate::quota::Kind;

#[derive(Clone, Debug, Serialize)]
pub struct Ticket {
    pub id: Uuid,
    pub kind: Kind,
    pub max_calls: i32,
    pub expires_at: DateTime<Utc>,
}

/// Schémas de réponse admis par type de ticket (FR-2303).
pub fn allows(kind: Kind, schema: &str) -> bool {
    let allowed: &[&str] = match kind {
        Kind::Week => &["WeekPlanResponse", "DayPlanResponse", "FoodMatchResponse"],
        Kind::Day => &["DayPlanResponse", "FoodMatchResponse"],
        Kind::Meal => &["MealReplacementResponse", "FoodMatchResponse"],
        Kind::Recipe => &["RecipeResponse"],
    };
    allowed.contains(&schema)
}

/// Création, dans la transaction de consommation du quota.
pub(crate) async fn create(
    txn: &impl ConnectionTrait,
    install_id: Uuid,
    kind: Kind,
    policy: &TicketPolicy,
    now: DateTime<Utc>,
) -> Result<Ticket, AppError> {
    let ttl =
        chrono::Duration::from_std(policy.ttl).map_err(|e| AppError::Internal(e.to_string()))?;
    let ticket = Ticket {
        id: Uuid::new_v4(),
        kind,
        max_calls: policy.calls.of(kind),
        expires_at: now + ttl,
    };
    txn.execute(Statement::from_sql_and_values(
        DatabaseBackend::Postgres,
        "INSERT INTO ai_tickets (id, install_id, kind, max_calls, expires_at) VALUES ($1, $2, $3, $4, $5)",
        [
            ticket.id.into(),
            install_id.into(),
            kind.as_str().into(),
            ticket.max_calls.into(),
            ticket.expires_at.into(),
        ],
    ))
    .await?;
    Ok(ticket)
}

/// Type d'un ticket de l'installation, sans rien consommer. Inconnu ou d'une autre installation : refus.
pub async fn kind_of(
    db: &DatabaseConnection,
    ticket_id: Uuid,
    install_id: Uuid,
) -> Result<Kind, AppError> {
    db.query_one(Statement::from_sql_and_values(
        DatabaseBackend::Postgres,
        "SELECT kind FROM ai_tickets WHERE id = $1 AND install_id = $2",
        [ticket_id.into(), install_id.into()],
    ))
    .await?
    .map(|row| row.try_get::<String>("", "kind"))
    .transpose()?
    .and_then(|kind| Kind::parse(&kind))
    .ok_or(AppError::TicketInvalid)
}

/// Prend un appel du ticket en une opération : ticket de l'installation, non expiré, non épuisé, abonnement
/// actif (FR-2304). Refus : motif précis.
pub async fn take_call(
    db: &DatabaseConnection,
    ticket_id: Uuid,
    install_id: Uuid,
    now: DateTime<Utc>,
) -> Result<(), AppError> {
    let taken = db
        .query_one(Statement::from_sql_and_values(
            DatabaseBackend::Postgres,
            "UPDATE ai_tickets t SET calls = t.calls + 1
             FROM installs i
             WHERE t.id = $1 AND t.install_id = $2 AND i.id = t.install_id AND i.revoked_at IS NULL
               AND i.entitlement = 'subscribed' AND i.subscription_expires_at > $3
               AND t.calls < t.max_calls AND t.expires_at > $3
             RETURNING t.calls",
            [ticket_id.into(), install_id.into(), now.into()],
        ))
        .await?;
    if taken.is_some() {
        return Ok(());
    }
    let row = db
        .query_one(Statement::from_sql_and_values(
            DatabaseBackend::Postgres,
            "SELECT t.calls, t.max_calls, t.expires_at, i.entitlement, i.subscription_expires_at
             FROM ai_tickets t JOIN installs i ON i.id = t.install_id
             WHERE t.id = $1 AND t.install_id = $2",
            [ticket_id.into(), install_id.into()],
        ))
        .await?
        .ok_or(AppError::TicketInvalid)?;
    let subscribed = row.try_get::<String>("", "entitlement")? == "subscribed"
        && row
            .try_get::<Option<DateTime<Utc>>>("", "subscription_expires_at")?
            .is_some_and(|expiry| expiry > now);
    Err(if !subscribed {
        AppError::SubscriptionRequired
    } else if row.try_get::<DateTime<Utc>>("", "expires_at")? <= now {
        AppError::TicketExpired
    } else {
        AppError::TicketExhausted
    })
}

/// Rend un appel au ticket : appel OpenAI en échec (spec 023 US3).
pub async fn give_back(db: &DatabaseConnection, ticket_id: Uuid) -> Result<(), AppError> {
    db.execute(Statement::from_sql_and_values(
        DatabaseBackend::Postgres,
        "UPDATE ai_tickets SET calls = calls - 1 WHERE id = $1 AND calls > 0",
        [ticket_id.into()],
    ))
    .await?;
    Ok(())
}
