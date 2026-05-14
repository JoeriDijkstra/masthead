defmodule LedgerWeb.Plugs.Subdomain do
  @moduledoc """
  Resolves the subdomain on `conn.host` to a `Ledger.Sites.Site`.

  - On the bare app host (e.g. `ledger.local`, `localhost`, `lvh.me`), this is
    a no-op: the request is for the marketing / admin surface.
  - On a subdomain that matches a site slug, the site is assigned to
    `conn.assigns.current_site`.
  - On a subdomain that doesn't match any site, we 404 immediately so we never
    serve admin-shaped responses against a stranger's host.
  """
  alias Ledger.Sites
  alias LedgerWeb.SiteNotFound

  def init(opts), do: opts

  def call(conn, _opts) do
    case extract_subdomain(conn.host) do
      nil ->
        conn

      slug ->
        case Sites.get_site_by_slug(slug) do
          nil -> SiteNotFound.send(conn)
          site -> Plug.Conn.assign(conn, :current_site, site)
        end
    end
  end

  defp extract_subdomain(host) when is_binary(host) do
    hosts = app_hosts()

    cond do
      host in hosts ->
        nil

      true ->
        # `foo.lvh.me` -> "foo"; `bar.baz.ledger.local` -> "bar.baz" (we treat
        # everything left of the registered host as the subdomain).
        app_host = Enum.find(hosts, &String.ends_with?(host, "." <> &1))

        if app_host do
          host
          |> String.replace_suffix("." <> app_host, "")
          |> case do
            ^host -> nil
            "" -> nil
            sub -> sub
          end
        else
          nil
        end
    end
  end

  defp extract_subdomain(_), do: nil

  defp app_hosts do
    Application.get_env(:ledger, :app_hosts, ~w(ledger.local lvh.me localhost 127.0.0.1))
  end
end
