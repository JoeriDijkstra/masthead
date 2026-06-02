defmodule MastheadWeb.AdminController do
  use MastheadWeb, :controller

  alias Masthead.Themes

  @doc "Streams an uploaded theme's source files as a .zip download."
  def download_theme(conn, %{"id" => id}) do
    theme = Themes.get_theme!(id)

    case Themes.package_theme(theme) do
      {:ok, filename, zip} ->
        send_download(conn, {:binary, zip}, filename: filename, content_type: "application/zip")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "That theme can't be downloaded.")
        |> redirect(to: ~p"/admin")
    end
  end
end
