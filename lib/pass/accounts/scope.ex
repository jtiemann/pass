defmodule Pass.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Pass.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use as authorization, or to
  ensure specific code paths can only be access for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias Pass.Accounts.User

  defstruct user: nil

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  @doc """
  Authorization check for a scope. Actions:

    * `:read` — view the vault (all roles)
    * `:write` — create/edit/delete vault entries (owner, member)
    * `:manage_users` — change roles / manage members (owner only)

  """
  def can?(%__MODULE__{user: %User{role: role}}, action), do: allowed?(role, action)
  def can?(_scope, _action), do: false

  defp allowed?(:owner, _action), do: true
  defp allowed?(:member, action), do: action in [:read, :write]
  defp allowed?(:viewer, action), do: action == :read
  defp allowed?(_role, _action), do: false
end
