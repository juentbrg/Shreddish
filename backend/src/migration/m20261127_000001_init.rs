use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .get_connection()
            .execute_unprepared(
                "CREATE TABLE installs (
                    id uuid PRIMARY KEY,
                    token_hash bytea NOT NULL UNIQUE,
                    entitlement text NOT NULL DEFAULT 'trial'
                        CHECK (entitlement IN ('trial', 'trial_used', 'subscribed')),
                    subscription_expires_at timestamptz,
                    created_at timestamptz NOT NULL DEFAULT now(),
                    revoked_at timestamptz
                );
                CREATE TABLE ai_usage (
                    install_id uuid NOT NULL REFERENCES installs (id) ON DELETE CASCADE,
                    day date NOT NULL,
                    kind text NOT NULL CHECK (kind IN ('week', 'meal', 'day', 'recipe')),
                    count integer NOT NULL CHECK (count >= 0),
                    PRIMARY KEY (install_id, day, kind)
                );",
            )
            .await?;
        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .get_connection()
            .execute_unprepared("DROP TABLE ai_usage; DROP TABLE installs;")
            .await?;
        Ok(())
    }
}
