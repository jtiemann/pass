defmodule Pass.Vault.Credential do
  @moduledoc """
  A credential attached to an asset: a login, PIN, key, or similar. The `secret`
  and free-text `notes` are encrypted at rest; `label`, `username`, and `url` are
  stored in the clear for display and are safe to render.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Pass.Encryption.EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "credentials" do
    field :label, :string
    field :username, :string
    field :url, :string
    field :secret, EncryptedBinary, redact: true
    field :notes, EncryptedBinary, redact: true

    belongs_to :asset, Pass.Vault.Asset

    timestamps(type: :utc_datetime)
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:label, :username, :url, :secret, :notes])
    |> validate_required([:label])
    |> validate_length(:label, max: 200)
    |> nilify_blanks([:username, :url, :secret, :notes])
  end

  # Treat empty strings from form inputs as nil so we don't store blank ciphertext.
  defp nilify_blanks(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, cs ->
      case get_change(cs, field) do
        "" -> put_change(cs, field, nil)
        _ -> cs
      end
    end)
  end
end
