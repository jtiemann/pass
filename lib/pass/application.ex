defmodule Pass.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PassWeb.Telemetry,
      Pass.Repo,
      Pass.Encryption.Vault,
      Pass.Accounts.ChallengeStore,
      Pass.RateLimiter,
      {DNSCluster, query: Application.get_env(:pass, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Pass.PubSub},
      # Start a worker by calling: Pass.Worker.start_link(arg)
      # {Pass.Worker, arg},
      # Start to serve requests, typically the last entry
      PassWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pass.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PassWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
