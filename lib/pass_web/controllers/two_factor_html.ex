defmodule PassWeb.TwoFactorHTML do
  @moduledoc """
  Templates rendered by `PassWeb.TwoFactorController`.
  """
  use PassWeb, :html

  embed_templates "two_factor_html/*"
end
