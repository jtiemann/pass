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
end
