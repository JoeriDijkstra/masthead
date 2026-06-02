defmodule MastheadWeb.PageController do
  use MastheadWeb, :controller

  def home(conn, _params) do
    case conn.assigns[:current_user] do
      nil -> render(conn, :home)
      _user -> redirect(conn, to: "/sites")
    end
  end
end
