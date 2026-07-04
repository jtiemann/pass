defmodule Pass.Vault.Projection do
  @moduledoc """
  Future-value projections for assets — pure math, no side effects.

  Each asset grows at its `annual_return_pct`; when unset, a **historical
  long-run default for its category** is assumed (see `default_return/1`).
  A `dividend_yield_pct` adds income on top:

    * **reinvested** — dividends compound into the asset, so the effective
      annual growth is `return + yield` (total-return compounding)
    * **not reinvested** — the asset compounds at `return` alone, and each
      year's dividend (`yield × that year's value`) accumulates as cash

  Projections are computed in floats (they're estimates by nature) and
  rounded to cents only for display. These are assumptions, not advice —
  the defaults are rough nominal long-run figures the user should override
  with rates that fit their actual holdings.
  """

  alias Pass.Vault.Asset

  # Rough long-run nominal annual returns by category, in percent. Deliberately
  # conservative and easy to override per asset. Crypto defaults to 0 because no
  # historical trend there is worth assuming on a family's behalf.
  @default_returns %{
    financial: 7.0,
    real_estate: 4.0,
    vehicle: -10.0,
    insurance: 0.0,
    digital: 0.0,
    crypto: 0.0,
    valuables: 2.0,
    business: 5.0,
    other: 0.0
  }

  @doc "The assumed historical annual return (%) for a category."
  def default_return(category), do: Map.get(@default_returns, category, 0.0)

  @doc """
  Projects one asset `years` into the future, simulated year by year:

    1. dividends are computed on the year's starting value (kept as cash
       unless reinvested, in which case they compound with the return)
    2. the value grows by the return
    3. the `annual_draw` is withdrawn at the end of the year

  A draw can only take what's there — once the asset is exhausted its value
  floors at zero and `depleted_at` records the year it ran out.

  Returns a map with the current value, projected asset value, accumulated
  dividends, total drawn, total remaining, gain (which counts drawn cash and
  dividends as gains — money you got to use), the rates used, and whether the
  return was an assumed category default. Returns `nil` for assets without an
  estimated value.
  """
  def project_asset(%Asset{estimated_value: nil}, _years), do: nil

  def project_asset(%Asset{} = asset, years) when is_integer(years) and years >= 0 do
    pv = Decimal.to_float(asset.estimated_value)
    assumed? = is_nil(asset.annual_return_pct)

    return_pct =
      if assumed?, do: default_return(asset.category), else: to_float(asset.annual_return_pct)

    yield_pct = if asset.dividend_yield_pct, do: to_float(asset.dividend_yield_pct), else: 0.0
    draw = if asset.annual_draw, do: to_float(asset.annual_draw), else: 0.0

    r = return_pct / 100
    d = yield_pct / 100
    reinvested? = asset.dividends_reinvested

    {future_value, dividends_cash, total_drawn, depleted_at} =
      simulate(pv, r, d, reinvested?, draw, years)

    total = future_value + dividends_cash

    %{
      asset: asset,
      current: pv,
      future_value: future_value,
      dividends_cash: dividends_cash,
      total_drawn: total_drawn,
      depleted_at: depleted_at,
      total: total,
      gain: total + total_drawn - pv,
      return_pct: return_pct,
      yield_pct: yield_pct,
      assumed?: assumed?
    }
  end

  defp simulate(pv, r, d, reinvested?, draw, years) do
    Enum.reduce(1..years//1, {pv, 0.0, 0.0, nil}, fn year, {value, cash, drawn, depleted} ->
      if value <= 0.0 do
        {value, cash, drawn, depleted}
      else
        cash = if reinvested?, do: cash, else: cash + value * d
        grown = if reinvested?, do: value * (1 + r + d), else: value * (1 + r)

        draw_taken = min(draw, max(grown, 0.0))
        remaining = max(grown - draw_taken, 0.0)

        depleted =
          if remaining == 0.0 and draw > 0.0 and is_nil(depleted), do: year, else: depleted

        {remaining, cash, drawn + draw_taken, depleted}
      end
    end)
  end

  @doc """
  Projects a list of assets jointly, per currency, and aggregates.

  `reallocations` maps a depleted asset's id to `%{target_asset_id => fraction}`
  (fractions 0..1). Draws never stop: once an asset can't cover its own draw,
  the shortfall is redirected to its targets **in the same year** (each target
  gives up to its share of the shortfall). Whatever no one covers accumulates
  as an *unfunded* shortfall for that currency, with the first gap year noted.
  Redirection happens only within the same currency.

  Returns `%{rows: [...], totals: [{currency, totals_map}], excluded: n}` where
  each totals map has `:current`, `:total`, `:drawn`, `:gain`, `:unfunded`, and
  `:first_gap_year`.
  """
  def project_assets(assets, years, reallocations \\ %{}) do
    {valued, skipped} = Enum.split_with(assets, & &1.estimated_value)
    indexed = Enum.with_index(valued)

    results =
      indexed
      |> Enum.group_by(fn {asset, _idx} -> asset.currency end)
      |> Enum.map(fn {currency, group} ->
        {currency, simulate_group(group, years, reallocations)}
      end)

    rows =
      results
      |> Enum.flat_map(fn {_currency, {rows, _totals}} -> rows end)
      |> Enum.sort_by(fn {_row, idx} -> idx end)
      |> Enum.map(fn {row, _idx} -> row end)

    totals =
      results
      |> Enum.map(fn {currency, {_rows, totals}} -> {currency, totals} end)
      |> Enum.sort_by(fn {_currency, %{current: current}} -> current end, :desc)

    %{rows: rows, totals: totals, excluded: length(skipped)}
  end

  # Simulates all assets of one currency together, year by year, so that
  # shortfalls can be redirected between them.
  defp simulate_group(group, years, reallocations) do
    params =
      Enum.map(group, fn {asset, idx} ->
        assumed? = is_nil(asset.annual_return_pct)

        return_pct =
          if assumed?, do: default_return(asset.category), else: to_float(asset.annual_return_pct)

        yield_pct = if asset.dividend_yield_pct, do: to_float(asset.dividend_yield_pct), else: 0.0

        %{
          idx: idx,
          asset: asset,
          pv: Decimal.to_float(asset.estimated_value),
          r: return_pct / 100,
          d: yield_pct / 100,
          reinvested?: asset.dividends_reinvested,
          draw: if(asset.annual_draw, do: to_float(asset.annual_draw), else: 0.0),
          return_pct: return_pct,
          yield_pct: yield_pct,
          assumed?: assumed?
        }
      end)

    id_to_idx = for %{asset: %{id: id}, idx: idx} <- params, id != nil, into: %{}, do: {id, idx}

    init_states =
      Map.new(params, fn p ->
        {p.idx, %{value: p.pv, cash: 0.0, drawn: 0.0, depleted_at: nil}}
      end)

    {states, unfunded, first_gap_year} =
      Enum.reduce(1..years//1, {init_states, 0.0, nil}, fn year, acc ->
        simulate_year(year, params, acc, reallocations, id_to_idx)
      end)

    rows =
      Enum.map(params, fn p ->
        state = states[p.idx]
        total = state.value + state.cash

        row = %{
          asset: p.asset,
          current: p.pv,
          future_value: state.value,
          dividends_cash: state.cash,
          total_drawn: state.drawn,
          depleted_at: state.depleted_at,
          total: total,
          gain: total + state.drawn - p.pv,
          return_pct: p.return_pct,
          yield_pct: p.yield_pct,
          assumed?: p.assumed?
        }

        {row, p.idx}
      end)

    totals = %{
      current: sum_by(rows, fn {row, _} -> row.current end),
      total: sum_by(rows, fn {row, _} -> row.total end),
      drawn: sum_by(rows, fn {row, _} -> row.total_drawn end),
      gain: sum_by(rows, fn {row, _} -> row.gain end),
      unfunded: unfunded,
      first_gap_year: first_gap_year
    }

    {rows, totals}
  end

  defp simulate_year(year, params, {states, unfunded, first_gap}, reallocations, id_to_idx) do
    # Phase 1: dividends, growth, and each asset's own draw. Shortfalls are the
    # part of a draw the asset itself couldn't cover this year.
    {states, shortfalls} =
      Enum.reduce(params, {states, []}, fn p, {states, shortfalls} ->
        state = states[p.idx]

        cond do
          state.value <= 0.0 and p.draw > 0.0 ->
            {states, [{p, p.draw} | shortfalls]}

          state.value <= 0.0 ->
            {states, shortfalls}

          true ->
            cash = if p.reinvested?, do: state.cash, else: state.cash + state.value * p.d
            growth = 1 + p.r + if(p.reinvested?, do: p.d, else: 0.0)
            grown = max(state.value * growth, 0.0)
            take = min(p.draw, grown)
            value = grown - take

            depleted_at =
              if value <= 0.0 and p.draw > 0.0 and is_nil(state.depleted_at),
                do: year,
                else: state.depleted_at

            state = %{
              state
              | value: value,
                cash: cash,
                drawn: state.drawn + take,
                depleted_at: depleted_at
            }

            states = Map.put(states, p.idx, state)

            if p.draw - take > 1.0e-9 do
              {states, [{p, p.draw - take} | shortfalls]}
            else
              {states, shortfalls}
            end
        end
      end)

    # Phase 2: redirect shortfalls to their fallback targets; whatever the
    # targets can't cover is unfunded.
    Enum.reduce(shortfalls, {states, unfunded, first_gap}, fn {p, amount},
                                                              {states, unfunded, first_gap} ->
      allocation = Map.get(reallocations, p.asset.id, %{})

      {states, covered} =
        Enum.reduce(allocation, {states, 0.0}, fn {target_id, fraction}, {states, covered} ->
          target_idx = Map.get(id_to_idx, target_id)

          if is_nil(target_idx) or target_idx == p.idx or fraction <= 0.0 do
            {states, covered}
          else
            target = states[target_idx]
            want = amount * fraction
            take = min(want, max(target.value, 0.0))
            value = target.value - take

            depleted_at =
              if value <= 0.0 and take > 0.0 and is_nil(target.depleted_at),
                do: year,
                else: target.depleted_at

            target = %{
              target
              | value: value,
                drawn: target.drawn + take,
                depleted_at: depleted_at
            }

            {Map.put(states, target_idx, target), covered + take}
          end
        end)

      gap = amount - covered

      if gap > 1.0e-9 do
        {states, unfunded + gap, first_gap || year}
      else
        {states, unfunded, first_gap}
      end
    end)
  end

  @doc "Rounds a float projection to a Decimal with cents, for money formatting."
  def to_money(float) when is_float(float) do
    float |> Float.round(2) |> Decimal.from_float()
  end

  defp sum_by(rows, fun), do: Enum.reduce(rows, 0.0, &(fun.(&1) + &2))

  defp to_float(%Decimal{} = decimal), do: Decimal.to_float(decimal)
end
