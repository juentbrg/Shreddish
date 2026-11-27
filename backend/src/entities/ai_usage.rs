//! Actions IA consommées par installation, jour UTC et type (spec 022 FR-2204).

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "ai_usage")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub install_id: Uuid,
    #[sea_orm(primary_key, auto_increment = false)]
    pub day: Date,
    #[sea_orm(primary_key, auto_increment = false)]
    pub kind: String,
    pub count: i32,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
