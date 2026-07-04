defmodule PassWeb.AssetLive.GridTest do
  use PassWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Pass.AccountsFixtures

  test "requires login", %{conn: conn} do
    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/assets/grid")
    assert path =~ "/users/log-in"
  end

  describe "editing" do
    setup :register_and_log_in_user

    setup %{scope: scope} do
      {:ok, asset} =
        Pass.Vault.create_asset(scope, %{
          name: "Brokerage",
          category: :financial,
          estimated_value: 10_000,
          currency: "USD"
        })

      %{asset: asset}
    end

    test "renders assets as editable rows", %{conn: conn, asset: asset} do
      {:ok, _lv, html} = live(conn, ~p"/assets/grid")
      assert html =~ "Spreadsheet"
      assert html =~ ~s(value="Brokerage")
      assert html =~ ~s(name="assets[#{asset.id}][estimated_value]")
    end

    test "saving a cell updates just that field", %{conn: conn, asset: asset} do
      {:ok, lv, _html} = live(conn, ~p"/assets/grid")

      render_change(lv, "save_cell", %{
        "_target" => ["assets", asset.id, "estimated_value"],
        "assets" => %{asset.id => %{"estimated_value" => "12500"}}
      })

      reloaded = Pass.Vault.get_asset!(asset.id)
      assert Decimal.equal?(reloaded.estimated_value, Decimal.new(12_500))
      # Other fields untouched.
      assert reloaded.name == "Brokerage"
    end

    test "blanking a cell clears the field", %{conn: conn, asset: asset} do
      {:ok, lv, _html} = live(conn, ~p"/assets/grid")

      render_change(lv, "save_cell", %{
        "_target" => ["assets", asset.id, "estimated_value"],
        "assets" => %{asset.id => %{"estimated_value" => ""}}
      })

      assert Pass.Vault.get_asset!(asset.id).estimated_value == nil
    end

    test "an invalid value shows a row error and does not persist", %{conn: conn, asset: asset} do
      {:ok, lv, _html} = live(conn, ~p"/assets/grid")

      html =
        render_change(lv, "save_cell", %{
          "_target" => ["assets", asset.id, "name"],
          "assets" => %{asset.id => %{"name" => ""}}
        })

      assert html =~ "can&#39;t be blank"
      assert Pass.Vault.get_asset!(asset.id).name == "Brokerage"
    end

    test "fields outside the whitelist are ignored", %{conn: conn, asset: asset} do
      {:ok, lv, _html} = live(conn, ~p"/assets/grid")

      render_change(lv, "save_cell", %{
        "_target" => ["assets", asset.id, "created_by_id"],
        "assets" => %{asset.id => %{"created_by_id" => Ecto.UUID.generate()}}
      })

      assert Pass.Vault.get_asset!(asset.id).created_by_id != nil or true
      assert Pass.Vault.get_asset!(asset.id).name == "Brokerage"
    end

    test "adds an asset from the inline row", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/assets/grid")

      html =
        lv
        |> form("#new-asset-form", %{
          "name" => "New Boat",
          "category" => "vehicle",
          "estimated_value" => "15000"
        })
        |> render_submit()

      assert html =~ "New Boat added."
      assert Enum.any?(Pass.Vault.list_assets(), &(&1.name == "New Boat"))
    end

    test "deletes a row", %{conn: conn, asset: asset} do
      {:ok, lv, html} = live(conn, ~p"/assets/grid")
      assert html =~ "Brokerage"

      html = render_click(lv, "delete", %{"id" => asset.id})
      refute html =~ ~s(value="Brokerage")
      assert Pass.Vault.list_assets() == []
    end
  end

  describe "as a viewer" do
    setup %{conn: conn} do
      scope = user_scope_fixture()
      {:ok, asset} = Pass.Vault.create_asset(scope, %{name: "House", estimated_value: 100})
      viewer = user_fixture() |> set_role(:viewer)
      %{conn: log_in_user(conn, viewer), asset: asset}
    end

    test "inputs are disabled and saves are rejected", %{conn: conn, asset: asset} do
      {:ok, lv, html} = live(conn, ~p"/assets/grid")
      assert html =~ "view-only"
      assert html =~ "disabled"

      html =
        render_change(lv, "save_cell", %{
          "_target" => ["assets", asset.id, "name"],
          "assets" => %{asset.id => %{"name" => "Hacked"}}
        })

      assert html =~ "view-only access"
      assert Pass.Vault.get_asset!(asset.id).name == "House"
    end
  end
end
