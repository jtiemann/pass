defmodule PassWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PassWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="sticky top-0 z-40 border-b border-base-300 bg-base-100/90 backdrop-blur">
      <div class="mx-auto flex h-16 max-w-5xl items-center justify-between px-4 sm:px-6 lg:px-8">
        <a href="/" class="flex items-center gap-2.5">
          <img src={~p"/images/logo.svg"} width="28" height="28" alt="" />
          <span class="font-display text-xl font-semibold tracking-tight">pass</span>
        </a>

        <nav class="flex items-center gap-1">
          <%!-- Desktop: full link row (the email chip stays in the DOM for all sizes) --%>
          <ul class="hidden md:flex items-center gap-1">
            <li :if={@current_scope && @current_scope.user}>
              <span
                class="inline-block max-w-[18ch] truncate align-middle px-2 text-xs text-base-content/50"
                title={@current_scope.user.email}
              >
                {@current_scope.user.email}
              </span>
            </li>
            <.nav_items current_scope={@current_scope} />
          </ul>

          <%!-- Mobile: hamburger dropdown with the same links --%>
          <div class="dropdown dropdown-end md:hidden">
            <div tabindex="0" role="button" class="btn btn-ghost btn-sm" aria-label="Menu">
              <.icon name="hero-bars-3" class="size-5" />
            </div>
            <ul
              tabindex="0"
              class="dropdown-content menu z-50 mt-2 w-52 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg"
            >
              <li :if={@current_scope && @current_scope.user} class="menu-title truncate">
                {@current_scope.user.email}
              </li>
              <.nav_items current_scope={@current_scope} />
            </ul>
          </div>

          <div class="ml-2">
            <.theme_toggle />
          </div>
        </nav>
      </div>
    </header>

    <main class="px-4 py-10 sm:px-6 sm:py-12 lg:px-8">
      <div class="mx-auto max-w-3xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  attr :current_scope, :map, default: nil

  defp nav_items(assigns) do
    ~H"""
    <%= if @current_scope && @current_scope.user do %>
      <li><.link navigate={~p"/assets"} class="btn btn-ghost btn-sm">Assets</.link></li>
      <li><.link navigate={~p"/projections"} class="btn btn-ghost btn-sm">Projections</.link></li>
      <li :if={@current_scope.user.role == :owner}>
        <.link navigate={~p"/users"} class="btn btn-ghost btn-sm">Members</.link>
      </li>
      <li :if={@current_scope.user.role == :owner}>
        <.link navigate={~p"/audit"} class="btn btn-ghost btn-sm">Audit</.link>
      </li>
      <li>
        <.link navigate={~p"/users/settings"} class="btn btn-ghost btn-sm">Settings</.link>
      </li>
      <li>
        <.link
          href={~p"/users/log-out"}
          method="delete"
          class="btn btn-ghost btn-sm text-base-content/60"
        >
          Log out
        </.link>
      </li>
    <% else %>
      <li><.link navigate={~p"/users/log-in"} class="btn btn-ghost btn-sm">Log in</.link></li>
      <li>
        <.link navigate={~p"/users/register"} class="btn btn-primary btn-sm">Sign up</.link>
      </li>
    <% end %>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
