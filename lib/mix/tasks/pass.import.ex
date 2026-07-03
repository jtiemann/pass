defmodule Mix.Tasks.Pass.Import do
  @shortdoc "Imports a vault export produced by mix pass.export"

  @moduledoc """
  Restores a vault from the JSON that `mix pass.export` produces:

      mix pass.import vault-export.json

  - Runs atomically — if any record is invalid, nothing is imported.
  - Assets whose name already exists are skipped, so re-running is safe.
  - Credential secrets and notes are re-encrypted on insert.
  - Documents are listed in exports as metadata only, so their file contents
    are NOT restored here — restore those from a database backup (BACKUP.md).
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run([path]) do
    Logger.configure(level: :warning)

    data =
      case path |> File.read!() |> Jason.decode() do
        {:ok, data} -> data
        {:error, _} -> Mix.raise("#{path} is not valid JSON.")
      end

    case Pass.Vault.import_data(data) do
      {:ok, summary} ->
        Pass.Audit.log(nil, "vault.imported",
          summary: "#{summary.imported} assets from #{Path.basename(path)}"
        )

        IO.puts("""
        Import complete.
          Assets imported:      #{summary.imported}
          Credentials imported: #{summary.credentials}
          Contacts imported:    #{summary.contacts}
          Skipped (name already exists): #{format_skipped(summary.skipped)}
          Documents not restored (metadata only in exports): #{summary.documents_skipped}
        """)

        if summary.documents_skipped > 0 do
          IO.puts(
            :stderr,
            "Reminder: restore document files from a database backup (see BACKUP.md)."
          )
        end

      {:error, {:invalid_record, asset_name, changeset}} ->
        Mix.raise("""
        Import aborted — nothing was changed.
        A record under asset "#{asset_name}" is invalid: #{inspect(changeset.errors)}
        """)

      {:error, :invalid_format} ->
        Mix.raise("That file doesn't look like a pass export (missing \"assets\" list).")
    end
  end

  def run(_args) do
    Mix.raise("Usage: mix pass.import path/to/vault-export.json")
  end

  defp format_skipped([]), do: "0"
  defp format_skipped(names), do: "#{length(names)} (#{Enum.join(names, ", ")})"
end
