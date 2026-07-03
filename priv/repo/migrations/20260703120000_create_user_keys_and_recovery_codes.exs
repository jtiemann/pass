defmodule Pass.Repo.Migrations.CreateUserKeysAndRecoveryCodes do
  use Ecto.Migration

  def change do
    # Registered WebAuthn/passkey credentials (2nd factor).
    create table(:user_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :label, :string, null: false
      # Raw binary credential id returned by the authenticator.
      add :credential_id, :binary, null: false
      # COSE public key, stored via :erlang.term_to_binary/1.
      add :public_key, :binary, null: false
      # Authenticator AAGUID (16 bytes), useful for later metadata checks.
      add :aaguid, :binary
      # Signature counter for clone detection.
      add :sign_count, :integer, null: false, default: 0
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_keys, [:credential_id])
    create index(:user_keys, [:user_id])

    # Single-use recovery codes, used to log in when no passkey is available.
    create table(:user_recovery_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :hashed_code, :string, null: false
      add :used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:user_recovery_codes, [:user_id])
  end
end
