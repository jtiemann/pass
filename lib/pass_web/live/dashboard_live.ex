defmodule PassWeb.DashboardLive do
  @moduledoc "Landing page: a welcome for guests, a vault overview for members."
  use PassWeb, :live_view

  alias Pass.{Audit, Vault}
  alias Pass.Vault.Asset
  alias Pass.Accounts.Scope

  @impl true
  def render(%{current_scope: %{user: %{}}} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Your vault
        <:subtitle>A quick overview of everything you're keeping safe.</:subtitle>
        <:actions>
          <.button :if={@can_write} variant="primary" navigate={~p"/assets/new"}>
            <.icon name="hero-plus" /> New asset
          </.button>
        </:actions>
      </.header>

      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <.stat label="Assets" value={@summary.total_assets} />
        <.stat label="Estimated value" value={format_totals(@summary.totals)} />
        <.stat label="Categories" value={length(@summary.by_category)} />
      </div>

      <section :if={@summary.total_assets > 0} class="mt-8 space-y-3">
        <h2 class="text-lg font-semibold">By category</h2>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <.link
            :for={row <- @summary.by_category}
            navigate={~p"/assets"}
            class="rounded-box border border-base-300 p-4 flex items-center justify-between hover:bg-base-200"
          >
            <span class="font-medium">{Asset.humanize_category(row.category)}</span>
            <span class="text-sm text-base-content/70">
              {row.count}<span :if={row.totals != []}> · {format_totals(row.totals)}</span>
            </span>
          </.link>
        </div>
      </section>

      <section :if={@summary.recent != []} class="mt-8 space-y-3">
        <h2 class="text-lg font-semibold">Recently added</h2>
        <ul class="rounded-box border border-base-300 divide-y divide-base-300">
          <li :for={asset <- @summary.recent}>
            <.link
              navigate={~p"/assets/#{asset}"}
              class="flex items-center justify-between p-4 hover:bg-base-200"
            >
              <span class="font-medium">{asset.name}</span>
              <span class="badge badge-ghost">{Asset.humanize_category(asset.category)}</span>
            </.link>
          </li>
        </ul>
      </section>

      <section :if={@activity != []} class="mt-8 space-y-3">
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-semibold">Recent activity</h2>
          <.link navigate={~p"/audit"} class="text-sm link">View all</.link>
        </div>
        <ul class="rounded-box border border-base-300 divide-y divide-base-300 text-sm">
          <li :for={event <- @activity} class="flex items-center justify-between gap-4 p-3">
            <span>{event.actor_email || "—"} · {humanize_action(event.action)}</span>
            <span class="text-base-content/60 truncate">{event.summary}</span>
          </li>
        </ul>
      </section>

      <div
        :if={@summary.total_assets == 0}
        class="mt-8 rounded-box border border-base-300 p-8 text-center space-y-3"
      >
        <p class="text-base-content/70">Your vault is empty. Add your first asset to get started.</p>
        <.button :if={@can_write} variant="primary" navigate={~p"/assets/new"}>Add an asset</.button>
      </div>
    </Layouts.app>
    """
  end

  # Guest landing
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl text-center py-14 sm:py-20 space-y-7">
        <img src={~p"/images/logo.svg"} width="56" height="56" alt="" class="mx-auto" />
        <h1 class="text-4xl sm:text-5xl font-semibold leading-tight text-balance">
          Keep your family's assets safe and findable.
        </h1>
        <p class="text-lg text-base-content/70 text-pretty">
          Pass is a secure vault for your accounts, paperwork, and the details your family
          would need to access, prove ownership of, or sell what you own — protected by
          passkeys and encrypted at rest.
        </p>
        <div class="flex justify-center gap-3">
          <.link navigate={~p"/users/register"} class="btn btn-primary btn-lg">
            Get started
          </.link>
          <.link navigate={~p"/users/log-in"} class="btn btn-ghost btn-lg">Log in</.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp stat(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300 bg-base-200/40 p-5">
      <div class="text-sm text-base-content/60">{@label}</div>
      <div class="font-display text-3xl font-semibold tracking-tight mt-1">{@value}</div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, :page_title, "Home")

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:ok,
       socket
       |> assign(:can_write, Scope.can?(socket.assigns.current_scope, :write))
       |> assign(:summary, Vault.dashboard_summary())
       |> assign(:activity, recent_activity(socket.assigns.current_scope))}
    else
      {:ok, socket}
    end
  end

  # Only owners see the activity feed (it can reveal who accessed what).
  defp recent_activity(scope) do
    if Scope.can?(scope, :manage_users), do: Audit.list_events(6), else: []
  end

  defp humanize_action(action), do: action |> String.replace(".", " ") |> String.replace("_", " ")

  # One entry per currency; never a blind sum across currencies.
  defp format_totals([]), do: "—"

  defp format_totals(totals) do
    Enum.map_join(totals, " · ", fn {currency, sum} ->
      PassWeb.Format.money(sum, "#{currency} ")
    end)
  end
end
