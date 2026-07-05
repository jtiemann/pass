defmodule PassWeb.UserLive.RegistrationTest do
  use PassWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Pass.AccountsFixtures

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Register"
      assert html =~ "Log in"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/assets")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "with spaces"})

      assert result =~ "Register"
      assert result =~ "must have the @ sign and no spaces"
    end
  end

  describe "register user" do
    test "creates account but does not log in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))

      {:ok, _lv, html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~
               ~r/An email was sent to .*, please access it to confirm your account/
    end

    test "the submit itself is refused if someone registered since mount", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      # First owner registers while this visitor's page is open.
      _first = user_fixture()

      assert {:error, {:live_redirect, %{to: "/users/log-in"}}} =
               lv
               |> form("#registration_form", user: %{"email" => unique_user_email()})
               |> render_submit()
    end
  end

  describe "invite-only after bootstrap" do
    setup do
      %{existing: user_fixture()}
    end

    test "the registration page is closed once a user exists", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in", flash: flash}}} =
               live(conn, ~p"/users/register")

      assert flash["error"] =~ "by invitation"
    end

    test "the login page stops advertising sign-up", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")
      refute html =~ "Sign up"
      assert html =~ "by invitation"
    end

    test "the guest landing offers login only", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      refute html =~ "Get started"
      assert html =~ "by invitation"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Log in")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert login_html =~ "Log in"
    end
  end
end
