defmodule PassWeb.UserLive.AdminTest do
  use PassWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Pass.AccountsFixtures

  alias Pass.Accounts

  test "non-owners are redirected away from member management", %{conn: conn} do
    _owner = user_fixture() |> set_role(:owner)
    member = user_fixture() |> set_role(:member)
    conn = log_in_user(conn, member)

    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/users")
    assert path == "/assets"
  end

  describe "as an owner" do
    setup %{conn: conn} do
      owner = user_fixture() |> set_role(:owner)
      %{conn: log_in_user(conn, owner), owner: owner}
    end

    test "lists users and changes a role", %{conn: conn} do
      member = user_fixture() |> set_role(:member)

      {:ok, lv, html} = live(conn, ~p"/users")
      assert html =~ member.email

      render_hook(lv, "change_role", %{"user_id" => member.id, "role" => "viewer"})
      assert Accounts.get_user!(member.id).role == :viewer
    end

    test "refuses to demote the last owner", %{conn: conn, owner: owner} do
      {:ok, lv, _html} = live(conn, ~p"/users")

      html = render_hook(lv, "change_role", %{"user_id" => owner.id, "role" => "member"})
      assert html =~ "last owner"
      assert Accounts.get_user!(owner.id).role == :owner
    end

    test "invites a new member with a preset role", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users")

      html =
        lv
        |> form("#invite-form", %{"email" => "aunt.judy@example.com", "role" => "viewer"})
        |> render_submit()

      assert html =~ "Invitation sent to aunt.judy@example.com"
      assert html =~ "aunt.judy@example.com"

      invited = Pass.Accounts.get_user_by_email("aunt.judy@example.com")
      assert invited.role == :viewer
    end

    test "shows an error when inviting an existing member", %{conn: conn} do
      existing = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/users")

      html =
        lv
        |> form("#invite-form", %{"email" => existing.email, "role" => "member"})
        |> render_submit()

      assert html =~ "Couldn&#39;t invite that address"
    end
  end
end
