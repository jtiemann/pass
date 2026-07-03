defmodule PassWeb.DocumentControllerTest do
  use PassWeb.ConnCase, async: true

  alias Pass.Vault

  setup %{conn: conn} do
    scope = Pass.AccountsFixtures.user_scope_fixture()
    {:ok, asset} = Vault.create_asset(scope, %{name: "House", category: :real_estate})

    {:ok, document} =
      Vault.create_document(asset, %{
        filename: "deed.pdf",
        content_type: "application/pdf",
        byte_size: 11,
        data: "PDF-CONTENT"
      })

    %{conn: conn, asset: asset, document: document}
  end

  test "requires authentication", %{conn: conn, asset: asset, document: document} do
    conn = get(conn, ~p"/assets/#{asset}/documents/#{document.id}/download")
    assert redirected_to(conn) =~ "/users/log-in"
  end

  describe "when logged in" do
    setup :register_and_log_in_user

    test "downloads the decrypted file as an attachment", %{
      conn: conn,
      asset: asset,
      document: document
    } do
      conn = get(conn, ~p"/assets/#{asset}/documents/#{document.id}/download")

      assert response(conn, 200) == "PDF-CONTENT"
      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
      assert disposition =~ "deed.pdf"
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    end

    test "404s for a document that doesn't belong to the asset", %{conn: conn, document: document} do
      other_scope = Pass.AccountsFixtures.user_scope_fixture()
      {:ok, other_asset} = Vault.create_asset(other_scope, %{name: "Other"})

      assert_error_sent 404, fn ->
        get(conn, ~p"/assets/#{other_asset}/documents/#{document.id}/download")
      end
    end
  end
end
