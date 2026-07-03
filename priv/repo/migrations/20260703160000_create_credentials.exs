defmodule Pass.Repo.Migrations.CreateCredentials do
  use Ecto.Migration

  def change do
    create table(:credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :asset_id,
          references(:assets, type: :binary_id, on_delete: :delete_all),
          null: false

      # Displayable, non-secret fields.
      add :label, :string, null: false
      add :username, :string
      add :url, :string

      # Encrypted at rest via Cloak (stored as ciphertext binary).
      add :secret, :binary
      add :notes, :binary

      timestamps(type: :utc_datetime)
    end

    create index(:credentials, [:asset_id])
  end
end
