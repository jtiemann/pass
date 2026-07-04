defmodule PassWeb.ProjectionLiveTest do
  use PassWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "requires login", %{conn: conn} do
    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/projections")
    assert path =~ "/users/log-in"
  end

  describe "when logged in" do
    setup :register_and_log_in_user

    test "shows the empty state without valued assets", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/projections")
      assert html =~ "Projections"
      assert html =~ "No assets have an estimated value yet"
    end

    test "answers 'total gains after 5 years' and re-projects when the horizon changes", %{
      conn: conn,
      scope: scope
    } do
      # 10,000 at an explicit 10%: 5y -> 16,105.10 (gain 6,105.10); 10y -> 25,937.42
      {:ok, _} =
        Pass.Vault.create_asset(scope, %{
          name: "Index fund",
          category: :financial,
          estimated_value: 10_000,
          currency: "USD",
          annual_return_pct: 10
        })

      {:ok, lv, html} = live(conn, ~p"/projections")

      # Default horizon is 5 years.
      assert html =~ "In 5 years"
      assert html =~ "USD 16,105.10"
      assert html =~ "+USD 6,105.10"

      html = render_click(lv, "set_years", %{"years" => "10"})
      assert html =~ "In 10 years"
      assert html =~ "USD 25,937.42"
    end

    test "shows draws, the drawn-for-expenses total, and depletion warnings", %{
      conn: conn,
      scope: scope
    } do
      # 100,000 at 0% with a 30,000/yr draw depletes in year 4.
      {:ok, _} =
        Pass.Vault.create_asset(scope, %{
          name: "Spending account",
          category: :financial,
          estimated_value: 100_000,
          currency: "USD",
          annual_return_pct: 0,
          annual_draw: 30_000
        })

      {:ok, _lv, html} = live(conn, ~p"/projections")

      assert html =~ "Drawn for expenses"
      assert html =~ "USD 100,000.00"
      assert html =~ "depletes in year 4"
      # Configured draw per year is shown in the table.
      assert html =~ "USD 30,000.00"
    end

    test "asks where a depleted draw should continue and re-projects on allocation", %{
      conn: conn,
      scope: scope
    } do
      {:ok, spender} =
        Pass.Vault.create_asset(scope, %{
          name: "Spending account",
          category: :other,
          estimated_value: 100_000,
          currency: "USD",
          annual_return_pct: 0,
          annual_draw: 30_000
        })

      {:ok, _reserve} =
        Pass.Vault.create_asset(scope, %{
          name: "Reserve fund",
          category: :other,
          estimated_value: 500_000,
          currency: "USD",
          annual_return_pct: 0
        })

      {:ok, lv, html} = live(conn, ~p"/projections")

      # The page asks where to continue the draw, and reports the gap.
      assert html =~ "runs out in year 4"
      assert html =~ "Continue its"
      assert html =~ "Reserve fund"
      assert html =~ "can&#39;t be funded"

      # Split evenly (one target = 100% to the reserve): gap disappears,
      # the reserve absorbs 50,000 of draws over 5 years.
      html = render_click(lv, "split_evenly", %{"source" => spender.id})
      refute html =~ "can&#39;t be funded"
      assert html =~ "Fully allocated."

      # Total drawn now covers the full 30,000 × 5.
      assert html =~ "USD 150,000.00"
    end

    test "flags category defaults as assumed", %{conn: conn, scope: scope} do
      {:ok, _} =
        Pass.Vault.create_asset(scope, %{
          name: "Family car",
          category: :vehicle,
          estimated_value: 20_000,
          currency: "USD"
        })

      {:ok, _lv, html} = live(conn, ~p"/projections")
      assert html =~ "assumed"
      assert html =~ "-10%"
    end

    test "shows a financed rental property at equity with loan and cash-flow detail", %{
      conn: conn,
      scope: scope
    } do
      {:ok, _} =
        Pass.Vault.create_asset(scope, %{
          name: "Rental condo",
          category: :real_estate,
          estimated_value: 300_000,
          currency: "USD",
          annual_return_pct: 0,
          loan_balance: 100_000,
          loan_interest_pct: 0,
          loan_monthly_payment: 1000,
          rent_monthly: 2000,
          hoa_monthly: 300
        })

      {:ok, _lv, html} = live(conn, ~p"/projections")

      # Today = equity (300k − 100k), with the loan called out.
      assert html =~ "USD 200,000.00"
      assert html =~ "equity after USD 100,000.00 loan"
      assert html =~ "rent 2,000.00/mo"
      assert html =~ "HOA 300.00/mo"
      # After 5y: equity 260k + ops cash 42k = 302k, 40k loan left.
      assert html =~ "USD 302,000.00"
      assert html =~ "USD 40,000.00 loan remaining"
    end

    test "real-estate finances round-trip through the asset form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/assets/new")

      # The Property finances section only appears once the category is real
      # estate, so switch it first (as a user would).
      html =
        lv
        |> form("#asset-form", asset: %{category: "real_estate"})
        |> render_change()

      assert html =~ "Property finances"

      lv
      |> form("#asset-form",
        asset: %{
          name: "Beach condo",
          category: "real_estate",
          estimated_value: "400000",
          loan_balance: "250000",
          loan_interest_pct: "5.5",
          loan_monthly_payment: "1800",
          hoa_monthly: "450",
          rent_monthly: "2600"
        }
      )
      |> render_submit()

      [asset] = Pass.Vault.list_assets()
      assert Decimal.equal?(asset.loan_balance, Decimal.new(250_000))
      assert Decimal.equal?(asset.loan_interest_pct, Decimal.new("5.5"))
      assert Decimal.equal?(asset.loan_monthly_payment, Decimal.new(1800))
      assert Decimal.equal?(asset.hoa_monthly, Decimal.new(450))
      assert Decimal.equal?(asset.rent_monthly, Decimal.new(2600))
    end

    test "growth assumptions round-trip through the asset form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/assets/new")

      lv
      |> form("#asset-form",
        asset: %{
          name: "Brokerage",
          category: "financial",
          estimated_value: "5000",
          annual_return_pct: "8.5",
          dividend_yield_pct: "1.5",
          dividends_reinvested: "false"
        }
      )
      |> render_submit()

      [asset] = Pass.Vault.list_assets()
      assert Decimal.equal?(asset.annual_return_pct, Decimal.new("8.5"))
      assert Decimal.equal?(asset.dividend_yield_pct, Decimal.new("1.5"))
      assert asset.dividends_reinvested == false
    end
  end
end
