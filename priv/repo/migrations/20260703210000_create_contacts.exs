defmodule Pass.Repo.Migrations.CreateContacts do
  use Ecto.Migration

  def change do
    create table(:contacts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :asset_id,
          references(:assets, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :relationship, :string
      add :organization, :string
      add :email, :string
      add :phone, :string
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:contacts, [:asset_id])
  end
end
