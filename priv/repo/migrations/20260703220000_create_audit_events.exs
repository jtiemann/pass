defmodule Pass.Repo.Migrations.CreateAuditEvents do
  use Ecto.Migration

  def change do
    create table(:audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Nullify (not delete) so the audit trail survives user removal; we also
      # snapshot the actor's email at the time of the event.
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :actor_email, :string

      add :action, :string, null: false
      add :entity_type, :string
      add :entity_id, :binary_id
      add :summary, :string

      # Audit events are immutable: inserted_at only.
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_events, [:inserted_at])
    create index(:audit_events, [:actor_id])
  end
end
