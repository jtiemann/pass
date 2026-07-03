defmodule PassWeb.UserLive.Admin do
  @moduledoc """
  Owner-only member management: view users and change their roles.
  """
  use PassWeb, :live_view

  # Role changes redefine who can access the vault — require fresh auth.
  on_mount {PassWeb.UserAuth, :require_sudo_mode}

  alias Pass.Accounts
  alias Pass.Accounts.User
  alias Pass.Audit

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Members
        <:subtitle>Manage who can access this vault and what they can do.</:subtitle>
      </.header>

      <div class="rounded-box border border-base-300 divide-y divide-base-300">
        <div :for={user <- @users} class="flex items-center justify-between gap-4 p-4">
          <div class="min-w-0">
            <p class="font-medium truncate">{user.email}</p>
            <p :if={user.id == @current_scope.user.id} class="text-xs text-base-content/60">
              This is you
            </p>
          </div>

          <form id={"role-form-#{user.id}"} phx-change="change_role" class="flex items-center gap-2">
            <input type="hidden" name="user_id" value={user.id} />
            <select name="role" class="select select-bordered select-sm" aria-label="Role">
              <option :for={role <- User.roles()} value={role} selected={user.role == role}>
                {Phoenix.Naming.humanize(role)}
              </option>
            </select>
          </form>
        </div>
      </div>

      <div class="mt-4 text-sm text-base-content/70 space-y-1">
        <p><span class="font-semibold">Owner</span> — full access, and can manage members.</p>
        <p><span class="font-semibold">Member</span> — can view and edit the vault.</p>
        <p><span class="font-semibold">Viewer</span> — can view the vault, but not change it.</p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Members") |> load_users()}
  end

  @impl true
  def handle_event("change_role", %{"user_id" => id, "role" => role}, socket) do
    user = Accounts.get_user!(id)

    case Accounts.update_user_role(user, role) do
      {:ok, updated} ->
        Audit.log(socket.assigns.current_scope, "user.role_changed",
          entity_type: "user",
          entity_id: updated.id,
          summary: "#{updated.email} → #{updated.role}"
        )

        {:noreply, socket |> put_flash(:info, "Role updated.") |> load_users()}

      {:error, :last_owner} ->
        {:noreply,
         socket
         |> put_flash(:error, "You can't remove the last owner.")
         |> load_users()}

      {:error, _changeset} ->
        {:noreply, socket |> put_flash(:error, "Couldn't update that role.") |> load_users()}
    end
  end

  defp load_users(socket), do: assign(socket, :users, Accounts.list_users())
end
