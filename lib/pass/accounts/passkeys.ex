defmodule Pass.Accounts.Passkeys do
  @moduledoc """
  WebAuthn passkey registration and authentication.

  Wraps the `Wax` library. Challenges are `%Wax.Challenge{}` structs that the
  caller is expected to stash in the session between the two halves of each
  ceremony (challenge creation -> browser -> verification).
  """
  import Ecto.Query, warn: false

  alias Pass.Repo
  alias Pass.Accounts.{User, UserKey}

  @doc "Lists a user's registered passkeys, newest first."
  def list_user_keys(%User{id: user_id}) do
    Repo.all(from k in UserKey, where: k.user_id == ^user_id, order_by: [desc: k.inserted_at])
  end

  @doc "Whether the user has at least one passkey enrolled."
  def has_passkey?(%User{id: user_id}) do
    Repo.exists?(from k in UserKey, where: k.user_id == ^user_id)
  end

  @doc "Fetches one of the user's passkeys by id, or nil."
  def get_user_key(%User{id: user_id}, id) do
    Repo.get_by(UserKey, id: id, user_id: user_id)
  end

  @doc "Deletes one of the user's passkeys."
  def delete_user_key(%User{} = user, id) do
    case get_user_key(user, id) do
      nil -> {:error, :not_found}
      key -> Repo.delete(key)
    end
  end

  ## Registration ceremony

  @doc """
  Builds a registration challenge. Pair with `register_key/5`, passing the same
  challenge back. `attestation: "none"` keeps things simple and private.
  """
  def registration_challenge do
    Wax.new_registration_challenge(attestation: "none")
  end

  @doc """
  Credential ids to send as `excludeCredentials` so a user can't enroll the same
  authenticator twice.
  """
  def exclude_credentials(%User{} = user) do
    for k <- list_user_keys(user), do: k.credential_id
  end

  @doc """
  Verifies the browser's `navigator.credentials.create()` response and stores the
  new credential. `attestation_object` and `client_data_json` must be the raw
  (already base64-decoded) binaries.
  """
  def register_key(%User{} = user, label, attestation_object, client_data_json, challenge) do
    with {:ok, {auth_data, _attestation_result}} <-
           Wax.register(attestation_object, client_data_json, challenge) do
      acd = auth_data.attested_credential_data

      %UserKey{user_id: user.id}
      |> UserKey.registration_changeset(%{
        label: label,
        credential_id: acd.credential_id,
        public_key: :erlang.term_to_binary(acd.credential_public_key),
        aaguid: acd.aaguid,
        sign_count: auth_data.sign_count
      })
      |> Repo.insert()
    end
  end

  ## Authentication ceremony

  @doc """
  Builds an authentication challenge restricted to the user's own credentials.
  Pair with `verify/6`, passing the same challenge back.
  """
  def authentication_challenge(%User{} = user) do
    allow = for k <- list_user_keys(user), do: {k.credential_id, UserKey.cose_key(k)}
    Wax.new_authentication_challenge(allow_credentials: allow)
  end

  @doc """
  Verifies a `navigator.credentials.get()` assertion. All binary args must be the
  raw (already base64-decoded) values. On success, bumps the credential's
  signature counter and `last_used_at`.
  """
  def verify(%User{} = user, credential_id, auth_data_bin, sig, client_data_json, challenge) do
    with {:ok, auth_data} <-
           Wax.authenticate(credential_id, auth_data_bin, sig, client_data_json, challenge),
         %UserKey{} = key <- get_user_key_by_credential_id(user, credential_id),
         :ok <- check_sign_count(auth_data.sign_count, key.sign_count) do
      key
      |> UserKey.usage_changeset(%{
        sign_count: auth_data.sign_count,
        last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update()
    else
      nil -> {:error, :unknown_credential}
      {:error, _} = error -> error
    end
  end

  @doc """
  WebAuthn clone detection (assertion verification step 17): a signature
  counter that goes backwards or repeats means two authenticators share the
  same credential — reject. Counters stuck at zero are allowed, since many
  platform authenticators (passkeys synced via iCloud/Google) never increment.
  """
  def check_sign_count(new_count, _stored) when new_count == 0, do: :ok
  def check_sign_count(new_count, stored) when new_count > stored, do: :ok
  def check_sign_count(_new_count, _stored), do: {:error, :possible_credential_clone}

  defp get_user_key_by_credential_id(%User{id: user_id}, credential_id) do
    Repo.get_by(UserKey, user_id: user_id, credential_id: credential_id)
  end
end
