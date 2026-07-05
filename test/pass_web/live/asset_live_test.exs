defmodule PassWeb.AssetLiveTest do
  use PassWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Pass.AccountsFixtures

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

    @tag token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
    test "reveal requires a recent authentication", %{conn: conn, asset: asset} do
      {:ok, credential} = Pass.Vault.create_credential(asset, %{label: "Login", secret: "s3cret"})
      {:ok, lv, _html} = live(conn, ~p"/assets/#{asset}")

      assert {:error, {:live_redirect, %{to: "/users/log-in"}}} =
               render_hook(lv, "reveal", %{"id" => credential.id})
    end

    test "deletes a credential", %{conn: conn, asset: asset} do
      {:ok, credential} = Pass.Vault.create_credential(asset, %{label: "Temp", secret: "x"})
      {:ok, lv, html} = live(conn, ~p"/assets/#{asset}")
      assert html =~ "Temp"

      html = render_hook(lv, "delete_credential", %{"id" => credential.id})
      refute html =~ "Temp"
    end

    test "edits a credential, keeping the secret when the field is left blank", %{
      conn: conn,
      asset: asset
    } do
      {:ok, credential} =
        Pass.Vault.create_credential(asset, %{
          label: "Bank login",
          username: "jon",
          secret: "keepme"
        })

      {:ok, lv, _html} = live(conn, ~p"/assets/#{asset}")

      # Opening the edit form must not leak the decrypted secret into the DOM.
      html = render_hook(lv, "edit_credential", %{"id" => credential.id})
      assert html =~ "Editing"
      refute html =~ "keepme"

      html =
        lv
        |> form("#credential-form",
          credential: %{label: "Bank login", username: "jon2", secret: ""}
        )
        |> render_submit()

      assert html =~ "Credential updated."
      assert html =~ "jon2"

      reloaded = Pass.Vault.get_credential!(asset, credential.id)
      assert reloaded.username == "jon2"
      assert reloaded.secret == "keepme"
    end

    test "edits a credential and replaces the secret when one is entered", %{
      conn: conn,
      asset: asset
    } do
      {:ok, credential} = Pass.Vault.create_credential(asset, %{label: "X", secret: "old"})
      {:ok, lv, _html} = live(conn, ~p"/assets/#{asset}")

      render_hook(lv, "edit_credential", %{"id" => credential.id})

      lv
      |> form("#credential-form", credential: %{label: "X", secret: "brand-new"})
      |> render_submit()

      assert Pass.Vault.get_credential!(asset, credential.id).secret == "brand-new"
    end

    test "edits a contact", %{conn: conn, asset: asset} do
      {:ok, contact} = Pass.Vault.create_contact(asset, %{name: "Jane", relationship: "Attorney"})
      {:ok, lv, _html} = live(conn, ~p"/assets/#{asset}")

      html = render_hook(lv, "edit_contact", %{"id" => contact.id})
      assert html =~ "Editing"

      html =
        lv
        |> form("#contact-form", contact: %{name: "Jane Smith", relationship: "Estate attorney"})
        |> render_submit()

      assert html =~ "Contact updated."
      assert html =~ "Jane Smith"
      assert Pass.Vault.get_contact!(asset, contact.id).name == "Jane Smith"
    end
  end

  describe "documents on the show page" do
    setup :register_and_log_in_user

    setup %{scope: scope} do
      {:ok, asset} = Pass.Vault.create_asset(scope, %{name: "House", category: :real_estate})
      %{asset: asset}
    end

    test "uploads a document and lists it (encrypted at rest)", %{conn: conn, asset: asset} do
      {:ok, lv, _html} = live(conn, ~p"/assets/#{asset}")

      file =
        file_input(lv, "#document-form", :document, [
          %{name: "deed.pdf", content: "SECRET-PDF-BYTES", type: "application/pdf"}
        ])

      assert render_upload(file, "deed.pdf") =~ "deed.pdf"

      html = lv |> element("#document-form") |> render_submit()
      assert html =~ "deed.pdf"

      # Persisted and encrypted
      [doc] = Pass.Vault.list_documents(asset)
      assert doc.filename == "deed.pdf"

      %{rows: [[ciphertext]]} =
        Pass.Repo.query!("SELECT data FROM documents WHERE id = $1", [Ecto.UUID.dump!(doc.id)])

      refute String.contains?(ciphertext, "SECRET-PDF-BYTES")
    end

    test "rejects a file that is too large", %{conn: conn, asset: asset} do
      {:ok, lv, _html} = live(conn, ~p"/assets/#{asset}")

      big = :binary.copy("x", 10_000_001)

      file =
        file_input(lv, "#document-form", :document, [
          %{name: "huge.pdf", content: big, type: "application/pdf"}
        ])

      assert {:error, [[_ref, :too_large]]} = render_upload(file, "huge.pdf")
    end
  end

  describe "archived assets" do
    setup :register_and_log_in_user

    setup %{scope: scope} do
      {:ok, active} = Pass.Vault.create_asset(scope, %{name: "Active Cabin"})
      {:ok, archived} = Pass.Vault.create_asset(scope, %{name: "Old Boat", status: :archived})
      %{active: active, archived: archived}
    end

    test "hides archived assets by default", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/assets")
      assert html =~ "Active Cabin"
      refute html =~ "Old Boat"
    end

    test "the toggle reveals archived assets", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/assets")

      html = render_hook(lv, "toggle_archived", %{})
      assert html =~ "Active Cabin"
      assert html =~ "Old Boat"
    end
  end

  describe "as a viewer (read-only)" do
    setup %{conn: conn} do
      user = user_fixture() |> set_role(:viewer)
      %{conn: log_in_user(conn, user)}
    end

    test "does not see the New asset button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/assets")
      refute html =~ "New asset"
    end

    test "is redirected away from the new-asset form", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/assets"}}} = live(conn, ~p"/assets/new")
    end

    test "sees no edit/delete controls on an asset", %{conn: conn} do
      scope = user_scope_fixture()
      {:ok, asset} = Pass.Vault.create_asset(scope, %{name: "Cabin", category: :real_estate})

      {:ok, _lv, html} = live(conn, ~p"/assets/#{asset}")
      refute html =~ "Add credential"
      refute html =~ "Add contact"
    end
  end
end
