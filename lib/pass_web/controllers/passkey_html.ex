defmodule PassWeb.PasskeyHTML do
  @moduledoc """
  Templates rendered by `PassWeb.PasskeyController`.
  """
  use PassWeb, :html

  embed_templates "passkey_html/*"

  @doc "Human-friendly relative-ish label for when a key was last used."
  def last_used(nil), do: "never used"
  def last_used(%DateTime{} = dt), do: "last used " <> Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
end
