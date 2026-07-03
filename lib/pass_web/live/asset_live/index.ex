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

      <.table
        :if={!@empty?}
        id="assets"
        rows={@streams.assets}
        row_click={fn {_id, asset} -> JS.navigate(~p"/assets/#{asset}") end}
      >
        <:col :let={{_id, asset}} label="Name">
          <div class="font-medium">{asset.name}</div>
          <div :if={asset.institution} class="text-xs text-base-content/60">
            {asset.institution}
          </div>
        </:col>
        <:col :let={{_id, asset}} label="Category">
          <span class="badge badge-ghost">{Asset.humanize_category(asset.category)}</span>
        </:col>
        <:col :let={{_id, asset}} label="Value">{format_value(asset)}</:col>
        <:col :let={{_id, asset}} label="Status">
          <span class={[
            "badge",
            asset.status == :active && "badge-success",
            asset.status == :archived && "badge-ghost"
          ]}>
            {asset.status}
          </span>
        </:col>
        <:action :let={{_id, asset}}>
          <.link navigate={~p"/assets/#{asset}"}>View</.link>
        </:action>
        <:action :let={{id, asset}}>
          <.link :if={@can_write} navigate={~p"/assets/#{asset}/edit"}>Edit</.link>
          <.link
            :if={@can_write}
            phx-click={JS.push("delete", value: %{id: asset.id}) |> hide("##{id}")}
            data-confirm={"Delete #{asset.name}? This cannot be undone."}
            class="text-error"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Vault.subscribe_assets()

    assets = Vault.list_assets()

    {:ok,
     socket
     |> assign(:page_title, "Assets")
     |> assign(:can_write, Scope.can?(socket.assigns.current_scope, :write))
     |> assign(:count, length(assets))
     |> assign(:empty?, assets == [])
     |> stream(:assets, assets)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    if Scope.can?(socket.assigns.current_scope, :write) do
      asset = Vault.get_asset!(id)
      {:ok, _} = Vault.delete_asset(asset)

      Audit.log(socket.assigns.current_scope, "asset.deleted",
        entity_type: "asset",
        entity_id: asset.id,
        summary: asset.name
      )

      # Stream removal + count are handled via the broadcast handler below.
      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to delete assets.")}
    end
  end

  @impl true
  def handle_info({:created, asset}, socket) do
    {:noreply, socket |> adjust_count(+1) |> stream_insert(:assets, asset, at: 0)}
  end

  def handle_info({:updated, asset}, socket) do
    {:noreply, stream_insert(socket, :assets, asset)}
  end

  def handle_info({:deleted, asset}, socket) do
    {:noreply, socket |> adjust_count(-1) |> stream_delete(:assets, asset)}
  end

  defp adjust_count(socket, delta) do
    count = max(socket.assigns.count + delta, 0)
    socket |> assign(:count, count) |> assign(:empty?, count == 0)
  end

  defp format_value(%Asset{estimated_value: nil}), do: "—"

  defp format_value(%Asset{estimated_value: value, currency: currency}) do
    "#{currency} #{Decimal.round(value, 2)}"
  end
end
