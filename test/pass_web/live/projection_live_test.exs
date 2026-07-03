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
