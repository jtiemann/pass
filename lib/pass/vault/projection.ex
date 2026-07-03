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
  Projects one asset `years` into the future. Returns a map with the current
  value, projected asset value, accumulated (non-reinvested) dividends, total,
  gain, the rates that were used, and whether the return was an assumed
  category default. Returns `nil` for assets without an estimated value.
  """
  def project_asset(%Asset{estimated_value: nil}, _years), do: nil

  def project_asset(%Asset{} = asset, years) when is_integer(years) and years >= 0 do
    pv = Decimal.to_float(asset.estimated_value)
    assumed? = is_nil(asset.annual_return_pct)

    return_pct =
      if assumed?, do: default_return(asset.category), else: to_float(asset.annual_return_pct)

    yield_pct = if asset.dividend_yield_pct, do: to_float(asset.dividend_yield_pct), else: 0.0

    r = return_pct / 100
    d = yield_pct / 100

    {future_value, dividends_cash} =
      cond do
        asset.dividends_reinvested ->
          {pv * :math.pow(1 + r + d, years), 0.0}

        r == 0.0 ->
          {pv, pv * d * years}

        true ->
          # Dividend paid on each year's starting value: pv·d·Σ(1+r)^k
          {pv * :math.pow(1 + r, years), pv * d * (:math.pow(1 + r, years) - 1) / r}
      end

    total = future_value + dividends_cash

    %{
      asset: asset,
      current: pv,
      future_value: future_value,
      dividends_cash: dividends_cash,
      total: total,
      gain: total - pv,
      return_pct: return_pct,
      yield_pct: yield_pct,
      assumed?: assumed?
    }
  end

  @doc """
  Projects a list of assets and aggregates per currency. Returns
  `%{rows: [...], totals: [{currency, %{current:, total:, gain:}}], excluded: n}`
  where `excluded` counts assets without an estimated value.
  """
  def project_assets(assets, years) do
    rows =
      assets
      |> Enum.map(&project_asset(&1, years))
      |> Enum.reject(&is_nil/1)

    totals =
      rows
      |> Enum.group_by(& &1.asset.currency)
      |> Enum.map(fn {currency, currency_rows} ->
        {currency,
         %{
           current: sum_by(currency_rows, & &1.current),
           total: sum_by(currency_rows, & &1.total),
           gain: sum_by(currency_rows, & &1.gain)
         }}
      end)
      |> Enum.sort_by(fn {_currency, %{current: current}} -> current end, :desc)

    %{rows: rows, totals: totals, excluded: length(assets) - length(rows)}
  end

  @doc "Rounds a float projection to a Decimal with cents, for money formatting."
  def to_money(float) when is_float(float) do
    float |> Float.round(2) |> Decimal.from_float()
  end

  defp sum_by(rows, fun), do: Enum.reduce(rows, 0.0, &(fun.(&1) + &2))

  defp to_float(%Decimal{} = decimal), do: Decimal.to_float(decimal)
end
