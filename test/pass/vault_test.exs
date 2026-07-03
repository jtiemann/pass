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

    test "dashboard_summary/0 totals per currency, never across them", %{scope: scope} do
      {:ok, _} =
        Vault.create_asset(scope, %{name: "US House", estimated_value: 100, currency: "USD"})

      {:ok, _} =
        Vault.create_asset(scope, %{name: "US Car", estimated_value: 50, currency: "USD"})

      {:ok, _} =
        Vault.create_asset(scope, %{name: "EU Flat", estimated_value: 200, currency: "EUR"})

      {:ok, _} = Vault.create_asset(scope, %{name: "No value"})

      summary = Vault.dashboard_summary()

      assert summary.total_assets == 4

      totals = Map.new(summary.totals)
      assert Decimal.equal?(totals["USD"], Decimal.new(150))
      assert Decimal.equal?(totals["EUR"], Decimal.new(200))
      assert map_size(totals) == 2
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

  describe "export" do
    test "includes decrypted credentials and document metadata, but no file bytes" do
      scope = user_scope_fixture()
      {:ok, asset} = Vault.create_asset(scope, %{name: "Bank", category: :financial})
      {:ok, _} = Vault.create_credential(asset, %{label: "Login", secret: "hunter2"})
      {:ok, _} = Vault.create_contact(asset, %{name: "Jane", relationship: "Advisor"})

      {:ok, _} =
        Vault.create_document(asset, %{filename: "deed.pdf", byte_size: 9, data: "FILEBYTES"})

      export = Vault.export()
      assert [exported] = export.assets
      assert exported.name == "Bank"

      assert [credential] = exported.credentials
      assert credential.secret == "hunter2"

      assert [contact] = exported.contacts
      assert contact.name == "Jane"

      assert [document] = exported.documents
      assert document.filename == "deed.pdf"
      refute Map.has_key?(document, :data)

      # And the whole thing is JSON-encodable (what mix pass.export prints).
      json = Jason.encode!(export)
      assert json =~ "hunter2"
      refute json =~ "FILEBYTES"
    end
  end

  describe "import" do
    test "round-trips an export through JSON: wipe, import, everything restored" do
      scope = user_scope_fixture()

      {:ok, asset} =
        Vault.create_asset(scope, %{
          name: "Bank",
          category: :financial,
          estimated_value: 100,
          currency: "USD"
        })

      {:ok, _} =
        Vault.create_credential(asset, %{label: "Login", username: "jon", secret: "hunter2"})

      {:ok, _} = Vault.create_contact(asset, %{name: "Jane", relationship: "Advisor"})

      {:ok, _} =
        Vault.create_document(asset, %{filename: "deed.pdf", byte_size: 5, data: "BYTES"})

      # Serialize exactly the way mix pass.export does, then wipe the vault.
      json = Vault.export() |> Jason.encode!() |> Jason.decode!()
      {:ok, _} = Vault.delete_asset(asset)
      assert Vault.list_assets() == []

      assert {:ok, summary} = Vault.import_data(json)
      assert summary.imported == 1
      assert summary.credentials == 1
      assert summary.contacts == 1
      assert summary.documents_skipped == 1
      assert summary.skipped == []

      [restored] = Vault.list_assets()
      assert restored.name == "Bank"
      assert restored.category == :financial
      assert Decimal.equal?(restored.estimated_value, Decimal.new(100))

      # The secret decrypts again — re-encrypted on insert.
      [credential] = Vault.list_credentials(restored)
      assert credential.secret == "hunter2"

      [contact] = Vault.list_contacts(restored)
      assert contact.name == "Jane"

      # Document contents are not restorable from an export.
      assert Vault.list_documents(restored) == []
    end

    test "skips assets whose name already exists (safe to re-run)" do
      scope = user_scope_fixture()
      {:ok, _} = Vault.create_asset(scope, %{name: "Bank"})

      data = %{
        "assets" => [
          %{"name" => "Bank", "credentials" => [%{"label" => "X", "secret" => "no"}]},
          %{"name" => "Boat", "category" => "vehicle"}
        ]
      }

      assert {:ok, summary} = Vault.import_data(data)
      assert summary.imported == 1
      assert summary.skipped == ["Bank"]
      # Nothing was attached to the existing "Bank" asset.
      [existing] = Enum.filter(Vault.list_assets(), &(&1.name == "Bank"))
      assert Vault.list_credentials(existing) == []
    end

    test "rolls back the whole import when any record is invalid" do
      data = %{
        "assets" => [
          %{"name" => "Good asset"},
          # credential without a label is invalid
          %{"name" => "Bad asset", "credentials" => [%{"secret" => "x"}]}
        ]
      }

      assert {:error, {:invalid_record, "Bad asset", %Ecto.Changeset{}}} =
               Vault.import_data(data)

      # Atomic: even the valid asset was not imported.
      assert Vault.list_assets() == []
    end

    test "rejects files that are not exports" do
      assert {:error, :invalid_format} = Vault.import_data(%{"nope" => true})
    end
  end

  describe "contacts" do
    alias Pass.Vault.Contact

    setup do
      scope = user_scope_fixture()
      {:ok, asset} = Vault.create_asset(scope, %{name: "Estate", category: :real_estate})
      %{asset: asset}
    end

    test "create_contact/2 with valid data", %{asset: asset} do
      assert {:ok, %Contact{} = contact} =
               Vault.create_contact(asset, %{
                 name: "Jane Doe",
                 relationship: "Attorney",
                 email: "jane@example.com"
               })

      assert contact.name == "Jane Doe"
      assert contact.relationship == "Attorney"
    end

    test "create_contact/2 requires a name", %{asset: asset} do
      assert {:error, changeset} = Vault.create_contact(asset, %{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "create_contact/2 rejects a malformed email", %{asset: asset} do
      assert {:error, changeset} =
               Vault.create_contact(asset, %{name: "X", email: "not-an-email"})

      assert %{email: _} = errors_on(changeset)
    end

    test "list_contacts/1 returns only that asset's contacts", %{asset: asset} do
      scope = user_scope_fixture()
      {:ok, other} = Vault.create_asset(scope, %{name: "Other"})
      {:ok, a} = Vault.create_contact(asset, %{name: "A"})
      {:ok, _b} = Vault.create_contact(other, %{name: "B"})

      assert Vault.list_contacts(asset) |> Enum.map(& &1.id) == [a.id]
    end

    test "update_contact/2 changes fields", %{asset: asset} do
      {:ok, contact} = Vault.create_contact(asset, %{name: "Old Name"})

      assert {:ok, updated} =
               Vault.update_contact(contact, %{name: "New Name", phone: "555-1234"})

      assert updated.name == "New Name"
      assert updated.phone == "555-1234"
    end

    test "delete_contact/1 removes it", %{asset: asset} do
      {:ok, contact} = Vault.create_contact(asset, %{name: "Gone"})
      assert {:ok, _} = Vault.delete_contact(contact)
      assert Vault.list_contacts(asset) == []
    end
  end
end
