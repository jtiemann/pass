defmodule Pass.Audit do
  @moduledoc """
  Records an immutable trail of security-relevant actions (who did what, when).

  `log/3` is intentionally forgiving: it never raises, so a failure to write an
  audit row can't break the action being audited.
  """
  import Ecto.Query, warn: false

  alias Pass.Repo
  alias Pass.Audit.Event
  alias Pass.Accounts.{Scope, User}

  @doc """
  Records an event. Accepts a `Scope` or a `User` as the actor (or `nil` for a
  system action).

  ## Options
    * `:entity_type` - e.g. "asset", "credential"
    * `:entity_id`   - the affected record's id
    * `:summary`     - a short human-friendly description
  """
  def log(actor, action, opts \\ [])

  def log(%Scope{user: user}, action, opts), do: log(user, action, opts)

  def log(actor, action, opts) do
    {actor_id, actor_email} =
      case actor do
        %User{id: id, email: email} -> {id, email}
        _ -> {nil, nil}
      end

    attrs = %{
      actor_id: actor_id,
      actor_email: actor_email,
      action: action,
      entity_type: opts[:entity_type],
      entity_id: opts[:entity_id],
      summary: opts[:summary]
    }

    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  rescue
    _ -> {:error, :audit_failed}
  end

  @doc """
  Lists the most recent audit events (newest first), optionally filtered by
  `entity_type` (e.g. "asset", "credential", "user").
  """
  def list_events(limit \\ 200, entity_type \\ nil)

  def list_events(limit, nil) do
    Repo.all(from e in Event, order_by: [desc: e.inserted_at], limit: ^limit)
  end

  def list_events(limit, entity_type) when is_binary(entity_type) do
    Repo.all(
      from e in Event,
        where: e.entity_type == ^entity_type,
        order_by: [desc: e.inserted_at],
        limit: ^limit
    )
  end
end
