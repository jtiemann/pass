defmodule PassWeb.DashboardLiveTest do
  use PassWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Pass.AccountsFixtures

  describe "as a guest" do
    test "shows the marketing landing with sign-up/login", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Get started"
      assert html =~ "Log in"
      refute html =~ "Your vault"
    end
  end

  describe "as a member" do
    setup :register_and_log_in_user

    test "shows an empty-vault overview", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Your vault"
      assert html =~ "Your vault is empty"
    end

    test "summarizes assets by category and totals", %{conn: conn, scope: scope} do
      {:ok, _} = Pass.Vault.create_asset(scope, %{name: "Cabin", category: :real_estate})
      {:ok, _} = Pass.Vault.create_asset(scope, %{name: "Roth IRA", category: :financial})

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "By category"
      assert html =~ "Real estate"
      assert html =~ "Recently added"
      assert html =~ "Cabin"
    end
  end

  describe "activity feed visibility" do
    test "owners see recent activity", %{conn: conn} do
      owner = user_fixture() |> set_role(:owner)
      conn = log_in_user(conn, owner)
      scope = Pass.Accounts.Scope.for_user(owner)
      {:ok, _} = Pass.Vault.create_asset(scope, %{name: "House"})
      Pass.Audit.log(owner, "asset.created", entity_type: "asset", summary: "House")

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Recent activity"
    end

    test "non-owners do not see the activity feed", %{conn: conn} do
      user = user_fixture() |> set_role(:viewer)
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/")
      refute html =~ "Recent activity"
    end
  end
end
