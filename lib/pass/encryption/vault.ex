defmodule Pass.Encryption.Vault do
  @moduledoc """
  Cloak vault used to encrypt sensitive fields (credential secrets, notes) at rest.

  The encryption key is supplied via configuration — a real, secret key in prod
  (from `PASS_CLOAK_KEY`), and a dev-only default otherwise. See `config/*.exs`.
  """
  use Cloak.Vault, otp_app: :pass
end
