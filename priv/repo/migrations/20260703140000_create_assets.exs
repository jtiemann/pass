defmodule Pass.Repo.Migrations.CreateAssets do
  use Ecto.Migration

  def change do
    create table(:assets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :name, :string, null: false
      add :category, :string, null: false, default: "other"
      add :status, :string, null: false, default: "active"

      add :institution, :string
      add :location, :string
      add :description, :text
      add :estimated_value, :decimal
      add :currency, :string, null: false, default: "USD"

      # Free-text guidance. NOTE: these can hold sensitive detail; Phase 4 will
      # move sensitive columns behind Cloak encryption at rest.
      add :access_instructions, :text
      add :ownership_proof, :text
      add :sale_instructions, :text

      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:assets, [:category])
    create index(:assets, [:created_by_id])
  end
end
