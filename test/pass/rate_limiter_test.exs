defmodule Pass.RateLimiterTest do
  # Not async: exercises the globally named ETS table.
  use ExUnit.Case, async: false

  alias Pass.RateLimiter

  test "allows up to the limit, then rejects" do
    key = "test:#{System.unique_integer()}"

    for _ <- 1..5 do
      assert :ok = RateLimiter.check(key, 5, 60)
    end

    assert {:error, :rate_limited} = RateLimiter.check(key, 5, 60)
    assert {:error, :rate_limited} = RateLimiter.check(key, 5, 60)
  end

  test "keys are independent" do
    a = "test:#{System.unique_integer()}"
    b = "test:#{System.unique_integer()}"

    assert :ok = RateLimiter.check(a, 1, 60)
    assert {:error, :rate_limited} = RateLimiter.check(a, 1, 60)
    assert :ok = RateLimiter.check(b, 1, 60)
  end
end
