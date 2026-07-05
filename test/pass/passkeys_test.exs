defmodule Pass.Accounts.PasskeysTest do
  use ExUnit.Case, async: true

  alias Pass.Accounts.Passkeys

  describe "check_sign_count/2 (WebAuthn clone detection)" do
    test "a strictly increasing counter is fine" do
      assert :ok = Passkeys.check_sign_count(5, 4)
      assert :ok = Passkeys.check_sign_count(100, 1)
    end

    test "zero counters are allowed (synced platform passkeys never increment)" do
      assert :ok = Passkeys.check_sign_count(0, 0)
      assert :ok = Passkeys.check_sign_count(0, 42)
    end

    test "a repeated or regressed counter signals a cloned credential" do
      assert {:error, :possible_credential_clone} = Passkeys.check_sign_count(4, 4)
      assert {:error, :possible_credential_clone} = Passkeys.check_sign_count(3, 4)
    end
  end
end
