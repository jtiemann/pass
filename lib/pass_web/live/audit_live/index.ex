defmodule PassWeb.AuditLive.Index do
  @moduledoc "Owner-only view of the audit trail."
  use PassWeb, :live_view

  alias Pass.Audit

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Audit log
        <:subtitle>A record of who accessed and changed the vault.</:subtitle>
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
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Audit log")
     |> assign(:events, Audit.list_events())}
  end

  defp humanize_action(action) do
    action
    |> String.replace(".", " ")
    |> String.replace("_", " ")
  end
end
