defmodule Pass.Vault do
  @moduledoc """
  The Vault context: assets shared across the family instance.

  Assets are visible to every authenticated member (the whole point is that the
  family can find and access them). `created_by` is kept for provenance. Fine-
  grained roles arrive in a later phase.
  """
  import Ecto.Query, warn: false

  alias Pass.Repo
  alias Pass.Vault.{Asset, Credential, Document}
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

  ## Credentials

  @doc "Lists the credentials attached to an asset, oldest first."
  def list_credentials(%Asset{id: asset_id}) do
    Repo.all(from c in Credential, where: c.asset_id == ^asset_id, order_by: [asc: c.inserted_at])
  end

  @doc "Fetches a credential belonging to the given asset (raises if missing)."
  def get_credential!(%Asset{id: asset_id}, id) do
    Repo.get_by!(Credential, id: id, asset_id: asset_id)
  end

  @doc "Builds a changeset for form rendering."
  def change_credential(%Credential{} = credential, attrs \\ %{}) do
    Credential.changeset(credential, attrs)
  end

  @doc "Creates a credential on an asset."
  def create_credential(%Asset{id: asset_id}, attrs) do
    %Credential{asset_id: asset_id}
    |> Credential.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a credential."
  def update_credential(%Credential{} = credential, attrs) do
    credential
    |> Credential.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a credential."
  def delete_credential(%Credential{} = credential) do
    Repo.delete(credential)
  end

  ## Documents

  @doc """
  Lists an asset's documents as lightweight metadata structs. The encrypted
  `data` field is intentionally not selected, so no file bytes are decrypted
  just to render a list.
  """
  def list_documents(%Asset{id: asset_id}) do
    Repo.all(
      from d in Document,
        where: d.asset_id == ^asset_id,
        order_by: [asc: d.inserted_at],
        select: struct(d, ^Document.meta_fields())
    )
  end

  @doc "Fetches one document (including decrypted `data`), scoped to the asset."
  def get_document!(%Asset{id: asset_id}, id) do
    Repo.get_by!(Document, id: id, asset_id: asset_id)
  end

  @doc "Stores a new document (encrypting its contents at rest)."
  def create_document(%Asset{id: asset_id}, attrs) do
    %Document{asset_id: asset_id}
    |> Document.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Deletes a document."
  def delete_document(%Document{} = document) do
    Repo.delete(document)
  end

  @doc "Metadata-only projection of a document, matching `list_documents/1` shape."
  def document_meta(%Document{} = document), do: %{document | data: nil}
end
