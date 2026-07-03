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
      </div>

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

  defp project(socket) do
    assign(
      socket,
      :projection,
      Projection.project_assets(Vault.list_assets(), socket.assigns.years)
    )
  end

  defp quick_horizons, do: @quick_horizons

  defp draw?(asset) do
    asset.annual_draw != nil and Decimal.compare(asset.annual_draw, 0) == :gt
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
