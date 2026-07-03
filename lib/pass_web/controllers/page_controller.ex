defmodule PassWeb.PageController do
  use PassWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
