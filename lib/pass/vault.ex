defmodule Pass.Vault do
  @moduledoc """
  The Vault context: assets shared across the family instance.

  Assets are visible to every authenticated member (the whole point is that the
  family can find and access them). `created_by` is kept for provenance. Fine-
  grained roles arrive in a later phase.
  """
  import Ecto.Query, warn: false

  alias Pass.Repo
  alias Pass.Vault.Asset
  alias Pass.Accounts.Scope

  @topic "assets"

  @doc "Subscribes the caller to asset changes (for live updates)."
  def subscribe_assets do
    Phoenix.PubSub.subscribe(Pass.PubSub, @topic)
  end

  @doc "Lists all assets, alphabetically."
  def list_assets do
    Repo.all(from a in Asset, order_by: [asc: a.name])
  end

  @doc "Fetches an asset by id, raising if missing."
  def get_asset!(id), do: Repo.get!(Asset, id)

  @doc "Builds a changeset for form rendering."
  def change_asset(%Asset{} = asset, attrs \\ %{}) do
    Asset.changeset(asset, attrs)
  end

  @doc "Creates an asset, recording who created it."
  def create_asset(%Scope{user: user}, attrs) do
    %Asset{created_by_id: user.id}
    |> Asset.changeset(attrs)
    |> Repo.insert()
    |> broadcast(:created)
  end

  @doc "Updates an asset."
  def update_asset(%Asset{} = asset, attrs) do
    asset
    |> Asset.changeset(attrs)
    |> Repo.update()
    |> broadcast(:updated)
  end

  @doc "Deletes an asset."
  def delete_asset(%Asset{} = asset) do
    asset
    |> Repo.delete()
    |> broadcast(:deleted)
  end

  defp broadcast({:ok, %Asset{} = asset} = result, event) do
    Phoenix.PubSub.broadcast(Pass.PubSub, @topic, {event, asset})
    result
  end

  defp broadcast(other, _event), do: other
end
