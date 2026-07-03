defmodule PassWeb.AssetLive.Index do
  use PassWeb, :live_view

  alias Pass.Vault
  alias Pass.Vault.Asset
  alias Pass.Accounts.Scope
  alias Pass.Audit

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Assets
        <:subtitle>Everything the family owns, and how to get to it.</:subtitle>
        <:actions>
          <.button :if={@can_write} variant="primary" navigate={~p"/assets/new"}>
            <.icon name="hero-plus" /> New asset
          </.button>
        </:actions>
      </.header>

      <div :if={@empty?} class="rounded-box border border-base-300 p-8 text-center space-y-3">
        <p class="text-base-content/70">No assets yet.</p>
        <.button :if={@can_write} variant="primary" navigate={~p"/assets/new"}>
          Add your first asset
        </.button>
      </div>

      <div :if={!@empty?} id="asset-filter" phx-hook="Filter">
        <div class="mb-4 flex flex-col sm:flex-row sm:items-center gap-3">
          <div class="relative grow">
            <.icon
              name="hero-magnifying-glass"
              class="size-5 absolute left-3 top-1/2 -translate-y-1/2 text-base-content/40"
            />
            <input
              type="text"
              data-filter-input
              placeholder="Search by name, institution, category, or location…"
              class="input input-bordered w-full pl-10"
              autocomplete="off"
            />
          </div>
          <label class="flex flex-none cursor-pointer items-center gap-2 text-sm">
            <input
              type="checkbox"
              class="toggle toggle-sm"
              phx-click="toggle_archived"
              checked={@show_archived}
            /> Show archived
          </label>
        </div>

        <ul id="assets" phx-update="stream" class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <li
            :for={{dom_id, asset} <- @streams.assets}
            id={dom_id}
            data-search={search_text(asset)}
            class="rounded-box border border-base-300 p-4 hover:bg-base-200/40 transition-colors"
          >
            <div class="flex items-start justify-between gap-3">
              <.link navigate={~p"/assets/#{asset}"} class="min-w-0 grow">
                <p class="font-medium truncate">{asset.name}</p>
                <p :if={asset.institution} class="text-xs text-base-content/60 truncate">
                  {asset.institution}
                </p>
                <div class="mt-2 flex items-center gap-2 flex-wrap">
                  <span class="badge badge-ghost">{Asset.humanize_category(asset.category)}</span>
                  <span class="text-sm text-base-content/70">{format_value(asset)}</span>
                  <span :if={asset.status == :archived} class="badge badge-ghost badge-sm">
                    archived
                  </span>
                </div>
              </.link>

              <div :if={@can_write} class="flex flex-col items-end gap-1 flex-none text-sm">
                <.link navigate={~p"/assets/#{asset}/edit"}>Edit</.link>
                <.link
                  phx-click={JS.push("delete", value: %{id: asset.id}) |> hide("##{dom_id}")}
                  data-confirm={"Delete #{asset.name}? This cannot be undone."}
                  class="text-error"
                >
                  Delete
                </.link>
              </div>
            </div>
          </li>
        </ul>

        <p data-filter-empty style="display:none" class="text-sm text-base-content/60 mt-4">
          No assets match your search.
        </p>
      </div>
    </Layouts.app>
    """
  end

  # Text the client-side filter matches against.
  defp search_text(asset) do
    [asset.name, asset.institution, asset.location, Asset.humanize_category(asset.category)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Vault.subscribe_assets()

    {:ok,
     socket
     |> assign(:page_title, "Assets")
     |> assign(:can_write, Scope.can?(socket.assigns.current_scope, :write))
     |> assign(:show_archived, false)
     |> refresh_assets()}
  end

  @impl true
  def handle_event("toggle_archived", _params, socket) do
    {:noreply, socket |> update(:show_archived, &(!&1)) |> refresh_assets()}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    if Scope.can?(socket.assigns.current_scope, :write) do
      asset = Vault.get_asset!(id)
      {:ok, _} = Vault.delete_asset(asset)

      Audit.log(socket.assigns.current_scope, "asset.deleted",
        entity_type: "asset",
        entity_id: asset.id,
        summary: asset.name
      )

      # Stream removal is handled via the broadcast handler below.
      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to delete assets.")}
    end
  end

  # Any change to the vault (from this member or another) reloads the visible
  # list — at family scale, correctness beats incremental bookkeeping.
  @impl true
  def handle_info({event, _asset}, socket) when event in [:created, :updated, :deleted] do
    {:noreply, refresh_assets(socket)}
  end

  defp refresh_assets(socket) do
    all = Vault.list_assets()

    visible =
      if socket.assigns.show_archived,
        do: all,
        else: Enum.reject(all, &(&1.status == :archived))

    socket
    |> assign(:count, length(visible))
    # "empty" means the vault has nothing at all — if everything is archived,
    # the list (with its show-archived toggle) must stay visible.
    |> assign(:empty?, all == [])
    |> stream(:assets, visible, reset: true)
  end

  defp format_value(%Asset{estimated_value: nil}), do: "—"

  defp format_value(%Asset{estimated_value: value, currency: currency}) do
    PassWeb.Format.money(value, "#{currency} ")
  end
end
