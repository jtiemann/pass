defmodule Pass.VaultTest do
  use Pass.DataCase, async: true

  alias Pass.Vault
  alias Pass.Vault.Asset

  import Pass.AccountsFixtures

  describe "assets" do
    setup do
      %{scope: user_scope_fixture()}
    end

    test "create_asset/2 with valid data records the creator", %{scope: scope} do
      assert {:ok, %Asset{} = asset} =
               Vault.create_asset(scope, %{name: "Lake House", category: :real_estate})

      assert asset.name == "Lake House"
      assert asset.category == :real_estate
      assert asset.status == :active
      assert asset.created_by_id == scope.user.id
    end

    test "create_asset/2 requires a name", %{scope: scope} do
      assert {:error, changeset} = Vault.create_asset(scope, %{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "create_asset/2 rejects a negative estimated value", %{scope: scope} do
      assert {:error, changeset} =
               Vault.create_asset(scope, %{name: "X", estimated_value: -1})

      assert %{estimated_value: _} = errors_on(changeset)
    end

    test "list_assets/0 returns every asset (shared vault)", %{scope: scope} do
      other = user_scope_fixture()
      {:ok, a} = Vault.create_asset(scope, %{name: "Car", category: :vehicle})
      {:ok, b} = Vault.create_asset(other, %{name: "Boat", category: :vehicle})

      ids = Vault.list_assets() |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == Enum.sort([a.id, b.id])
    end

    test "update_asset/2 changes fields", %{scope: scope} do
      {:ok, asset} = Vault.create_asset(scope, %{name: "Old"})
      assert {:ok, updated} = Vault.update_asset(asset, %{name: "New"})
      assert updated.name == "New"
    end

    test "delete_asset/1 removes it", %{scope: scope} do
      {:ok, asset} = Vault.create_asset(scope, %{name: "Gone"})
      assert {:ok, _} = Vault.delete_asset(asset)
      assert Vault.list_assets() == []
    end

    test "changes broadcast to subscribers", %{scope: scope} do
      Vault.subscribe_assets()
      {:ok, asset} = Vault.create_asset(scope, %{name: "Broadcast"})
      assert_received {:created, %Asset{id: id}}
      assert id == asset.id
    end
  end

  describe "credentials" do
    alias Pass.Vault.Credential

    setup do
      scope = user_scope_fixture()
      {:ok, asset} = Vault.create_asset(scope, %{name: "Bank Account", category: :financial})
      %{scope: scope, asset: asset}
    end

    test "create_credential/2 stores and round-trips the secret", %{asset: asset} do
      assert {:ok, %Credential{} = cred} =
               Vault.create_credential(asset, %{
                 label: "Online banking",
                 username: "jon",
                 secret: "hunter2",
                 notes: "security question: pet"
               })

      assert cred.label == "Online banking"
      assert cred.secret == "hunter2"
      assert cred.notes == "security question: pet"
    end

    test "the secret is encrypted at rest (not plaintext in the column)", %{asset: asset} do
      {:ok, cred} = Vault.create_credential(asset, %{label: "X", secret: "hunter2"})

      %{rows: [[ciphertext]]} =
        Pass.Repo.query!("SELECT secret FROM credentials WHERE id = $1", [
          Ecto.UUID.dump!(cred.id)
        ])

      refute String.contains?(ciphertext, "hunter2")
    end

    test "the secret is redacted from inspect output", %{asset: asset} do
      {:ok, cred} = Vault.create_credential(asset, %{label: "X", secret: "hunter2"})
      refute inspect(cred) =~ "hunter2"
    end

    test "create_credential/2 requires a label", %{asset: asset} do
      assert {:error, changeset} = Vault.create_credential(asset, %{label: ""})
      assert %{label: ["can't be blank"]} = errors_on(changeset)
    end

    test "blank secret is stored as nil, not empty ciphertext", %{asset: asset} do
      {:ok, cred} = Vault.create_credential(asset, %{label: "No secret", secret: ""})
      assert cred.secret == nil
    end

    test "list_credentials/1 returns only that asset's credentials", %{scope: scope, asset: asset} do
      {:ok, other} = Vault.create_asset(scope, %{name: "Other"})
      {:ok, a} = Vault.create_credential(asset, %{label: "A"})
      {:ok, _b} = Vault.create_credential(other, %{label: "B"})

      assert Vault.list_credentials(asset) |> Enum.map(& &1.id) == [a.id]
    end

    test "delete_credential/1 removes it", %{asset: asset} do
      {:ok, cred} = Vault.create_credential(asset, %{label: "Gone"})
      assert {:ok, _} = Vault.delete_credential(cred)
      assert Vault.list_credentials(asset) == []
    end
  end

  describe "documents" do
    alias Pass.Vault.Document

    setup do
      scope = user_scope_fixture()
      {:ok, asset} = Vault.create_asset(scope, %{name: "House", category: :real_estate})
      %{scope: scope, asset: asset}
    end

    test "create_document/2 stores metadata and round-trips the contents", %{asset: asset} do
      assert {:ok, %Document{} = doc} =
               Vault.create_document(asset, %{
                 filename: "deed.pdf",
                 content_type: "application/pdf",
                 byte_size: 11,
                 data: "PDF-CONTENTS"
               })

      assert doc.filename == "deed.pdf"
      # get_document! reloads with decrypted data
      assert Vault.get_document!(asset, doc.id).data == "PDF-CONTENTS"
    end

    test "file contents are encrypted at rest", %{asset: asset} do
      {:ok, doc} =
        Vault.create_document(asset, %{filename: "d.txt", byte_size: 6, data: "secret"})

      %{rows: [[ciphertext]]} =
        Pass.Repo.query!("SELECT data FROM documents WHERE id = $1", [Ecto.UUID.dump!(doc.id)])

      refute String.contains?(ciphertext, "secret")
    end

    test "list_documents/1 returns metadata without decrypting file bytes", %{asset: asset} do
      {:ok, _} = Vault.create_document(asset, %{filename: "a.pdf", byte_size: 3, data: "abc"})

      [meta] = Vault.list_documents(asset)
      assert meta.filename == "a.pdf"
      assert meta.byte_size == 3
      # data field is not selected, so it stays nil in the list projection
      assert meta.data == nil
    end

    test "create_document/2 requires filename, byte_size and data", %{asset: asset} do
      assert {:error, changeset} = Vault.create_document(asset, %{filename: ""})
      errors = errors_on(changeset)
      assert errors[:filename]
      assert errors[:byte_size]
      assert errors[:data]
    end

    test "delete_document/1 removes it", %{asset: asset} do
      {:ok, doc} = Vault.create_document(asset, %{filename: "x", byte_size: 1, data: "y"})
      assert {:ok, _} = Vault.delete_document(doc)
      assert Vault.list_documents(asset) == []
    end
  end
end
