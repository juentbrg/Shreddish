//! Tickets d'appels IA (spec 023 FR-2301).

use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .get_connection()
            .execute_unprepared(
                "CREATE TABLE ai_tickets (
                    id uuid PRIMARY KEY,
                    install_id uuid NOT NULL REFERENCES installs (id) ON DELETE CASCADE,
                    kind text NOT NULL CHECK (kind IN ('week', 'meal', 'day', 'recipe')),
                    calls integer NOT NULL DEFAULT 0 CHECK (calls >= 0),
                    max_calls integer NOT NULL CHECK (max_calls >= 0),
                    expires_at timestamptz NOT NULL,
                    created_at timestamptz NOT NULL DEFAULT now()
                );
                CREATE INDEX ai_tickets_install ON ai_tickets (install_id);",
            )
            .await?;
        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .get_connection()
            .execute_unprepared("DROP TABLE ai_tickets;")
            .await?;
        Ok(())
    }
}
