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
  import Plug.Conn
  alias Ledger.Sites

  @app_hosts ~w(ledger.local lvh.me localhost 127.0.0.1)

  def init(opts), do: opts

  def call(conn, _opts) do
    case extract_subdomain(conn.host) do
      nil ->
        conn

      slug ->
        case Sites.get_site_by_slug(slug) do
          nil ->
            conn
            |> send_resp(404, "site not found")
            |> halt()

          site ->
            assign(conn, :current_site, site)
        end
    end
  end

  defp extract_subdomain(host) when is_binary(host) do
    cond do
      host in @app_hosts ->
        nil

      true ->
        # `foo.lvh.me` -> "foo"; `bar.baz.ledger.local` -> "bar.baz" (we treat
        # everything left of the registered host as the subdomain).
        app_host = matching_app_host(host)

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

  defp matching_app_host(host) do
    Enum.find(@app_hosts, fn h -> String.ends_with?(host, "." <> h) end)
  end
end
