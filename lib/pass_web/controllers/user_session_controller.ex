defmodule PassWeb.UserSessionController do
  use PassWeb, :controller

  alias Pass.Accounts
  alias Pass.Accounts.Passkeys
  alias PassWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "User confirmed successfully.")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)
        finish_or_require_2fa(conn, user, user_params, info)

      _ ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      finish_or_require_2fa(conn, user, user_params, info)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end

  # After the first factor succeeds: if the user has a passkey enrolled, defer the
  # actual login and send them to the second-factor step. Otherwise (no passkey
  # yet) log them straight in so no one is locked out before enrolling.
  defp finish_or_require_2fa(conn, user, params, info) do
    if Passkeys.has_passkey?(user) do
      conn
      |> put_session(:pending_2fa_user_id, user.id)
      |> put_session(:pending_2fa_remember_me, params["remember_me"] == "true")
      |> put_session(:pending_2fa_at, System.system_time(:second))
      |> redirect(to: ~p"/users/two-factor")
    else
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, params)
    end
  end
end
