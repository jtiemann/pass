defmodule Pass.Vault do
  @moduledoc """
  The Vault context: assets shared across the family instance.

  Assets are visible to every authenticated member (the whole point is that the
  family can find and access them). `created_by` is kept for provenance. Fine-
  grained roles arrive in a later phase.
  """
  import Ecto.Query, warn: false

  alias Pass.Repo
  alias Pass.Vault.{Asset, Contact, Credential, Document}
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

  @doc """
  A summary of the whole vault for the dashboard: per-currency totals, a
  per-category breakdown, and the most recently added assets. Values are never
  summed across currencies — each currency gets its own total.
  """
  def dashboard_summary do
    assets = list_assets()

    by_category =
      assets
      |> Enum.group_by(& &1.category)
      |> Enum.map(fn {category, list} ->
        %{category: category, count: length(list), totals: totals_by_currency(list)}
      end)
      |> Enum.sort_by(& &1.count, :desc)

    %{
      total_assets: length(assets),
      totals: totals_by_currency(assets),
      by_category: by_category,
      recent: assets |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime}) |> Enum.take(5)
    }
  end

  # [{currency, Decimal sum}] for assets that carry a value, largest first.
  defp totals_by_currency(assets) do
    assets
    |> Enum.filter(&match?(%Decimal{}, &1.estimated_value))
    |> Enum.group_by(& &1.currency)
    |> Enum.map(fn {currency, list} ->
      {currency, Enum.reduce(list, Decimal.new(0), &Decimal.add(&2, &1.estimated_value))}
    end)
    |> Enum.sort_by(fn {_currency, sum} -> Decimal.to_float(sum) end, :desc)
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

  ## Contacts

  @doc "Lists an asset's contacts, alphabetically by name."
  def list_contacts(%Asset{id: asset_id}) do
    Repo.all(from c in Contact, where: c.asset_id == ^asset_id, order_by: [asc: c.name])
  end

  @doc "Fetches one contact scoped to the asset."
  def get_contact!(%Asset{id: asset_id}, id) do
    Repo.get_by!(Contact, id: id, asset_id: asset_id)
  end

  @doc "Builds a changeset for form rendering."
  def change_contact(%Contact{} = contact, attrs \\ %{}) do
    Contact.changeset(contact, attrs)
  end

  @doc "Creates a contact on an asset."
  def create_contact(%Asset{id: asset_id}, attrs) do
    %Contact{asset_id: asset_id}
    |> Contact.changeset(attrs)
    |> Repo.insert()
  end

  ## Export

  @doc """
  Builds a full, DECRYPTED export of the vault as plain maps — used by
  `mix pass.export` to produce the offline "emergency kit". Document contents
  are omitted (only metadata); a database backup covers the encrypted blobs.

  Handle the output with care: it contains every secret in the vault.
  """
  def export do
    %{
      exported_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      assets:
        Enum.map(list_assets(), fn asset ->
          %{
            name: asset.name,
            category: asset.category,
            status: asset.status,
            institution: asset.institution,
            location: asset.location,
            description: asset.description,
            estimated_value: asset.estimated_value && Decimal.to_string(asset.estimated_value),
            currency: asset.currency,
            annual_return_pct:
              asset.annual_return_pct && Decimal.to_string(asset.annual_return_pct),
            dividend_yield_pct:
              asset.dividend_yield_pct && Decimal.to_string(asset.dividend_yield_pct),
            dividends_reinvested: asset.dividends_reinvested,
            annual_draw: asset.annual_draw && Decimal.to_string(asset.annual_draw),
            access_instructions: asset.access_instructions,
            ownership_proof: asset.ownership_proof,
            sale_instructions: asset.sale_instructions,
            credentials:
              Enum.map(list_credentials(asset), fn credential ->
                %{
                  label: credential.label,
                  username: credential.username,
                  url: credential.url,
                  secret: credential.secret,
                  notes: credential.notes
                }
              end),
            contacts:
              Enum.map(list_contacts(asset), fn contact ->
                %{
                  name: contact.name,
                  relationship: contact.relationship,
                  organization: contact.organization,
                  email: contact.email,
                  phone: contact.phone,
                  notes: contact.notes
                }
              end),
            documents:
              Enum.map(list_documents(asset), fn document ->
                %{
                  filename: document.filename,
                  content_type: document.content_type,
                  byte_size: document.byte_size
                }
              end)
          }
        end)
    }
  end

  @doc """
  Imports a vault export (the decoded JSON produced by `mix pass.export`).

  Runs in a single transaction: any invalid record rolls the whole import back.
  Assets whose name already exists in the vault are skipped, so re-running an
  import is safe. Secrets are (re-)encrypted on insert like any other write.
  Documents appear in exports as metadata only, so they are counted as skipped —
  restore file contents from a database backup.

  Returns `{:ok, summary}` or `{:error, reason}`.
  """
  def import_data(%{"assets" => assets}) when is_list(assets) do
    Repo.transaction(fn ->
      existing = MapSet.new(list_assets(), & &1.name)

      initial = %{
        imported: 0,
        skipped: [],
        credentials: 0,
        contacts: 0,
        documents_skipped: 0
      }

      {_names, summary} =
        Enum.reduce(assets, {existing, initial}, fn entry, {names, acc} ->
          name = entry["name"]

          if MapSet.member?(names, name) do
            {names, %{acc | skipped: [name | acc.skipped]}}
          else
            asset = insert_imported!(%Asset{}, Asset.changeset(%Asset{}, entry), name)

            credentials =
              for cred <- entry["credentials"] || [] do
                insert_imported!(
                  asset,
                  Credential.changeset(%Credential{asset_id: asset.id}, cred),
                  name
                )
              end

            contacts =
              for contact <- entry["contacts"] || [] do
                insert_imported!(
                  asset,
                  Contact.changeset(%Contact{asset_id: asset.id}, contact),
                  name
                )
              end

            acc = %{
              acc
              | imported: acc.imported + 1,
                credentials: acc.credentials + length(credentials),
                contacts: acc.contacts + length(contacts),
                documents_skipped: acc.documents_skipped + length(entry["documents"] || [])
            }

            {MapSet.put(names, name), acc}
          end
        end)

      %{summary | skipped: Enum.reverse(summary.skipped)}
    end)
  end

  def import_data(_other), do: {:error, :invalid_format}

  defp insert_imported!(_parent, changeset, asset_name) do
    case Repo.insert(changeset) do
      {:ok, record} -> record
      {:error, failed} -> Repo.rollback({:invalid_record, asset_name, failed})
    end
  end

  @doc "Updates a contact."
  def update_contact(%Contact{} = contact, attrs) do
    contact
    |> Contact.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a contact."
  def delete_contact(%Contact{} = contact) do
    Repo.delete(contact)
  end
end
