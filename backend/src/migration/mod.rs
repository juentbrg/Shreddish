//! Schéma créé et mis à jour au démarrage (spec 022 FR-2214).

use sea_orm_migration::prelude::*;

mod m20261127_000001_init;
mod m20261127_000002_no_server_trial;
mod m20261127_000003_ai_tickets;

pub struct Migrator;

#[async_trait::async_trait]
impl MigratorTrait for Migrator {
    fn migrations() -> Vec<Box<dyn MigrationTrait>> {
        vec![
            Box::new(m20261127_000001_init::Migration),
            Box::new(m20261127_000002_no_server_trial::Migration),
            Box::new(m20261127_000003_ai_tickets::Migration),
        ]
    }
}
