defmodule Pass.Vault.ProjectionTest do
  use ExUnit.Case, async: true

  alias Pass.Vault.{Asset, Projection}

  defp asset(attrs) do
    struct!(
      %Asset{
        name: "Test",
        category: :other,
        currency: "USD",
        dividends_reinvested: true
      },
      attrs
    )
  end

  describe "project_asset/2" do
    test "compounds a plain annual return" do
      # 1,000 at 10% for 5 years = 1,610.51
      row =
        Projection.project_asset(
          asset(estimated_value: Decimal.new(1000), annual_return_pct: Decimal.new(10)),
          5
        )

      assert_in_delta row.total, 1610.51, 0.01
      assert_in_delta row.gain, 610.51, 0.01
      refute row.assumed?
    end

    test "reinvested dividends compound with the return (total return)" do
      # 5% growth + 2% yield reinvested = 7% effective: 1,000 -> 1,402.55 over 5y
      row =
        Projection.project_asset(
          asset(
            estimated_value: Decimal.new(1000),
            annual_return_pct: Decimal.new(5),
            dividend_yield_pct: Decimal.new(2),
            dividends_reinvested: true
          ),
          5
        )

      assert_in_delta row.total, 1000 * :math.pow(1.07, 5), 0.01
      assert row.dividends_cash == 0.0
    end

    test "non-reinvested dividends accumulate as cash on a growing base" do
      # 10% growth, 2% yield paid out, 2 years:
      # asset: 1,000 -> 1,210; cash: 1,000·0.02·(1 + 1.1) = 42
      row =
        Projection.project_asset(
          asset(
            estimated_value: Decimal.new(1000),
            annual_return_pct: Decimal.new(10),
            dividend_yield_pct: Decimal.new(2),
            dividends_reinvested: false
          ),
          2
        )

      assert_in_delta row.future_value, 1210.0, 0.01
      assert_in_delta row.dividends_cash, 42.0, 0.01
      assert_in_delta row.total, 1252.0, 0.01
    end

    test "non-reinvested dividends with zero growth are simple interest" do
      row =
        Projection.project_asset(
          asset(
            estimated_value: Decimal.new(1000),
            annual_return_pct: Decimal.new(0),
            dividend_yield_pct: Decimal.new(3),
            dividends_reinvested: false
          ),
          5
        )

      assert_in_delta row.future_value, 1000.0, 0.01
      assert_in_delta row.dividends_cash, 150.0, 0.01
    end

    test "falls back to the category's historical default and flags it" do
      # Vehicles depreciate at the -10% default.
      row =
        Projection.project_asset(
          asset(estimated_value: Decimal.new(20_000), category: :vehicle),
          3
        )

      assert row.assumed?
      assert row.return_pct == -10.0
      assert_in_delta row.total, 20_000 * :math.pow(0.9, 3), 0.01
      assert row.gain < 0
    end

    test "assets without a value are excluded" do
      assert Projection.project_asset(asset(estimated_value: nil), 5) == nil
    end

    test "a yearly draw is withdrawn after growth, and counts toward gains" do
      # 1,000 @ 10%, draw 50/yr:
      #   y1: 1,100 - 50 = 1,050
      #   y2: 1,155 - 50 = 1,105
      row =
        Projection.project_asset(
          asset(
            estimated_value: Decimal.new(1000),
            annual_return_pct: Decimal.new(10),
            annual_draw: Decimal.new(50)
          ),
          2
        )

      assert_in_delta row.future_value, 1105.0, 0.01
      assert_in_delta row.total_drawn, 100.0, 0.01
      # Gain counts the drawn cash: 1,105 + 100 - 1,000
      assert_in_delta row.gain, 205.0, 0.01
      assert row.depleted_at == nil
    end

    test "a draw with zero growth just spends the asset down" do
      row =
        Projection.project_asset(
          asset(
            estimated_value: Decimal.new(1000),
            annual_return_pct: Decimal.new(0),
            annual_draw: Decimal.new(100)
          ),
          5
        )

      assert_in_delta row.future_value, 500.0, 0.01
      assert_in_delta row.total_drawn, 500.0, 0.01
      assert_in_delta row.gain, 0.0, 0.01
    end

    test "an unsustainable draw depletes the asset and only takes what's there" do
      # 1,000 @ 0%, draw 400/yr: y1 -> 600, y2 -> 200, y3 draws the last 200.
      row =
        Projection.project_asset(
          asset(
            estimated_value: Decimal.new(1000),
            annual_return_pct: Decimal.new(0),
            annual_draw: Decimal.new(400)
          ),
          5
        )

      assert row.depleted_at == 3
      assert_in_delta row.future_value, 0.0, 0.01
      assert_in_delta row.total_drawn, 1000.0, 0.01
      assert_in_delta row.gain, 0.0, 0.01
    end

    test "draws coexist with non-reinvested dividends" do
      # 1,000 @ 0% + 3% yield paid as cash, draw 100/yr, 2 years:
      #   y1: dividend 30 on 1,000; value 1,000 - 100 = 900
      #   y2: dividend 27 on 900;   value 900 - 100 = 800
      row =
        Projection.project_asset(
          asset(
            estimated_value: Decimal.new(1000),
            annual_return_pct: Decimal.new(0),
            dividend_yield_pct: Decimal.new(3),
            dividends_reinvested: false,
            annual_draw: Decimal.new(100)
          ),
          2
        )

      assert_in_delta row.future_value, 800.0, 0.01
      assert_in_delta row.dividends_cash, 57.0, 0.01
      assert_in_delta row.total_drawn, 200.0, 0.01
      # gain = 800 + 57 + 200 - 1000
      assert_in_delta row.gain, 57.0, 0.01
    end
  end

  describe "project_assets/2" do
    test "aggregates per currency and counts excluded assets" do
      assets = [
        asset(
          estimated_value: Decimal.new(1000),
          annual_return_pct: Decimal.new(10),
          currency: "USD"
        ),
        asset(
          estimated_value: Decimal.new(500),
          annual_return_pct: Decimal.new(0),
          currency: "USD"
        ),
        asset(
          estimated_value: Decimal.new(2000),
          annual_return_pct: Decimal.new(5),
          currency: "EUR"
        ),
        asset(estimated_value: nil)
      ]

      %{rows: rows, totals: totals, excluded: excluded} = Projection.project_assets(assets, 5)

      assert length(rows) == 3
      assert excluded == 1

      totals = Map.new(totals)
      assert_in_delta totals["USD"].current, 1500.0, 0.01
      assert_in_delta totals["USD"].total, 1000 * :math.pow(1.1, 5) + 500, 0.01
      assert_in_delta totals["EUR"].total, 2000 * :math.pow(1.05, 5), 0.01
    end
  end
end
