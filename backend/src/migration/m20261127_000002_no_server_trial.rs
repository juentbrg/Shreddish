//! Essai = offre d'introduction Apple, plus d'essai côté serveur (spec 022 FR-2208, révision du 2026-11-27).

use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .get_connection()
            .execute_unprepared(
                "ALTER TABLE installs DROP CONSTRAINT installs_entitlement_check;
                UPDATE installs SET entitlement = 'none' WHERE entitlement IN ('trial', 'trial_used');
                ALTER TABLE installs ALTER COLUMN entitlement SET DEFAULT 'none';
                ALTER TABLE installs ADD CONSTRAINT installs_entitlement_check
                    CHECK (entitlement IN ('none', 'subscribed'));",
            )
            .await?;
        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .get_connection()
            .execute_unprepared(
                "ALTER TABLE installs DROP CONSTRAINT installs_entitlement_check;
                UPDATE installs SET entitlement = 'trial_used' WHERE entitlement = 'none';
                ALTER TABLE installs ALTER COLUMN entitlement SET DEFAULT 'trial';
                ALTER TABLE installs ADD CONSTRAINT installs_entitlement_check
                    CHECK (entitlement IN ('trial', 'trial_used', 'subscribed'));",
            )
            .await?;
        Ok(())
    }
}
