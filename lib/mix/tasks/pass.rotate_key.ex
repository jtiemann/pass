defmodule Mix.Tasks.Pass.RotateKey do
  @shortdoc "Re-encrypts all vault secrets under the current default Cloak key"

  @moduledoc """
  Rewrites every encrypted column (credential secrets/notes, document contents)
  so they are encrypted with the vault's current **default** cipher.

  Use after changing encryption keys — e.g. after setting your own
  `PASS_CLOAK_KEY` in dev (the old key stays registered as a retired cipher so
  this task can still read the old rows). Safe to run repeatedly.
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    Logger.configure(level: :warning)

    alias Pass.Repo
    alias Pass.Vault.{Credential, Document}
    import Ecto.Changeset, only: [change: 1, force_change: 3]

    credentials =
      for credential <- Repo.all(Credential) do
        credential
        |> change()
        |> force_change(:secret, credential.secret)
        |> force_change(:notes, credential.notes)
        |> Repo.update!()
      end

    documents =
      for document <- Repo.all(Document) do
        document
        |> change()
        |> force_change(:data, document.data)
        |> Repo.update!()
      end

    IO.puts(
      "Re-encrypted #{length(credentials)} credential(s) and #{length(documents)} document(s)."
    )
  end
end
