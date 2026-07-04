defmodule PassWeb.AssetLive.Grid do
  @moduledoc """
  Spreadsheet-style editing for assets: one row per asset, one input per cell,
  saved as soon as a cell changes (text/number cells save on blur).

  The whole table lives in a single form; LiveView's `_target` tells us exactly
  which asset+field changed, so each edit is a minimal single-column update.
  """
  use PassWeb, :live_view

  alias Pass.Audit
  alias Pass.Vault
  alias Pass.Vault.Asset
  alias Pass.Accounts.Scope

  # The only fields a grid cell may write — everything else is ignored.
  @editable ~w(name category status institution estimated_value currency
               annual_return_pct dividend_yield_pct dividends_reinvested annual_draw
               loan_balance loan_interest_pct loan_monthly_payment hoa_monthly rent_monthly)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Spreadsheet
        <:subtitle>
          Edit cells directly — changes save when you leave a cell.
          <span :if={!@can_write}>You have view-only access.</span>
        </:subtitle>
        <:actions>
          <label class="mr-2 flex cursor-pointer items-center gap-2 text-sm">
            <input
              type="checkbox"
              class="toggle toggle-sm"
              phx-click="toggle_property"
              checked={@show_property}
            /> Property columns
          </label>
          <.button navigate={~p"/assets"}>Card view</.button>
        </:actions>
      </.header>

      <div class="overflow-x-auto rounded-box border border-base-300">
        <form id="grid-form" phx-change="save_cell">
          <table class="table table-sm">
            <thead>
              <tr>
                <th class="min-w-44">Name</th>
                <th>Category</th>
                <th class="min-w-32">Institution</th>
                <th class="min-w-28">Value</th>
                <th>Currency</th>
                <th>Return %</th>
                <th>Yield %</th>
                <th>Reinv.</th>
                <th class="min-w-24">Draw/yr</th>
                <%= if @show_property do %>
                  <th class="min-w-28">Loan bal.</th>
                  <th>Loan %</th>
                  <th class="min-w-24">Pay/mo</th>
                  <th class="min-w-24">HOA/mo</th>
                  <th class="min-w-24">Rent/mo</th>
                <% end %>
                <th>Status</th>
                <th :if={@can_write}><span class="sr-only">Delete</span></th>
              </tr>
            </thead>
            <tbody id="grid-rows" phx-update="stream">
              <tr :for={{dom_id, asset} <- @streams.assets} id={dom_id}>
                <td>
                  <.cell name={field_name(asset, :name)} value={asset.name} disabled={!@can_write} />
                  <div :if={@row_errors[asset.id]} class="mt-1 text-xs text-error">
                    {@row_errors[asset.id]}
                  </div>
                </td>
                <td>
                  <select
                    name={field_name(asset, :category)}
                    class="select select-xs select-bordered"
                    disabled={!@can_write}
                  >
                    <option
                      :for={{label, value} <- Asset.category_options()}
                      value={value}
                      selected={asset.category == value}
                    >
                      {label}
                    </option>
                  </select>
                </td>
                <td>
                  <.cell
                    name={field_name(asset, :institution)}
                    value={asset.institution}
                    disabled={!@can_write}
                  />
                </td>
                <td>
                  <.cell
                    name={field_name(asset, :estimated_value)}
                    value={asset.estimated_value}
                    type="number"
                    disabled={!@can_write}
                  />
                </td>
                <td>
                  <.cell
                    name={field_name(asset, :currency)}
                    value={asset.currency}
                    class="w-16"
                    disabled={!@can_write}
                  />
                </td>
                <td>
                  <.cell
                    name={field_name(asset, :annual_return_pct)}
                    value={asset.annual_return_pct}
                    type="number"
                    class="w-20"
                    placeholder={"#{Pass.Vault.Projection.default_return(asset.category)}"}
                    disabled={!@can_write}
                  />
                </td>
                <td>
                  <.cell
                    name={field_name(asset, :dividend_yield_pct)}
                    value={asset.dividend_yield_pct}
                    type="number"
                    class="w-20"
                    disabled={!@can_write}
                  />
                </td>
                <td class="text-center">
                  <input type="hidden" name={field_name(asset, :dividends_reinvested)} value="false" />
                  <input
                    type="checkbox"
                    name={field_name(asset, :dividends_reinvested)}
                    value="true"
                    checked={asset.dividends_reinvested}
                    class="checkbox checkbox-xs"
                    disabled={!@can_write}
                  />
                </td>
                <td>
                  <.cell
                    name={field_name(asset, :annual_draw)}
                    value={asset.annual_draw}
                    type="number"
                    disabled={!@can_write}
                  />
                </td>
                <%= if @show_property do %>
                  <td>
                    <.cell
                      name={field_name(asset, :loan_balance)}
                      value={asset.loan_balance}
                      type="number"
                      disabled={!@can_write}
                    />
                  </td>
                  <td>
                    <.cell
                      name={field_name(asset, :loan_interest_pct)}
                      value={asset.loan_interest_pct}
                      type="number"
                      class="w-20"
                      disabled={!@can_write}
                    />
                  </td>
                  <td>
                    <.cell
                      name={field_name(asset, :loan_monthly_payment)}
                      value={asset.loan_monthly_payment}
                      type="number"
                      disabled={!@can_write}
                    />
                  </td>
                  <td>
                    <.cell
                      name={field_name(asset, :hoa_monthly)}
                      value={asset.hoa_monthly}
                      type="number"
                      disabled={!@can_write}
                    />
                  </td>
                  <td>
                    <.cell
                      name={field_name(asset, :rent_monthly)}
                      value={asset.rent_monthly}
                      type="number"
                      disabled={!@can_write}
                    />
                  </td>
                <% end %>
                <td>
                  <select
                    name={field_name(asset, :status)}
                    class="select select-xs select-bordered"
                    disabled={!@can_write}
                  >
                    <option
                      :for={status <- Asset.statuses()}
                      value={status}
                      selected={asset.status == status}
                    >
                      {Phoenix.Naming.humanize(status)}
                    </option>
                  </select>
                </td>
                <td :if={@can_write}>
                  <button
                    type="button"
                    class="btn btn-ghost btn-xs text-error"
                    phx-click="delete"
                    phx-value-id={asset.id}
                    data-confirm={"Delete #{asset.name}?"}
                    aria-label={"Delete #{asset.name}"}
                  >
                    ✕
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </form>
      </div>

      <form
        :if={@can_write}
        id="new-asset-form"
        phx-submit="create"
        class="mt-4 flex flex-wrap items-end gap-2"
      >
        <div>
          <label for="new_name" class="fieldset-label text-xs">New asset</label>
          <input
            type="text"
            id="new_name"
            name="name"
            required
            placeholder="Name — press Enter to add"
            class="input input-sm input-bordered w-64"
            autocomplete="off"
          />
        </div>
        <select name="category" class="select select-sm select-bordered" aria-label="Category">
          <option :for={{label, value} <- Asset.category_options()} value={value}>{label}</option>
        </select>
        <input
          type="number"
          name="estimated_value"
          step="any"
          min="0"
          placeholder="Value (optional)"
          class="input input-sm input-bordered w-36"
          aria-label="Estimated value"
        />
        <.button variant="primary">Add</.button>
      </form>

      <p class="mt-3 text-xs text-base-content/60">
        Blank a cell to clear it. Full details (documents, credentials, instructions) live in
        the <.link navigate={~p"/assets"} class="link">card view</.link>.
      </p>
    </Layouts.app>
    """
  end

  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :type, :string, default: "text"
  attr :class, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :disabled, :boolean, default: false

  defp cell(assigns) do
    ~H"""
    <input
      type={@type}
      name={@name}
      value={@value}
      step={@type == "number" && "any"}
      placeholder={@placeholder}
      disabled={@disabled}
      phx-debounce="blur"
      class={["input input-xs input-bordered w-full min-w-20", @class]}
    />
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Vault.subscribe_assets()

    {:ok,
     socket
     |> assign(:page_title, "Spreadsheet")
     |> assign(:can_write, Scope.can?(socket.assigns.current_scope, :write))
     |> assign(:show_property, false)
     |> assign(:row_errors, %{})
     |> stream(:assets, Vault.list_assets())}
  end

  @impl true
  def handle_event("toggle_property", _params, socket) do
    {:noreply,
     socket
     |> update(:show_property, &(!&1))
     |> stream(:assets, Vault.list_assets(), reset: true)}
  end

  def handle_event("save_cell", %{"_target" => ["assets", id, field]} = params, socket)
      when field in @editable do
    guard_write(socket, fn ->
      value = get_in(params, ["assets", id, field])
      asset = Vault.get_asset!(id)

      case Vault.update_asset(asset, %{field => value}) do
        {:ok, updated} ->
          Audit.log(socket.assigns.current_scope, "asset.updated",
            entity_type: "asset",
            entity_id: updated.id,
            summary: "#{updated.name} (#{field})"
          )

          {:noreply,
           socket
           |> update(:row_errors, &Map.delete(&1, id))
           |> stream_insert(:assets, updated)}

        {:error, changeset} ->
          # Streamed rows only re-render when re-inserted, so push the row back
          # in (with its stored values) to surface the error message.
          {:noreply,
           socket
           |> update(:row_errors, &Map.put(&1, id, error_text(changeset)))
           |> stream_insert(:assets, asset)}
      end
    end)
  end

  def handle_event("save_cell", _params, socket), do: {:noreply, socket}

  def handle_event("create", params, socket) do
    guard_write(socket, fn ->
      attrs = Map.take(params, ["name", "category", "estimated_value"])

      case Vault.create_asset(socket.assigns.current_scope, attrs) do
        {:ok, asset} ->
          Audit.log(socket.assigns.current_scope, "asset.created",
            entity_type: "asset",
            entity_id: asset.id,
            summary: asset.name
          )

          {:noreply,
           socket
           |> stream_insert(:assets, asset)
           |> put_flash(:info, "#{asset.name} added.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Couldn't add that asset — a name is required.")}
      end
    end)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    guard_write(socket, fn ->
      asset = Vault.get_asset!(id)
      {:ok, _} = Vault.delete_asset(asset)

      Audit.log(socket.assigns.current_scope, "asset.deleted",
        entity_type: "asset",
        entity_id: asset.id,
        summary: asset.name
      )

      {:noreply, stream_delete(socket, :assets, asset)}
    end)
  end

  # Live updates from other members (own saves also arrive here — harmless).
  @impl true
  def handle_info({:created, asset}, socket) do
    {:noreply, stream_insert(socket, :assets, asset)}
  end

  def handle_info({:updated, asset}, socket) do
    {:noreply, stream_insert(socket, :assets, asset)}
  end

  def handle_info({:deleted, asset}, socket) do
    {:noreply, stream_delete(socket, :assets, asset)}
  end

  defp guard_write(socket, fun) do
    if socket.assigns.can_write do
      fun.()
    else
      {:noreply, put_flash(socket, :error, "You have view-only access.")}
    end
  end

  defp field_name(asset, field), do: "assets[#{asset.id}][#{field}]"

  defp error_text(changeset) do
    Enum.map_join(changeset.errors, "; ", fn {field, error} ->
      "#{Phoenix.Naming.humanize(field)} #{PassWeb.CoreComponents.translate_error(error)}"
    end)
  end
end
