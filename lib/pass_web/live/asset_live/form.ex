defmodule PassWeb.AssetLive.Form do
  use PassWeb, :live_view

  alias Pass.Vault
  alias Pass.Vault.{Asset, Projection}
  alias Pass.Accounts.Scope
  alias Pass.Audit

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

        <div class="divider">Growth assumptions</div>

        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <.input
            field={@form[:annual_return_pct]}
            type="number"
            label="Expected annual return (%)"
            step="0.1"
            placeholder={return_placeholder(@form)}
          />
          <.input
            field={@form[:dividend_yield_pct]}
            type="number"
            label="Dividend / income yield (%)"
            step="0.1"
            placeholder="0"
          />
          <.input field={@form[:dividends_reinvested]} type="checkbox" label="Reinvest dividends" />
          <.input
            field={@form[:annual_draw]}
            type="number"
            label="Annual draw (withdrawal)"
            step="0.01"
            min="0"
            placeholder="0"
          />
        </div>
        <p class="text-xs text-base-content/60">
          Used by <.link navigate={~p"/projections"} class="link">Projections</.link>.
          Leave the return blank to assume the category's historical default. The annual
          draw is withdrawn at the end of each year to cover expenses elsewhere.
          Estimates only — not financial advice.
        </p>

        <div :if={selected_category(@form) == :real_estate}>
          <div class="divider">Property finances</div>

          <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <.input
              field={@form[:loan_balance]}
              type="number"
              label="Loan balance"
              step="0.01"
              min="0"
            />
            <.input
              field={@form[:loan_interest_pct]}
              type="number"
              label="Loan interest rate (%/yr)"
              step="0.01"
              min="0"
            />
            <.input
              field={@form[:loan_monthly_payment]}
              type="number"
              label="Loan payment (monthly)"
              step="0.01"
              min="0"
            />
            <.input
              field={@form[:hoa_monthly]}
              type="number"
              label="HOA fee (monthly)"
              step="0.01"
              min="0"
            />
            <.input
              field={@form[:rent_monthly]}
              type="number"
              label="Rental income (monthly)"
              step="0.01"
              min="0"
            />
          </div>
          <p class="mt-2 text-xs text-base-content/60">
            Projections count your equity (value − loan) and treat rent, HOA, and loan
            payments as yearly cash flows. The loan amortizes monthly at the given rate.
          </p>
        </div>

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
    if Scope.can?(socket.assigns.current_scope, :write) do
      {:ok, apply_action(socket, socket.assigns.live_action, params)}
    else
      {:ok,
       socket
       |> put_flash(:error, "You have view-only access.")
       |> push_navigate(to: ~p"/assets")}
    end
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
        Audit.log(socket.assigns.current_scope, "asset.created",
          entity_type: "asset",
          entity_id: asset.id,
          summary: asset.name
        )

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
        Audit.log(socket.assigns.current_scope, "asset.updated",
          entity_type: "asset",
          entity_id: asset.id,
          summary: asset.name
        )

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

  # Placeholder showing the historical default that applies if the return is
  # left blank, tracking the currently selected category.
  defp return_placeholder(form) do
    category = selected_category(form)
    "#{Projection.default_return(category)} — #{Asset.humanize_category(category)} default"
  end

  defp selected_category(form) do
    case Phoenix.HTML.Form.input_value(form, :category) do
      category when is_atom(category) and not is_nil(category) -> category
      category when is_binary(category) and category != "" -> String.to_existing_atom(category)
      _ -> :other
    end
  end
end
