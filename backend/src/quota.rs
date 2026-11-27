//! Quota IA quotidien par installation et par type d'action (spec 022 FR-2203 à FR-2207, FR-2209).

use std::collections::BTreeMap;

use chrono::{DateTime, Days, NaiveDate, Utc};
use sea_orm::{
    ColumnTrait, ConnectionTrait, DatabaseBackend, DatabaseConnection, EntityTrait, QueryFilter,
    Statement, TransactionTrait,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::config::{Limits, TicketPolicy};
use crate::entities::{ai_usage, installs};
use crate::entitlement::Entitlement;
use crate::error::AppError;
use crate::ticket::{self, Ticket};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Week,
    Meal,
    Day,
    Recipe,
}

impl Kind {
    pub const ALL: [Self; 4] = [Self::Week, Self::Meal, Self::Day, Self::Recipe];

    pub fn parse(value: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|kind| kind.as_str() == value)
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Week => "week",
            Self::Meal => "meal",
            Self::Day => "day",
            Self::Recipe => "recipe",
        }
    }
}

#[derive(Debug, Serialize, PartialEq, Eq)]
pub struct Usage {
    pub limit: i32,
    pub used: i32,
    pub remaining: i32,
}

impl Usage {
    fn new(limit: i32, used: i32) -> Self {
        Self {
            limit,
            used,
            remaining: (limit - used).max(0),
        }
    }
}

#[derive(Debug, Serialize)]
pub struct Snapshot {
    pub day: NaiveDate,
    pub resets_at: DateTime<Utc>,
    pub entitlement: Entitlement,
    pub kinds: BTreeMap<Kind, Usage>,
}

/// Jour du quota : jour calendaire UTC ; remise à zéro au début du suivant (FR-2205).
pub fn quota_day(now: DateTime<Utc>) -> (NaiveDate, DateTime<Utc>) {
    let day = now.date_naive();
    let next = day.checked_add_days(Days::new(1)).unwrap_or(day);
    (day, next.and_hms_opt(0, 0, 0).unwrap_or_default().and_utc())
}

/// Quota restant, sans consommation (FR-2207).
pub async fn snapshot(
    db: &DatabaseConnection,
    install: &installs::Model,
    limits: &Limits,
    now: DateTime<Utc>,
) -> Result<Snapshot, AppError> {
    let (day, resets_at) = quota_day(now);
    let rows = ai_usage::Entity::find()
        .filter(ai_usage::Column::InstallId.eq(install.id))
        .filter(ai_usage::Column::Day.eq(day))
        .all(db)
        .await?;
    let kinds = Kind::ALL
        .into_iter()
        .map(|kind| {
            let used = rows
                .iter()
                .find(|row| row.kind == kind.as_str())
                .map_or(0, |row| row.count);
            (kind, Usage::new(limits.of(kind), used))
        })
        .collect();
    let entitlement =
        Entitlement::effective(&install.entitlement, install.subscription_expires_at, now);
    Ok(Snapshot {
        day,
        resets_at,
        entitlement,
        kinds,
    })
}

/// Consomme une action IA : droit puis quota, en une transaction ; l'installation est verrouillée pour
/// sérialiser ses demandes (FR-2206). Abonnement exigé (FR-2209). Ticket d'appels créé dans la même
/// transaction (spec 023 FR-2301).
pub async fn consume(
    db: &DatabaseConnection,
    install_id: Uuid,
    kind: Kind,
    limits: &Limits,
    tickets: &TicketPolicy,
    now: DateTime<Utc>,
) -> Result<(Usage, Ticket), AppError> {
    let (day, resets_at) = quota_day(now);
    let limit = limits.of(kind);
    let txn = db.begin().await?;
    let install = txn
        .query_one(Statement::from_sql_and_values(
            DatabaseBackend::Postgres,
            "SELECT entitlement, subscription_expires_at FROM installs
             WHERE id = $1 AND revoked_at IS NULL FOR UPDATE",
            [install_id.into()],
        ))
        .await?
        .ok_or(AppError::Unauthenticated)?;
    let entitlement = Entitlement::effective(
        &install.try_get::<String>("", "entitlement")?,
        install.try_get::<Option<DateTime<Utc>>>("", "subscription_expires_at")?,
        now,
    );
    if entitlement != Entitlement::Subscribed {
        return Err(AppError::SubscriptionRequired);
    }
    let incremented = if limit > 0 {
        txn.query_one(Statement::from_sql_and_values(
            DatabaseBackend::Postgres,
            "INSERT INTO ai_usage (install_id, day, kind, count) VALUES ($1, $2, $3, 1)
             ON CONFLICT (install_id, day, kind) DO UPDATE SET count = ai_usage.count + 1
             WHERE ai_usage.count < $4
             RETURNING count",
            [
                install_id.into(),
                day.into(),
                kind.as_str().into(),
                limit.into(),
            ],
        ))
        .await?
    } else {
        None
    };
    let Some(row) = incremented else {
        let used = txn
            .query_one(Statement::from_sql_and_values(
                DatabaseBackend::Postgres,
                "SELECT count FROM ai_usage WHERE install_id = $1 AND day = $2 AND kind = $3",
                [install_id.into(), day.into(), kind.as_str().into()],
            ))
            .await?
            .map(|row| row.try_get::<i32>("", "count"))
            .transpose()?
            .unwrap_or(0);
        return Err(AppError::QuotaExceeded {
            kind,
            limit,
            used,
            resets_at,
        });
    };
    let used = row.try_get::<i32>("", "count")?;
    let ticket = ticket::create(&txn, install_id, kind, tickets, now).await?;
    txn.commit().await?;
    Ok((Usage::new(limit, used), ticket))
}
