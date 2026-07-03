defmodule Pass.Accounts.ChallengeStoreTest do
  # Not async: exercises the globally named ETS table.
  use ExUnit.Case, async: false

  alias Pass.Accounts.ChallengeStore

  test "put/take round-trips a value" do
    ref = ChallengeStore.put(%{some: "challenge"})
    assert is_binary(ref)
    assert {:ok, %{some: "challenge"}} = ChallengeStore.take(ref)
  end

  test "take is one-shot" do
    ref = ChallengeStore.put(:once)
    assert {:ok, :once} = ChallengeStore.take(ref)
    assert :error = ChallengeStore.take(ref)
  end

  test "expired entries are not returned" do
    ref = ChallengeStore.put(:stale, -1)
    assert :error = ChallengeStore.take(ref)
  end

  test "unknown or nil refs return :error" do
    assert :error = ChallengeStore.take("nope")
    assert :error = ChallengeStore.take(nil)
  end
end
