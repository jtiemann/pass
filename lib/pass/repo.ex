defmodule Pass.Repo do
  use Ecto.Repo,
    otp_app: :pass,
    adapter: Ecto.Adapters.Postgres
end
