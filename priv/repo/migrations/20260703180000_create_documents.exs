defmodule Pass.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :asset_id,
          references(:assets, type: :binary_id, on_delete: :delete_all),
          null: false

      add :filename, :string, null: false
      add :content_type, :string
      add :byte_size, :integer, null: false

      # Encrypted file contents at rest (Cloak). Kept out of list queries.
      add :data, :binary, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:documents, [:asset_id])
  end
end
