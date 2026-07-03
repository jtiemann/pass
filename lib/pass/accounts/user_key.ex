defmodule Pass.Accounts.UserKey do
  @moduledoc """
  A registered WebAuthn credential (passkey / security key) belonging to a user.

  Used as the second authentication factor. The COSE public key is stored as an
  opaque binary (`:erlang.term_to_binary/1`); use `cose_key/1` to decode it back
  into the map shape that `Wax` expects.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "user_keys" do
    field :label, :string
    field :credential_id, :binary
    field :public_key, :binary
    field :aaguid, :binary
    field :sign_count, :integer, default: 0
    field :last_used_at, :utc_datetime

    belongs_to :user, Pass.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for registering a brand new credential."
  def registration_changeset(user_key, attrs) do
    user_key
    |> cast(attrs, [:label, :credential_id, :public_key, :aaguid, :sign_count])
    |> validate_required([:label, :credential_id, :public_key, :sign_count])
    |> validate_length(:label, min: 1, max: 100)
    |> unique_constraint(:credential_id)
  end

  @doc "Changeset for recording usage after a successful assertion."
  def usage_changeset(user_key, attrs) do
    cast(user_key, attrs, [:sign_count, :last_used_at])
  end

  @doc "Decodes the stored COSE public key into the map shape Wax expects."
  def cose_key(%__MODULE__{public_key: bin}) when is_binary(bin) do
    :erlang.binary_to_term(bin, [:safe])
  end
end
