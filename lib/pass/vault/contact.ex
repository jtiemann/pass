defmodule Pass.Vault.Contact do
  @moduledoc """
  A person associated with an asset — advisor, attorney, agent, banker — and how
  to reach them. Contact details are not secret and are stored in the clear.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "contacts" do
    field :name, :string
    field :relationship, :string
    field :organization, :string
    field :email, :string
    field :phone, :string
    field :notes, :string

    belongs_to :asset, Pass.Vault.Asset

    timestamps(type: :utc_datetime)
  end

  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [:name, :relationship, :organization, :email, :phone, :notes])
    |> validate_required([:name])
    |> validate_length(:name, max: 200)
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must be a valid email",
      allow_blank: true
    )
  end
end
