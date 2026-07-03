defmodule Pass.Vault.Document do
  @moduledoc """
  A file (deed, title, statement, policy PDF, photo…) attached to an asset. The
  file contents are encrypted at rest; only the metadata is stored in the clear.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Pass.Encryption.EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Metadata fields loaded for listing (excludes the heavy, encrypted `data`).
  @meta_fields [:id, :asset_id, :filename, :content_type, :byte_size, :inserted_at, :updated_at]

  schema "documents" do
    field :filename, :string
    field :content_type, :string
    field :byte_size, :integer
    field :data, EncryptedBinary, redact: true

    belongs_to :asset, Pass.Vault.Asset

    timestamps(type: :utc_datetime)
  end

  @doc "Fields safe to select for listing (no decryption of file bytes)."
  def meta_fields, do: @meta_fields

  def changeset(document, attrs) do
    document
    |> cast(attrs, [:filename, :content_type, :byte_size, :data])
    |> validate_required([:filename, :byte_size, :data])
    |> validate_length(:filename, max: 255)
    |> validate_number(:byte_size, greater_than: 0)
  end
end
