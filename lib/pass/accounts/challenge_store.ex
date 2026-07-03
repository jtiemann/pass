defmodule Pass.Accounts.ChallengeStore do
  @moduledoc """
  Server-side storage for in-flight WebAuthn challenges.

  Challenges (especially authentication challenges, which carry every enrolled
  credential's public key) can outgrow the 4KB session cookie once a family has
  several passkeys. Instead of putting the challenge in the cookie, we keep it
  here and put only a short random reference in the session.

  Entries are take-once and expire after #{div(600, 60)} minutes; a sweeper
  clears anything left behind.
  """
  use GenServer

  @table __MODULE__
  @ttl_seconds 600
  @sweep_interval_ms 60_000

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Stores a challenge and returns an opaque reference for the session."
  def put(challenge, ttl_seconds \\ @ttl_seconds) do
    ref = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    expires_at = System.system_time(:second) + ttl_seconds
    :ets.insert(@table, {ref, challenge, expires_at})
    ref
  end

  @doc """
  Retrieves and deletes the challenge for `ref`. Returns `:error` if the ref is
  unknown, already used, or expired — a challenge can only be consumed once.
  """
  def take(ref) when is_binary(ref) do
    case :ets.take(@table, ref) do
      [{^ref, challenge, expires_at}] ->
        if System.system_time(:second) <= expires_at do
          {:ok, challenge}
        else
          :error
        end

      [] ->
        :error
    end
  end

  def take(_ref), do: :error

  ## Server

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.system_time(:second)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval_ms)
end
