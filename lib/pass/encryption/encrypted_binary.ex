defmodule Pass.Encryption.EncryptedBinary do
  @moduledoc "Ecto type for a value encrypted at rest via `Pass.Encryption.Vault`."
  use Cloak.Ecto.Binary, vault: Pass.Encryption.Vault
end
