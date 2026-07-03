defmodule PassWeb.AssetLive.Show do
  use PassWeb, :live_view

  alias Pass.Vault
  alias Pass.Vault.Asset

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@asset.name}
        <:subtitle>
          <span class="badge badge-ghost">{Asset.humanize_category(@asset.category)}</span>
          <span :if={@asset.institution}>· {@asset.institution}</span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/assets"}>Back</.button>
          <.button variant="primary" navigate={~p"/assets/#{@asset}/edit"}>
            <.icon name="hero-pencil-square" /> Edit
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Estimated value">{format_value(@asset)}</:item>
        <:item title="Location">{@asset.location || "—"}</:item>
        <:item title="Status">{@asset.status}</:item>
        <:item :if={@asset.description} title="Description">{@asset.description}</:item>
      </.list>

      <div class="mt-8 space-y-6">
        <.instruction title="How to access it" body={@asset.access_instructions} />
        <.instruction title="How to prove ownership" body={@asset.ownership_proof} />
        <.instruction title="How to sell or transfer it" body={@asset.sale_instructions} />
      </div>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :body, :string, default: nil

  defp instruction(assigns) do
    ~H"""
    <section class="rounded-box border border-base-300 p-4">
      <h3 class="font-semibold mb-2">{@title}</h3>
      <p :if={@body} class="whitespace-pre-wrap text-sm text-base-content/80">{@body}</p>
      <p :if={!@body} class="text-sm text-base-content/50 italic">Not documented yet.</p>
    </section>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket), do: Vault.subscribe_assets()
    asset = Vault.get_asset!(id)

    {:ok,
     socket
     |> assign(:page_title, asset.name)
     |> assign(:asset, asset)}
  end

  @impl true
  def handle_info({:updated, %Asset{id: id} = asset}, %{assigns: %{asset: %{id: id}}} = socket) do
    {:noreply, assign(socket, :asset, asset)}
  end

  def handle_info({:deleted, %Asset{id: id}}, %{assigns: %{asset: %{id: id}}} = socket) do
    {:noreply,
     socket
     |> put_flash(:info, "This asset was deleted.")
     |> push_navigate(to: ~p"/assets")}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp format_value(%Asset{estimated_value: nil}), do: "—"

  defp format_value(%Asset{estimated_value: value, currency: currency}) do
    "#{currency} #{Decimal.round(value, 2)}"
  end
end
