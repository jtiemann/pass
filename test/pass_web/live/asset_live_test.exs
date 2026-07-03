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

  describe "credentials on the show page" do
    setup :register_and_log_in_user

    setup %{scope: scope} do
      {:ok, asset} = Pass.Vault.create_asset(scope, %{name: "Bank", category: :financial})
      %{asset: asset}
    end

    test "adds a credential and never renders the plaintext secret", %{conn: conn, asset: asset} do
      {:ok, lv, _html} = live(conn, ~p"/assets/#{asset}")

      html =
        lv
        |> element("button", "Add credential")
        |> render_click()

      assert html =~ "credential-form"

      html =
        lv
        |> form("#credential-form",
          credential: %{label: "Online banking", username: "jon", secret: "hunter2"}
        )
        |> render_submit()

      assert html =~ "Online banking"
      assert html =~ "jon"
      # The secret must not appear in the rendered DOM (only masked).
      refute html =~ "hunter2"
      assert html =~ "••••••••"
    end

    test "reveal pushes the decrypted secret as an event, not into the DOM", %{
      conn: conn,
      asset: asset
    } do
      {:ok, credential} = Pass.Vault.create_credential(asset, %{label: "Login", secret: "s3cret"})
      {:ok, lv, _html} = live(conn, ~p"/assets/#{asset}")

      render_hook(lv, "reveal", %{"id" => credential.id})
      assert_push_event(lv, "secret:show", %{id: _id, value: "s3cret"})
    end

    test "deletes a credential", %{conn: conn, asset: asset} do
      {:ok, credential} = Pass.Vault.create_credential(asset, %{label: "Temp", secret: "x"})
      {:ok, lv, html} = live(conn, ~p"/assets/#{asset}")
      assert html =~ "Temp"

      html = render_hook(lv, "delete_credential", %{"id" => credential.id})
      refute html =~ "Temp"
    end
  end
end
