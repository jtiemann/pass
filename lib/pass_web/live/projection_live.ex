defmodule PassWeb.ProjectionLive do
  @moduledoc """
  "What will my total gains be after N years?" — projects the vault forward
  using each asset's growth assumptions (or its category's historical default).
  """
  use PassWeb, :live_view

  alias Pass.Vault
  alias Pass.Vault.{Asset, Projection}
  alias PassWeb.Format

  @quick_horizons [1, 5, 10, 20, 30]
  @default_years 5

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Projections
        <:subtitle>
          Estimated growth based on the assumptions on each asset — not financial advice.
        </:subtitle>
      </.header>

      <div class="flex flex-wrap items-center gap-2">
        <span class="text-sm text-base-content/70">Horizon:</span>
        <button
          :for={horizon <- quick_horizons()}
          type="button"
          class={["btn btn-sm", horizon == @years && "btn-primary"]}
          phx-click="set_years"
          phx-value-years={horizon}
        >
          {horizon}y
        </button>
        <form id="horizon-form" phx-change="set_years" class="inline-flex items-center gap-2">
          <input
            type="number"
            name="years"
            min="1"
            max="50"
            value={@years}
            class="input input-bordered input-sm w-20"
            aria-label="Years"
          />
          <span class="text-sm text-base-content/70">years</span>
        </form>
      </div>

      <div
        :if={@projection.totals == []}
        class="mt-8 rounded-box border border-base-300 p-8 text-center"
      >
        <p class="text-base-content/70">
          No assets have an estimated value yet — add values (and growth assumptions)
          to your assets to project them forward.
        </p>
      </div>

      <div :for={{currency, totals} <- @projection.totals} class="mt-6">
        <h2 class="text-lg font-semibold mb-3">{currency}</h2>
        <div class={[
          "grid grid-cols-1 gap-4",
          (totals.drawn > 0 && "sm:grid-cols-2 lg:grid-cols-4") || "sm:grid-cols-3"
        ]}>
          <.stat label="Today" value={money(totals.current, currency)} />
          <.stat label={"In #{@years} #{year_word(@years)}"} value={money(totals.total, currency)} />
          <.stat
            :if={totals.drawn > 0}
            label="Drawn for expenses"
            value={money(totals.drawn, currency)}
          />
          <.stat label="Total gain" value={money(totals.gain, currency)} tone={tone(totals.gain)} />
        </div>

        <div
          :if={totals.unfunded > 0.005}
          class="mt-3 rounded-box border border-error/40 bg-error/5 p-3 text-sm text-error"
        >
          <.icon name="hero-exclamation-triangle" class="size-4 inline align-text-bottom" />
          {money(totals.unfunded, currency)} of planned draws can't be funded over this horizon
          (first gap in year {totals.first_gap_year}). Choose below where depleted draws
          should continue from.
        </div>
      </div>

      <section :if={@prompts != []} class="mt-8 space-y-4">
        <h2 class="text-lg font-semibold">Keep the money flowing</h2>
        <div
          :for={prompt <- @prompts}
          class="rounded-box border border-warning/50 bg-warning/5 p-4 space-y-3"
        >
          <p class="text-sm">
            <span class="font-semibold">{prompt.asset.name}</span>
            runs out in year {prompt.depleted_at}. Continue its
            <span class="font-semibold">
              {Format.money(prompt.asset.annual_draw, "#{prompt.asset.currency} ")}/yr
            </span>
            draw from:
          </p>

          <form
            :if={prompt.targets != []}
            id={"realloc-#{prompt.asset.id}"}
            phx-change="set_allocation"
            class="space-y-2"
          >
            <input type="hidden" name="source" value={prompt.asset.id} />
            <div
              :for={target <- prompt.targets}
              class="flex items-center justify-between gap-3 text-sm"
            >
              <span class="min-w-0 truncate">{target.name}</span>
              <span class="flex items-center gap-1 flex-none">
                <input
                  type="number"
                  name={"pct[#{target.id}]"}
                  value={allocation_pct(@reallocations, prompt.asset.id, target.id)}
                  min="0"
                  max="100"
                  step="1"
                  class="input input-bordered input-sm w-20 text-right"
                /> %
              </span>
            </div>
          </form>

          <div class="flex items-center gap-3">
            <button
              :if={prompt.targets != []}
              type="button"
              class="btn btn-sm"
              phx-click="split_evenly"
              phx-value-source={prompt.asset.id}
            >
              Split evenly
            </button>
            <button
              :if={allocated_total(@reallocations, prompt.asset.id) > 0}
              type="button"
              class="btn btn-sm btn-ghost"
              phx-click="clear_allocation"
              phx-value-source={prompt.asset.id}
            >
              Clear
            </button>
            <span class="text-xs text-base-content/60">
              {allocation_note(@reallocations, prompt.asset.id)}
            </span>
          </div>

          <p :if={prompt.targets == []} class="text-sm text-base-content/70">
            No other {prompt.asset.currency} assets to draw from.
          </p>
        </div>
      </section>

      <section :if={@projection.rows != []} class="mt-8 space-y-3">
        <h2 class="text-lg font-semibold">Per asset</h2>
        <div class="overflow-x-auto rounded-box border border-base-300">
          <table class="table table-zebra">
            <thead>
              <tr>
                <th>Asset</th>
                <th>Today</th>
                <th>Return</th>
                <th>Yield</th>
                <th>Draw / yr</th>
                <th>In {@years}y</th>
                <th>Gain</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @projection.rows}>
                <td>
                  <.link navigate={~p"/assets/#{row.asset}"} class="font-medium hover:underline">
                    {row.asset.name}
                  </.link>
                  <div class="text-xs text-base-content/60">
                    {Asset.humanize_category(row.asset.category)}
                  </div>
                </td>
                <td>{money(row.current, row.asset.currency)}</td>
                <td>
                  {format_pct(row.return_pct)}
                  <span :if={row.assumed?} class="badge badge-ghost badge-xs align-middle ml-1">
                    assumed
                  </span>
                </td>
                <td>
                  <span :if={row.yield_pct > 0}>
                    {format_pct(row.yield_pct)}
                    <span class="text-xs text-base-content/60">
                      {if row.asset.dividends_reinvested, do: "reinvested", else: "as cash"}
                    </span>
                  </span>
                  <span :if={row.yield_pct == 0.0}>—</span>
                </td>
                <td>
                  <span :if={draw?(row.asset)}>
                    {Format.money(row.asset.annual_draw, "#{row.asset.currency} ")}
                  </span>
                  <span :if={!draw?(row.asset)}>—</span>
                </td>
                <td>
                  {money(row.total, row.asset.currency)}
                  <div :if={row.depleted_at} class="text-xs text-error">
                    depletes in year {row.depleted_at}
                  </div>
                </td>
                <td class={tone_class(row.gain)}>{signed_money(row.gain, row.asset.currency)}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <p :if={@projection.excluded > 0} class="text-xs text-base-content/60">
          {@projection.excluded} asset(s) without an estimated value are not included.
        </p>
        <p class="text-xs text-base-content/60">
          “Assumed” returns use rough historical category averages — set your own rates
          on each asset for projections you actually trust. Dividends marked “as cash”
          accumulate uninvested alongside the asset.
        </p>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :tone, :string, default: nil

  defp stat(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300 bg-base-200/40 p-5">
      <div class="text-sm text-base-content/60">{@label}</div>
      <div class={["font-display text-2xl font-semibold tracking-tight mt-1", @tone]}>
        {@value}
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Projections")
     |> assign(:years, @default_years)
     |> assign(:reallocations, %{})
     |> project()}
  end

  @impl true
  def handle_event("set_years", %{"years" => years}, socket) do
    years =
      case Integer.parse(to_string(years)) do
        {n, _} -> n |> max(1) |> min(50)
        :error -> @default_years
      end

    {:noreply, socket |> assign(:years, years) |> project()}
  end

  def handle_event("set_allocation", %{"source" => source_id, "pct" => pcts}, socket) do
    allocation =
      for {target_id, value} <- pcts,
          pct = parse_pct(value),
          pct > 0,
          into: %{},
          do: {target_id, pct}

    {:noreply,
     socket
     |> update(:reallocations, &Map.put(&1, source_id, allocation))
     |> project()}
  end

  def handle_event("split_evenly", %{"source" => source_id}, socket) do
    targets = targets_for(socket.assigns.assets, source_id)

    allocation =
      case targets do
        [] -> %{}
        list -> Map.new(list, &{&1.id, Float.round(100.0 / length(list), 1)})
      end

    {:noreply,
     socket
     |> update(:reallocations, &Map.put(&1, source_id, allocation))
     |> project()}
  end

  def handle_event("clear_allocation", %{"source" => source_id}, socket) do
    {:noreply,
     socket
     |> update(:reallocations, &Map.delete(&1, source_id))
     |> project()}
  end

  defp project(socket) do
    assets = Vault.list_assets()

    projection =
      Projection.project_assets(
        assets,
        socket.assigns.years,
        fractions(socket.assigns.reallocations)
      )

    prompts =
      projection.rows
      |> Enum.filter(fn row ->
        draw?(row.asset) and row.depleted_at != nil and row.depleted_at < socket.assigns.years
      end)
      |> Enum.map(fn row ->
        %{
          asset: row.asset,
          depleted_at: row.depleted_at,
          targets: targets_for(assets, row.asset.id, row.asset.currency)
        }
      end)

    socket
    |> assign(:assets, assets)
    |> assign(:projection, projection)
    |> assign(:prompts, prompts)
  end

  # UI percentages (0..100) -> fractions (0..1), scaled down if they exceed 100%.
  defp fractions(reallocations) do
    Map.new(reallocations, fn {source_id, allocation} ->
      total = allocation |> Map.values() |> Enum.sum()
      scale = if total > 100.0, do: total, else: 100.0
      {source_id, Map.new(allocation, fn {target_id, pct} -> {target_id, pct / scale} end)}
    end)
  end

  defp targets_for(assets, source_id, currency \\ nil) do
    currency =
      currency ||
        case Enum.find(assets, &(&1.id == source_id)) do
          nil -> nil
          asset -> asset.currency
        end

    Enum.filter(assets, fn asset ->
      asset.id != source_id and asset.currency == currency and asset.estimated_value != nil
    end)
  end

  defp allocation_pct(reallocations, source_id, target_id) do
    case get_in(reallocations, [source_id, target_id]) do
      nil -> nil
      pct -> format_pct_number(pct)
    end
  end

  defp allocated_total(reallocations, source_id) do
    reallocations |> Map.get(source_id, %{}) |> Map.values() |> Enum.sum()
  end

  defp allocation_note(reallocations, source_id) do
    case allocated_total(reallocations, source_id) do
      total when total <= 0 ->
        "Unallocated — its draw simply stops when it runs out."

      total when total < 100.0 ->
        "#{format_pct_number(total)}% allocated — the rest goes unfunded."

      total when total > 100.0 ->
        "Over 100% — shares are scaled down proportionally."

      _ ->
        "Fully allocated."
    end
  end

  defp format_pct_number(pct) do
    if pct == trunc(pct), do: trunc(pct), else: Float.round(pct, 1)
  end

  defp quick_horizons, do: @quick_horizons

  defp draw?(asset) do
    asset.annual_draw != nil and Decimal.compare(asset.annual_draw, 0) == :gt
  end

  defp parse_pct(value) do
    case Float.parse(to_string(value)) do
      {pct, _} -> pct |> max(0.0) |> min(100.0)
      :error -> 0.0
    end
  end

  defp year_word(1), do: "year"
  defp year_word(_years), do: "years"

  defp money(float, currency), do: Format.money(Projection.to_money(float), "#{currency} ")

  defp signed_money(float, currency) do
    prefix = if float >= 0, do: "+", else: ""
    prefix <> money(float, currency)
  end

  defp format_pct(pct) do
    number = if pct == trunc(pct), do: trunc(pct), else: Float.round(pct, 1)
    "#{number}%"
  end

  defp tone(gain) when gain < 0, do: "text-error"
  defp tone(_gain), do: "text-success"

  defp tone_class(gain) when gain < 0, do: "text-error"
  defp tone_class(_gain), do: "text-success"
end
