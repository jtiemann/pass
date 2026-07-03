defmodule PassWeb.TwoFactorController do
  @moduledoc """
  Second authentication factor at login. The user has already passed factor one
  (password or magic link) which left a short-lived `:pending_2fa_*` marker in the
  session. Here they prove possession of a passkey (or a recovery code) and the
  login is completed.
  """
  use PassWeb, :controller

  alias Pass.Accounts
  alias Pass.Accounts.{Passkeys, RecoveryCodes}
  alias PassWeb.UserAuth

  # Time allowed to complete the second factor after passing the first.
  @pending_ttl_seconds 600

  plug :require_pending_user

  @doc "Renders the second-factor challenge page."
  def new(conn, _params) do
    user = conn.assigns.pending_user
    challenge = Passkeys.authentication_challenge(user)

    credential_ids =
      user
      |> Passkeys.list_user_keys()
      |> Enum.map(&Base.url_encode64(&1.credential_id, padding: false))

    conn
    |> put_session(:wax_auth_challenge, challenge)
    |> render(:new,
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      rp_id: challenge.rp_id,
      credential_ids: credential_ids,
      recovery_count: RecoveryCodes.count_unused(user)
    )
  end

  @doc "Verifies a passkey assertion returned by the browser."
  def create(conn, %{"assertion" => assertion}) do
    user = conn.assigns.pending_user
    challenge = get_session(conn, :wax_auth_challenge)

    with %Wax.Challenge{} <- challenge,
         {:ok, credential_id} <- decode(assertion["credential_id"]),
         {:ok, auth_data} <- decode(assertion["authenticator_data"]),
         {:ok, signature} <- decode(assertion["signature"]),
         {:ok, client_data} <- decode(assertion["client_data_json"]),
         {:ok, _key} <-
           Passkeys.verify(user, credential_id, auth_data, signature, client_data, challenge) do
      complete_login(conn, user)
    else
      _ ->
        conn
        |> put_flash(:error, "We couldn't verify that passkey. Please try again.")
        |> redirect(to: ~p"/users/two-factor")
    end
  end

  @doc "Verifies a recovery code as an alternative second factor."
  def recovery(conn, %{"recovery" => %{"code" => code}}) do
    user = conn.assigns.pending_user

    case RecoveryCodes.verify_and_consume(user, code) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Recovery code accepted. Consider regenerating your codes.")
        |> complete_login(user)

      :error ->
        conn
        |> put_flash(:error, "That recovery code is invalid or has already been used.")
        |> redirect(to: ~p"/users/two-factor")
    end
  end

  defp complete_login(conn, user) do
    remember_me = get_session(conn, :pending_2fa_remember_me)
    params = if remember_me, do: %{"remember_me" => "true"}, else: %{}

    conn
    |> delete_session(:pending_2fa_user_id)
    |> delete_session(:pending_2fa_remember_me)
    |> delete_session(:pending_2fa_at)
    |> delete_session(:wax_auth_challenge)
    |> UserAuth.log_in_user(user, params)
  end

  # Ensures a valid, unexpired pending-login marker exists and loads that user.
  defp require_pending_user(conn, _opts) do
    with id when is_binary(id) <- get_session(conn, :pending_2fa_user_id),
         at when is_integer(at) <- get_session(conn, :pending_2fa_at),
         true <- System.system_time(:second) - at <= @pending_ttl_seconds,
         %Accounts.User{} = user <- Accounts.get_user(id) do
      assign(conn, :pending_user, user)
    else
      _ ->
        conn
        |> put_flash(:error, "Your login attempt expired. Please sign in again.")
        |> redirect(to: ~p"/users/log-in")
        |> halt()
    end
  end

  defp decode(str) when is_binary(str), do: Base.url_decode64(str, padding: false)
  defp decode(_), do: :error
end
