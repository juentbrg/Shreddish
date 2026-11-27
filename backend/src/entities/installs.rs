//! Installation anonyme de l'app (spec 022 FR-2201, FR-2208).

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "installs")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub id: Uuid,
    /// SHA-256 du jeton ; jeton jamais stocké en clair.
    #[sea_orm(unique)]
    pub token_hash: Vec<u8>,
    /// `trial`, `trial_used` ou `subscribed`.
    pub entitlement: String,
    pub subscription_expires_at: Option<DateTimeUtc>,
    pub created_at: DateTimeUtc,
    pub revoked_at: Option<DateTimeUtc>,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
