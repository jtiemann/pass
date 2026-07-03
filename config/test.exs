import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :pbkdf2_elixir, :rounds, 1

# WebAuthn / passkeys config for tests
config :wax_,
  origin: "http://localhost:4000",
  rp_id: "localhost"

# Encryption at rest (Cloak) — fixed test key.
config :pass, Pass.Encryption.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1", key: Base.decode64!("SnnlI94TTRVzlJCBKEzbmwylfVJT8rfkOo1kXFmKNf0=")}
  ]

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
db_password = System.get_env("PASS_DB_PASSWORD", "postgres")

config :pass, Pass.Repo,
  username: "postgres",
  password: db_password,
  hostname: "localhost",
  database: "pass_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :pass, PassWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "dLJF1MY04kNueQPdOL56zBmNqUKEyb8SdiQb10AYE5d061K9ohNcv8jrE853jWTM",
  server: false

# In test we don't send emails
config :pass, Pass.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
