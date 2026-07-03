defmodule Pass.AccountsRolesTest do
  use Pass.DataCase, async: true

  alias Pass.Accounts
  alias Pass.Accounts.Scope

  import Pass.AccountsFixtures

  describe "role assignment on registration" do
    test "the first user to register becomes the owner" do
      {:ok, first} = Accounts.register_user(valid_user_attributes())
      assert first.role == :owner
    end

    test "subsequent users become members" do
      {:ok, _first} = Accounts.register_user(valid_user_attributes())
      {:ok, second} = Accounts.register_user(valid_user_attributes())
      assert second.role == :member
    end
  end

  describe "Scope.can?/2" do
    test "owner can do everything" do
      scope = user_fixture() |> set_role(:owner) |> Scope.for_user()
      assert Scope.can?(scope, :read)
      assert Scope.can?(scope, :write)
      assert Scope.can?(scope, :manage_users)
    end

    test "member can read and write but not manage users" do
      scope = user_fixture() |> set_role(:member) |> Scope.for_user()
      assert Scope.can?(scope, :read)
      assert Scope.can?(scope, :write)
      refute Scope.can?(scope, :manage_users)
    end

    test "viewer can only read" do
      scope = user_fixture() |> set_role(:viewer) |> Scope.for_user()
      assert Scope.can?(scope, :read)
      refute Scope.can?(scope, :write)
      refute Scope.can?(scope, :manage_users)
    end

    test "nil scope can do nothing" do
      refute Scope.can?(nil, :read)
    end
  end

  describe "update_user_role/2" do
    test "changes a user's role" do
      owner = user_fixture() |> set_role(:owner)
      member = user_fixture() |> set_role(:member)

      # owner exists, so promoting/demoting the member is fine
      assert {:ok, updated} = Accounts.update_user_role(member, :viewer)
      assert updated.role == :viewer
      # keep owner referenced
      assert owner.role == :owner
    end

    test "refuses to demote the last owner" do
      owner = user_fixture() |> set_role(:owner)
      assert {:error, :last_owner} = Accounts.update_user_role(owner, :member)
    end

    test "allows demoting an owner when another owner exists" do
      _owner1 = user_fixture() |> set_role(:owner)
      owner2 = user_fixture() |> set_role(:owner)

      assert {:ok, updated} = Accounts.update_user_role(owner2, :member)
      assert updated.role == :member
    end
  end
end
