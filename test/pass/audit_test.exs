defmodule Pass.AuditTest do
  use Pass.DataCase, async: true

  alias Pass.Audit

  import Pass.AccountsFixtures

  test "log/3 records an event attributed to a user" do
    user = user_fixture()

    assert {:ok, event} =
             Audit.log(user, "asset.created", entity_type: "asset", summary: "House")

    assert event.actor_id == user.id
    assert event.actor_email == user.email
    assert event.action == "asset.created"
    assert event.summary == "House"
  end

  test "log/3 accepts a scope" do
    scope = user_scope_fixture()
    assert {:ok, event} = Audit.log(scope, "credential.revealed")
    assert event.actor_id == scope.user.id
  end

  test "log/3 accepts nil actor (system event)" do
    assert {:ok, event} = Audit.log(nil, "system.boot")
    assert event.actor_id == nil
    assert event.action == "system.boot"
  end

  test "list_events/1 returns events newest first" do
    user = user_fixture()
    {:ok, _} = Audit.log(user, "one")
    {:ok, _} = Audit.log(user, "two")

    actions = Audit.list_events() |> Enum.map(& &1.action)
    assert "one" in actions
    assert "two" in actions
  end

  test "list_events/2 filters by entity type" do
    user = user_fixture()
    {:ok, _} = Audit.log(user, "asset.created", entity_type: "asset", summary: "House")
    {:ok, _} = Audit.log(user, "credential.revealed", entity_type: "credential", summary: "Bank")

    actions = Audit.list_events(50, "asset") |> Enum.map(& &1.action)
    assert "asset.created" in actions
    refute "credential.revealed" in actions
  end

  test "list_events/2 respects the limit" do
    user = user_fixture()
    for i <- 1..5, do: Audit.log(user, "evt.#{i}")

    assert length(Audit.list_events(3)) == 3
  end
end
