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

      <section class="mt-10 space-y-4">
        <h2 class="text-lg font-semibold">Documents</h2>
        <p class="text-xs text-base-content/60">
          Files are encrypted at rest. Downloads require you to be signed in. Max 10&nbsp;MB each.
        </p>

        <form
          id="document-form"
          phx-submit="save_document"
          phx-change="validate_document"
          class="rounded-box border border-base-300 p-4 space-y-3"
        >
          <.live_file_input upload={@uploads.document} class="file-input file-input-bordered w-full" />

          <div :for={entry <- @uploads.document.entries} class="flex items-center gap-3 text-sm">
            <span class="truncate">{entry.client_name}</span>
            <progress value={entry.progress} max="100" class="progress w-32"></progress>
            <button
              type="button"
              class="btn btn-xs"
              phx-click="cancel_upload"
              phx-value-ref={entry.ref}
            >
              Cancel
            </button>
            <span
              :for={err <- upload_errors(@uploads.document, entry)}
              class="text-error text-xs"
            >
              {error_to_string(err)}
            </span>
          </div>

          <p :for={err <- upload_errors(@uploads.document)} class="text-error text-xs">
            {error_to_string(err)}
          </p>

          <.button variant="primary" phx-disable-with="Uploading...">Upload document</.button>
        </form>

        <ul id="documents" phx-update="stream" class="space-y-2">
          <li
            :for={{dom_id, document} <- @streams.documents}
            id={dom_id}
            class="rounded-box border border-base-300 p-4 flex items-center justify-between gap-4"
          >
            <div class="min-w-0">
              <p class="font-medium truncate">{document.filename}</p>
              <p class="text-xs text-base-content/60">
                {document.content_type} · {format_bytes(document.byte_size)}
              </p>
            </div>
            <div class="flex gap-2 flex-none">
              <.link
                href={~p"/assets/#{@asset}/documents/#{document.id}/download"}
                class="btn btn-xs"
              >
                Download
              </.link>
              <button
                type="button"
                class="btn btn-xs btn-error btn-soft"
                phx-click="delete_document"
                phx-value-id={document.id}
                data-confirm={"Delete \"#{document.filename}\"?"}
              >
                Delete
              </button>
            </div>
          </li>
        </ul>

        <p :if={@document_count == 0} class="text-sm text-base-content/60">
          No documents attached yet.
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
    documents = Vault.list_documents(asset)

    {:ok,
     socket
     |> assign(:page_title, asset.name)
     |> assign(:asset, asset)
     |> assign(:adding?, false)
     |> assign(:credential_count, length(credentials))
     |> assign(:document_count, length(documents))
     |> assign_new_credential_form()
     |> stream(:credentials, credentials)
     |> stream(:documents, documents)
     |> allow_upload(:document,
       accept: ~w(.pdf .png .jpg .jpeg .gif .webp .txt .csv .doc .docx .xls .xlsx),
       max_entries: 1,
       max_file_size: 10_000_000
     )}
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

  def handle_event("validate_document", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :document, ref)}
  end

  def handle_event("save_document", _params, socket) do
    results =
      consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
        attrs = %{
          filename: entry.client_name,
          content_type: entry.client_type,
          byte_size: entry.client_size,
          data: File.read!(path)
        }

        {:ok, Vault.create_document(socket.assigns.asset, attrs)}
      end)

    socket =
      Enum.reduce(results, socket, fn
        {:ok, document}, acc ->
          acc
          |> update(:document_count, &(&1 + 1))
          |> stream_insert(:documents, Vault.document_meta(document))
          |> put_flash(:info, "Document uploaded.")

        {:error, _changeset}, acc ->
          put_flash(acc, :error, "A document couldn't be saved.")
      end)

    {:noreply, socket}
  end

  def handle_event("delete_document", %{"id" => id}, socket) do
    document = Vault.get_document!(socket.assigns.asset, id)
    {:ok, _} = Vault.delete_document(document)

    {:noreply,
     socket
     |> update(:document_count, &max(&1 - 1, 0))
     |> stream_delete(:documents, document)}
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

  defp format_bytes(nil), do: "—"
  defp format_bytes(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1_024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp error_to_string(:too_large), do: "File is too large (max 10 MB)."
  defp error_to_string(:not_accepted), do: "That file type isn't allowed."
  defp error_to_string(:too_many_files), do: "Only one file at a time."
  defp error_to_string(_), do: "Upload failed."
end
