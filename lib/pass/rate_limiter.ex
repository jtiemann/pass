defmodule Pass.RateLimiter do
  @moduledoc """
  A small fixed-window rate limiter backed by ETS.

  `check/3` counts hits for a key within the current window and returns
  `:ok` while under the limit, `{:error, :rate_limited}` once over it.
  Windows are bucketed by wall-clock time; expired buckets are swept
  periodically.
  """
  use GenServer

  @table __MODULE__
  @sweep_interval_ms 300_000

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a hit for `key` and checks it against `limit` hits per
  `window_seconds`. Returns `:ok` or `{:error, :rate_limited}`.
  """
  def check(key, limit, window_seconds)
      when is_integer(limit) and limit > 0 and is_integer(window_seconds) and window_seconds > 0 do
    now = System.system_time(:second)
    bucket = div(now, window_seconds)
    ets_key = {key, bucket}
    expires_at = (bucket + 1) * window_seconds

    count = :ets.update_counter(@table, ets_key, {2, 1}, {ets_key, 0, expires_at})

    if count <= limit, do: :ok, else: {:error, :rate_limited}
  end

  @doc "Clears all counters (used by tests)."
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

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
