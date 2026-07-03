defmodule Pass.Accounts.RecoveryCodes do
  @moduledoc """
  Single-use recovery codes: generation, listing, and verification.

  Codes are shown to the user grouped with dashes (e.g. `a1b2-c3d4-e5f6-g7h8`)
  but hashed and compared in a normalized, dash-free, lowercase form.
  """
  import Ecto.Query, warn: false

  alias Pass.Repo
  alias Pass.Accounts.{User, RecoveryCode}

  @count 10
  @bytes 10

  @doc """
  Replaces any existing recovery codes with a fresh batch and returns the
  plaintext codes (the only time they are ever visible).
  """
  def generate(%User{id: user_id}) do
    Repo.delete_all(from r in RecoveryCode, where: r.user_id == ^user_id)

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    codes = for _ <- 1..@count, do: new_code()

    entries =
      Enum.map(codes, fn code ->
        %{
          id: Ecto.UUID.generate(),
          user_id: user_id,
          hashed_code: Pbkdf2.hash_pwd_salt(normalize(code)),
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(RecoveryCode, entries)
    codes
  end

  @doc "Number of unused recovery codes remaining."
  def count_unused(%User{id: user_id}) do
    Repo.aggregate(
      from(r in RecoveryCode, where: r.user_id == ^user_id and is_nil(r.used_at)),
      :count
    )
  end

  @doc """
  Verifies a recovery code and consumes it (marks it used). Returns `{:ok, user}`
  on success or `:error` otherwise. Runs a dummy hash on miss to avoid timing
  leaks.
  """
  def verify_and_consume(%User{id: user_id} = user, code) when is_binary(code) do
    normalized = normalize(code)

    unused =
      Repo.all(from r in RecoveryCode, where: r.user_id == ^user_id and is_nil(r.used_at))

    case Enum.find(unused, &Pbkdf2.verify_pass(normalized, &1.hashed_code)) do
      nil ->
        Pbkdf2.no_user_verify()
        :error

      %RecoveryCode{} = rc ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        {:ok, _} = rc |> Ecto.Changeset.change(used_at: now) |> Repo.update()
        {:ok, user}
    end
  end

  # A 16-char base32 code, displayed in four dash-separated groups.
  defp new_code do
    :crypto.strong_rand_bytes(@bytes)
    |> Base.encode32(padding: false)
    |> binary_part(0, 16)
    |> String.downcase()
    |> String.replace(~r/(.{4})(?=.)/, "\\1-")
  end

  defp normalize(code) do
    code
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]/, "")
  end
end
