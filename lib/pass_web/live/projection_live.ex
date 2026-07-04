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

      <section :if={@charts != []} class="mt-8 space-y-6">
        <div :for={{currency, series} <- @charts}>
          <h2 class="text-lg font-semibold mb-2">
            Value over {@chart_years} years
            <span :if={length(@charts) > 1} class="text-base-content/60">({currency})</span>
          </h2>
          <div class="rounded-box border border-base-300 bg-base-200/30 p-4">
            <.value_chart series={series} currency={currency} years={@chart_years} />
          </div>
        </div>
      </section>

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
                <td>
                  {money(row.current, row.asset.currency)}
                  <div :if={row.loan_balance_start > 0} class="text-xs text-base-content/60">
                    equity after {money(row.loan_balance_start, row.asset.currency)} loan
                  </div>
                  <div
                    :if={row.asset.rent_monthly || row.asset.hoa_monthly}
                    class="text-xs text-base-content/60"
                  >
                    <span :if={row.asset.rent_monthly}>
                      rent {Format.money(row.asset.rent_monthly, "")}/mo
                    </span>
                    <span :if={row.asset.hoa_monthly}>
                      · HOA {Format.money(row.asset.hoa_monthly, "")}/mo
                    </span>
                  </div>
                </td>
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
                  <div :if={row.loan_paid_off_at} class="text-xs text-success">
                    loan paid off in year {row.loan_paid_off_at}
                  </div>
                  <div :if={row.loan_balance_end > 0.005} class="text-xs text-base-content/60">
                    {money(row.loan_balance_end, row.asset.currency)} loan remaining
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

  # Chart canvas: fixed viewBox, scaled by CSS. Kept as plain SVG so it themes
  # itself through the CSS variables and needs no JS.
  @chart_w 720
  @chart_h 260
  @pad_l 64
  @pad_r 14
  @pad_t 14
  @pad_b 28

  attr :series, :list, required: true
  attr :currency, :string, required: true
  attr :years, :integer, required: true

  defp value_chart(assigns) do
    assigns = assign(assigns, :geometry, chart_geometry(assigns.series))

    ~H"""
    <svg
      viewBox={"0 0 #{@geometry.w} #{@geometry.h}"}
      class="w-full"
      role="img"
      aria-label={"Projected #{@currency} value over #{@years} years"}
    >
      <%!-- horizontal gridlines + y labels --%>
      <g :for={{label, y} <- @geometry.y_ticks}>
        <line
          x1={@geometry.pad_l}
          y1={y}
          x2={@geometry.w - @geometry.pad_r}
          y2={y}
          stroke="var(--color-base-300)"
          stroke-width="1"
        />
        <text
          x={@geometry.pad_l - 8}
          y={y + 4}
          text-anchor="end"
          font-size="12"
          fill="var(--color-base-content)"
          opacity="0.6"
        >
          {label}
        </text>
      </g>

      <%!-- x labels --%>
      <text
        :for={{label, x} <- @geometry.x_ticks}
        x={x}
        y={@geometry.h - 8}
        text-anchor="middle"
        font-size="12"
        fill="var(--color-base-content)"
        opacity="0.6"
      >
        {label}
      </text>

      <polygon points={@geometry.area} fill="var(--color-primary)" fill-opacity="0.12" />
      <polyline
        points={@geometry.line}
        fill="none"
        stroke="var(--color-primary)"
        stroke-width="2.5"
        stroke-linejoin="round"
      />

      <circle
        :for={{x, y, year, value} <- @geometry.points}
        cx={x}
        cy={y}
        r="3.5"
        fill="var(--color-primary)"
      >
        <title>Year {year}: {money(value, @currency)}</title>
      </circle>
    </svg>
    """
  end

  defp chart_geometry(series) do
    count = length(series)
    plot_w = @chart_w - @pad_l - @pad_r
    plot_h = @chart_h - @pad_t - @pad_b
    dims = %{w: @chart_w, h: @chart_h, pad_l: @pad_l, pad_r: @pad_r}

    y_min = min(0.0, Enum.min(series))
    y_max = max(Enum.max(series) * 1.05, y_min + 1.0)
    x_step = plot_w / max(count - 1, 1)

    scale_y = fn value -> @pad_t + plot_h * (1 - (value - y_min) / (y_max - y_min)) end

    points =
      series
      |> Enum.with_index()
      |> Enum.map(fn {value, year} ->
        {Float.round(@pad_l + year * x_step, 1), Float.round(scale_y.(value), 1), year, value}
      end)

    line = Enum.map_join(points, " ", fn {x, y, _year, _value} -> "#{x},#{y}" end)

    baseline_y = Float.round(scale_y.(max(y_min, 0.0)), 1)
    {first_x, _, _, _} = List.first(points)
    {last_x, _, _, _} = List.last(points)
    area = "#{first_x},#{baseline_y} #{line} #{last_x},#{baseline_y}"

    y_ticks =
      for step <- 0..4 do
        value = y_min + (y_max - y_min) * step / 4
        {compact_number(value), Float.round(scale_y.(value), 1)}
      end

    label_every = max(div(count - 1, 5), 1)

    x_ticks =
      for {x, _y, year, _value} <- points,
          rem(year, label_every) == 0 or year == count - 1,
          do: {"#{year}y", x}

    Map.merge(dims, %{points: points, line: line, area: area, y_ticks: y_ticks, x_ticks: x_ticks})
  end

  defp compact_number(value) do
    sign = if value < 0, do: "-", else: ""
    abs = abs(value)

    cond do
      abs >= 1_000_000 -> "#{sign}#{Float.round(abs / 1_000_000, 1)}M"
      abs >= 1_000 -> "#{sign}#{round(abs / 1_000)}k"
      true -> "#{sign}#{round(abs)}"
    end
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
    allocations = fractions(socket.assigns.reallocations)
    projection = Projection.project_assets(assets, socket.assigns.years, allocations)

    # The chart always looks at least 20 years out, whatever the card horizon.
    chart_years = max(socket.assigns.years, 20)

    charts =
      Projection.project_assets(assets, chart_years, allocations).totals
      |> Enum.map(fn {currency, totals} -> {currency, totals.series} end)

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
    |> assign(:charts, charts)
    |> assign(:chart_years, chart_years)
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
