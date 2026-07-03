defmodule Mix.Tasks.Pass.Export do
  @shortdoc "Prints a decrypted JSON export of the vault (emergency kit)"

  @moduledoc """
  Prints the entire vault — assets, access instructions, DECRYPTED credentials,
  contacts, and document metadata — as JSON on stdout.

      mix pass.export > vault-export.json

  Intended for the family "emergency kit": print or store the output somewhere
  physically secure (a safe, a bank deposit box, with your attorney). The output
  contains every secret in plaintext, so never leave it lying around, and never
  commit it anywhere.

  Document *contents* are not included; restore those from a database backup
  (see BACKUP.md).
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    # Keep stdout pure JSON so `mix pass.export > file.json` works.
    Logger.configure(level: :warning)

    IO.puts(:stderr, "WARNING: this export contains every secret in the vault, decrypted.")
    IO.puts(:stderr, "Store it somewhere physically secure and delete stray copies.\n")

    IO.puts(Jason.encode!(Pass.Vault.export(), pretty: true))
  end
end
