defmodule PassWeb.AssetLiveTest do
  use PassWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "when not logged in" do
    test "the assets page redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/assets")
      assert path =~ "/users/log-in"
    end
  end

  describe "when logged in" do
    setup :register_and_log_in_user

    test "shows the empty state with no assets", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/assets")
      assert html =~ "Assets"
      assert html =~ "No assets yet"
    end

    test "creates an asset through the form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/assets/new")

      assert {:ok, _show_lv, html} =
               lv
               |> form("#asset-form",
                 asset: %{
                   name: "Beach House",
                   category: "real_estate",
                   access_instructions: "Key is with the neighbor."
                 }
               )
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "Beach House"
      assert html =~ "Key is with the neighbor."
    end

    test "shows validation errors for a blank name", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/assets/new")

      html =
        lv
        |> form("#asset-form", asset: %{name: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "lists a created asset", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/assets/new")

      lv
      |> form("#asset-form", asset: %{name: "Brokerage Account", category: "financial"})
      |> render_submit()

      {:ok, _index_lv, html} = live(conn, ~p"/assets")
      assert html =~ "Brokerage Account"
      assert html =~ "Financial"
    end
  end
end
