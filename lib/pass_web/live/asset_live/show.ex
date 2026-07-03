defmodule PassWeb.AssetLive.Show do
  use PassWeb, :live_view

  alias Pass.Vault
  alias Pass.Vault.{Asset, Credential}

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

      <section class="mt-10 space-y-4">
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-semibold">Credentials</h2>
          <.button :if={!@adding?} phx-click="new_credential">
            <.icon name="hero-plus" /> Add credential
          </.button>
        </div>

        <p class="text-xs text-base-content/60">
          Secrets are encrypted at rest. Revealed or copied values clear automatically.
        </p>

        <.form
          :if={@adding?}
          for={@credential_form}
          id="credential-form"
          phx-change="validate_credential"
          phx-submit="save_credential"
          class="rounded-box border border-base-300 p-4 space-y-3"
        >
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <.input field={@credential_form[:label]} type="text" label="Label" required />
            <.input field={@credential_form[:username]} type="text" label="Username" />
            <.input field={@credential_form[:url]} type="text" label="URL" />
            <.input field={@credential_form[:secret]} type="password" label="Password / secret" />
          </div>
          <.input field={@credential_form[:notes]} type="textarea" label="Notes (encrypted)" />
          <div class="flex gap-2">
            <.button variant="primary" phx-disable-with="Saving...">Save credential</.button>
            <button type="button" class="btn" phx-click="cancel_credential">Cancel</button>
          </div>
        </.form>

        <ul id="credentials" phx-hook="Secrets" phx-update="stream" class="space-y-2">
          <li
            :for={{dom_id, credential} <- @streams.credentials}
            id={dom_id}
            class="rounded-box border border-base-300 p-4 flex items-start justify-between gap-4"
          >
            <div class="space-y-1 min-w-0">
              <p class="font-medium">{credential.label}</p>
              <p :if={credential.username} class="text-sm text-base-content/70">
                {credential.username}
              </p>
              <p :if={credential.url} class="text-sm">
                <a href={credential.url} target="_blank" rel="noopener" class="link">
                  {credential.url}
                </a>
              </p>

              <div :if={credential.secret} class="flex items-center gap-2 pt-1">
                <code id={"secret-value-#{credential.id}"} class="font-mono text-sm">••••••••</code>
                <button
                  type="button"
                  class="btn btn-xs"
                  phx-click="reveal"
                  phx-value-id={credential.id}
                >
                  Reveal
                </button>
                <button
                  type="button"
                  class="btn btn-xs"
                  phx-click="copy"
                  phx-value-id={credential.id}
                >
                  Copy
                </button>
                <span id={"secret-status-#{credential.id}"} class="text-xs text-base-content/60"></span>
              </div>
            </div>

            <button
              type="button"
              class="btn btn-xs btn-error btn-soft"
              phx-click="delete_credential"
              phx-value-id={credential.id}
              data-confirm={"Delete the credential \"#{credential.label}\"?"}
            >
              Delete
            </button>
          </li>
        </ul>

        <p :if={@credential_count == 0} class="text-sm text-base-content/60">
          No credentials stored for this asset yet.
        </p>
      </section>
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
    credentials = Vault.list_credentials(asset)

    {:ok,
     socket
     |> assign(:page_title, asset.name)
     |> assign(:asset, asset)
     |> assign(:adding?, false)
     |> assign(:credential_count, length(credentials))
     |> assign_new_credential_form()
     |> stream(:credentials, credentials)}
  end

  @impl true
  def handle_event("new_credential", _params, socket) do
    {:noreply, socket |> assign(:adding?, true) |> assign_new_credential_form()}
  end

  def handle_event("cancel_credential", _params, socket) do
    {:noreply, assign(socket, :adding?, false)}
  end

  def handle_event("validate_credential", %{"credential" => params}, socket) do
    changeset = %Credential{} |> Vault.change_credential(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :credential_form, to_form(changeset, as: "credential"))}
  end

  def handle_event("save_credential", %{"credential" => params}, socket) do
    case Vault.create_credential(socket.assigns.asset, params) do
      {:ok, credential} ->
        {:noreply,
         socket
         |> assign(:adding?, false)
         |> update(:credential_count, &(&1 + 1))
         |> assign_new_credential_form()
         |> stream_insert(:credentials, credential)
         |> put_flash(:info, "Credential saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :credential_form, to_form(changeset, as: "credential"))}
    end
  end

  def handle_event("delete_credential", %{"id" => id}, socket) do
    credential = Vault.get_credential!(socket.assigns.asset, id)
    {:ok, _} = Vault.delete_credential(credential)

    {:noreply,
     socket
     |> update(:credential_count, &max(&1 - 1, 0))
     |> stream_delete(:credentials, credential)}
  end

  def handle_event("reveal", %{"id" => id}, socket) do
    credential = Vault.get_credential!(socket.assigns.asset, id)
    {:noreply, push_event(socket, "secret:show", %{id: id, value: credential.secret || ""})}
  end

  def handle_event("copy", %{"id" => id}, socket) do
    credential = Vault.get_credential!(socket.assigns.asset, id)
    {:noreply, push_event(socket, "secret:copy", %{id: id, value: credential.secret || ""})}
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

  defp assign_new_credential_form(socket) do
    assign(
      socket,
      :credential_form,
      to_form(Vault.change_credential(%Credential{}), as: "credential")
    )
  end

  defp format_value(%Asset{estimated_value: nil}), do: "—"

  defp format_value(%Asset{estimated_value: value, currency: currency}) do
    "#{currency} #{Decimal.round(value, 2)}"
  end
end
