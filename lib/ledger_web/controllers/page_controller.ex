defmodule LedgerWeb.PageController do
  use LedgerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
