defmodule PassWeb.AssetLive.Form do
  use PassWeb, :live_view

  alias Pass.Vault
  alias Pass.Vault.Asset

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>{@subtitle}</:subtitle>
      </.header>

      <.form for={@form} id="asset-form" phx-change="validate" phx-submit="save">
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.input field={@form[:name]} type="text" label="Name" required />
          <.input
            field={@form[:category]}
            type="select"
            label="Category"
            options={Asset.category_options()}
          />
          <.input field={@form[:institution]} type="text" label="Institution / provider" />
          <.input
            field={@form[:location]}
            type="text"
            label="Location"
            placeholder="e.g. safe deposit box, home safe, URL"
          />
          <.input field={@form[:estimated_value]} type="number" label="Estimated value" step="0.01" />
          <.input field={@form[:currency]} type="text" label="Currency" />
          <.input
            field={@form[:status]}
            type="select"
            label="Status"
            options={Enum.map(Asset.statuses(), &{Phoenix.Naming.humanize(&1), &1})}
          />
        </div>

        <.input field={@form[:description]} type="textarea" label="Description" />

        <div class="divider">How to access, prove ownership, and sell</div>

        <.input
          field={@form[:access_instructions]}
          type="textarea"
          label="How to access it"
          placeholder="Where the keys/logins/paperwork live and the steps to get in."
        />
        <.input
          field={@form[:ownership_proof]}
          type="textarea"
          label="How to prove ownership"
          placeholder="Deeds, titles, statements — what proves this is ours and where it is."
        />
        <.input
          field={@form[:sale_instructions]}
          type="textarea"
          label="How to sell or transfer it"
          placeholder="Who to contact and what's needed to sell or transfer it."
        />

        <div class="mt-6 flex items-center gap-3">
          <.button variant="primary" phx-disable-with="Saving...">Save asset</.button>
          <.button navigate={@cancel_navigate}>Cancel</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    asset = %Asset{}

    socket
    |> assign(:page_title, "New asset")
    |> assign(:subtitle, "Add something the family owns.")
    |> assign(:asset, asset)
    |> assign(:cancel_navigate, ~p"/assets")
    |> assign_form(Vault.change_asset(asset))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    asset = Vault.get_asset!(id)

    socket
    |> assign(:page_title, "Edit asset")
    |> assign(:subtitle, asset.name)
    |> assign(:asset, asset)
    |> assign(:cancel_navigate, ~p"/assets/#{asset}")
    |> assign_form(Vault.change_asset(asset))
  end

  @impl true
  def handle_event("validate", %{"asset" => params}, socket) do
    changeset = Vault.change_asset(socket.assigns.asset, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"asset" => params}, socket) do
    save_asset(socket, socket.assigns.live_action, params)
  end

  defp save_asset(socket, :new, params) do
    case Vault.create_asset(socket.assigns.current_scope, params) do
      {:ok, asset} ->
        {:noreply,
         socket
         |> put_flash(:info, "Asset created.")
         |> push_navigate(to: ~p"/assets/#{asset}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_asset(socket, :edit, params) do
    case Vault.update_asset(socket.assigns.asset, params) do
      {:ok, asset} ->
        {:noreply,
         socket
         |> put_flash(:info, "Asset updated.")
         |> push_navigate(to: ~p"/assets/#{asset}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "asset"))
  end
end
