defmodule Pass.Audit.Event do
  @moduledoc "An immutable audit-trail entry."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "audit_events" do
    field :actor_email, :string
    field :action, :string
    field :entity_type, :string
    field :entity_id, Ecto.UUID
    field :summary, :string

    belongs_to :actor, Pass.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:actor_id, :actor_email, :action, :entity_type, :entity_id, :summary])
    |> validate_required([:action])
  end
end
