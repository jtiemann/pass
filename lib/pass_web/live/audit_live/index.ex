defmodule PassWeb.AuditLive.Index do
  @moduledoc "Owner-only view of the audit trail."
  use PassWeb, :live_view

  alias Pass.Audit

  @page_size 50
  @entities ~w(asset credential document contact user)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Audit log
        <:subtitle>A record of who accessed and changed the vault.</:subtitle>
        <:actions>
          <form id="audit-filter" phx-change="filter">
            <select name="entity" class="select select-bordered select-sm" aria-label="Filter by type">
              <option value="" selected={@entity == nil}>All activity</option>
              <option :for={entity <- entities()} value={entity} selected={@entity == entity}>
                {Phoenix.Naming.humanize(entity)}s
              </option>
            </select>
          </form>
        </:actions>
      </.header>

      <.table id="audit" rows={@events}>
        <:col :let={event} label="When">
          <span class="text-sm">{Calendar.strftime(event.inserted_at, "%Y-%m-%d %H:%M UTC")}</span>
        </:col>
        <:col :let={event} label="Who">{event.actor_email || "—"}</:col>
        <:col :let={event} label="Action">
          <span class="badge badge-ghost">{humanize_action(event.action)}</span>
        </:col>
        <:col :let={event} label="Details">{event.summary}</:col>
      </.table>

      <p :if={@events == []} class="text-sm text-base-content/60">No activity recorded yet.</p>

      <div :if={length(@events) >= @limit} class="mt-4 text-center">
        <.button phx-click="load_more">Show more</.button>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Audit log")
     |> assign(:entity, nil)
     |> assign(:limit, @page_size)
     |> load_events()}
  end

  @impl true
  def handle_event("filter", %{"entity" => entity}, socket) do
    entity = if entity in entities(), do: entity, else: nil

    {:noreply,
     socket
     |> assign(:entity, entity)
     |> assign(:limit, @page_size)
     |> load_events()}
  end

  def handle_event("load_more", _params, socket) do
    {:noreply,
     socket
     |> update(:limit, &(&1 + @page_size))
     |> load_events()}
  end

  defp load_events(socket) do
    assign(socket, :events, Audit.list_events(socket.assigns.limit, socket.assigns.entity))
  end

  defp entities, do: @entities

  defp humanize_action(action) do
    action
    |> String.replace(".", " ")
    |> String.replace("_", " ")
  end
end
