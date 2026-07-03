defmodule PassWeb.PasskeyController do
  @moduledoc """
  Passkey and recovery-code management for the signed-in user.

  Enrollment is a two-step ceremony: the browser fetches creation options from
  `challenge/2` (which stashes a registration challenge in the session), runs
  `navigator.credentials.create()`, then POSTs the result to `create/2`.
  """
  use PassWeb, :controller

  alias Pass.Accounts.{Passkeys, RecoveryCodes}

  @doc "Lists the user's passkeys and recovery-code status."
  def index(conn, _params) do
    user = conn.assigns.current_scope.user

    render(conn, :index,
      keys: Passkeys.list_user_keys(user),
      recovery_count: RecoveryCodes.count_unused(user)
    )
  end

  @doc "Returns WebAuthn credential-creation options as JSON."
  def challenge(conn, _params) do
    user = conn.assigns.current_scope.user
    challenge = Passkeys.registration_challenge()

    exclude =
      user
      |> Passkeys.exclude_credentials()
      |> Enum.map(&%{type: "public-key", id: Base.url_encode64(&1, padding: false)})

    conn
    |> put_session(:wax_reg_challenge, challenge)
    |> json(%{
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      rp: %{id: challenge.rp_id, name: "pass"},
      user: %{
        id: Base.url_encode64(user.id, padding: false),
        name: user.email,
        displayName: user.email
      },
      pubKeyCredParams: [
        %{type: "public-key", alg: -7},
        %{type: "public-key", alg: -257}
      ],
      excludeCredentials: exclude,
      authenticatorSelection: %{residentKey: "preferred", userVerification: "preferred"},
      attestation: "none",
      timeout: 60_000
    })
  end

  @doc "Verifies and stores a newly created passkey."
  def create(conn, %{"passkey" => params}) do
    user = conn.assigns.current_scope.user
    challenge = get_session(conn, :wax_reg_challenge)
    label = params["label"] |> to_string() |> String.trim()
    label = if label == "", do: "Passkey", else: label

    with %Wax.Challenge{} <- challenge,
         {:ok, attestation_object} <- decode(params["attestation_object"]),
         {:ok, client_data} <- decode(params["client_data_json"]),
         {:ok, _key} <-
           Passkeys.register_key(user, label, attestation_object, client_data, challenge) do
      conn
      |> delete_session(:wax_reg_challenge)
      |> put_flash(:info, recovery_hint("Passkey added.", user))
      |> redirect(to: ~p"/users/passkeys")
    else
      _ ->
        conn
        |> put_flash(:error, "We couldn't register that passkey. Please try again.")
        |> redirect(to: ~p"/users/passkeys")
    end
  end

  @doc "Removes a passkey."
  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_scope.user

    case Passkeys.delete_user_key(user, id) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Passkey removed.")
        |> redirect(to: ~p"/users/passkeys")

      {:error, _} ->
        conn
        |> put_flash(:error, "That passkey could not be found.")
        |> redirect(to: ~p"/users/passkeys")
    end
  end

  @doc "Generates a fresh batch of recovery codes and shows them once."
  def recovery_codes(conn, _params) do
    user = conn.assigns.current_scope.user
    codes = RecoveryCodes.generate(user)
    render(conn, :recovery_codes, codes: codes)
  end

  defp recovery_hint(msg, user) do
    if RecoveryCodes.count_unused(user) == 0 do
      msg <> " Generate recovery codes so you can still log in if you lose it."
    else
      msg
    end
  end

  defp decode(str) when is_binary(str), do: Base.url_decode64(str, padding: false)
  defp decode(_), do: :error
end
