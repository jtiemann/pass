defmodule Pass.Accounts.RecoveryCode do
  @moduledoc """
  A single-use recovery code, hashed at rest. Used to log in (as the second
  factor) when the user cannot use a passkey.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "user_recovery_codes" do
    field :hashed_code, :string
    field :used_at, :utc_datetime

    belongs_to :user, Pass.Accounts.User

    timestamps(type: :utc_datetime)
  end
end
