defmodule LedgerWeb.SiteNotFound do
  @moduledoc """
  Renders the public "site not found" page. Used by
  `LedgerWeb.Plugs.Subdomain` when a request arrives on a subdomain that
  doesn't match any site row.

  Kept as a static HTML response (no LiveView, no controller) so it can
  be served straight from the plug before the router runs.
  """

  @doc "Sends the 404 page as an HTTP response."
  def send(conn) do
    body = render(conn)

    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(404, body)
    |> Plug.Conn.halt()
  end

  defp render(conn) do
    host = primary_host()
    requested = conn.host

    scheme =
      Application.get_env(:ledger, :site_url, [])
      |> Keyword.get(:scheme, "http")

    port =
      Application.get_env(:ledger, :site_url, [])
      |> Keyword.get(:port)

    home_url = build_url(scheme, host, port)

    """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Site not found · Ledger</title>
        <style>#{style()}</style>
      </head>
      <body>
        <main class="card">
          <img class="illustration" src="/images/illustrations/site-not-found.svg" alt="" />
          <p class="eyebrow">404</p>
          <h1>This site doesn't exist</h1>
          <p class="lede">
            We couldn't find a site at <code>#{Plug.HTML.html_escape(requested)}</code>.
            It may have been moved, renamed, or never created in the first place.
          </p>
          <a class="btn" href="#{Plug.HTML.html_escape(home_url)}">&larr; Back to Ledger</a>
        </main>
      </body>
    </html>
    """
  end

  defp primary_host do
    case Application.get_env(:ledger, :app_hosts, []) do
      [host | _] -> host
      _ -> "ledger-cloud.com"
    end
  end

  defp build_url(scheme, host, nil), do: "#{scheme}://#{host}"
  defp build_url("http", host, 80), do: "http://#{host}"
  defp build_url("https", host, 443), do: "https://#{host}"
  defp build_url(scheme, host, port), do: "#{scheme}://#{host}:#{port}"

  defp style do
    """
    *, *::before, *::after { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 2rem 1.5rem;
      font-family: -apple-system, BlinkMacSystemFont, "Inter", "Helvetica Neue", Arial, sans-serif;
      color: #0f172a;
      background: #f4f4f5;
      line-height: 1.55;
    }
    .card {
      background: #fff;
      border: 1px solid #e4e4e7;
      border-radius: 16px;
      box-shadow: 0 14px 34px -10px rgba(15, 23, 42, 0.12), 0 4px 12px -4px rgba(15, 23, 42, 0.06);
      padding: 3rem 2.5rem;
      text-align: center;
      max-width: 480px;
      width: 100%;
    }
    .illustration {
      width: 100%;
      max-width: 280px;
      height: auto;
      margin-bottom: 1.75rem;
      pointer-events: none;
      user-select: none;
    }
    .eyebrow {
      font-size: 0.78rem;
      font-weight: 600;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: #2563eb;
      margin: 0 0 0.6rem;
    }
    h1 {
      margin: 0 0 0.75rem;
      font-size: 1.5rem;
      letter-spacing: -0.02em;
      color: #0f172a;
    }
    .lede {
      color: #475569;
      margin: 0 0 2rem;
      font-size: 0.98rem;
    }
    .lede code {
      font-family: ui-monospace, "SF Mono", Menlo, monospace;
      font-size: 0.88em;
      background: #f1f5f9;
      padding: 0.1em 0.4em;
      border-radius: 4px;
    }
    .btn {
      display: inline-block;
      background: #2563eb;
      color: #fff;
      text-decoration: none;
      padding: 0.7rem 1.4rem;
      border-radius: 8px;
      font-weight: 500;
      font-size: 0.95rem;
      transition: background 0.15s ease, transform 0.1s ease, box-shadow 0.15s ease;
      box-shadow: 0 1px 2px rgba(37, 99, 235, 0.25);
    }
    .btn:hover {
      background: #1d4ed8;
      transform: translateY(-1px);
      box-shadow: 0 6px 16px rgba(37, 99, 235, 0.3);
    }
    @media (max-width: 480px) {
      .card { padding: 2rem 1.5rem; }
      h1 { font-size: 1.3rem; }
    }
    """
  end
end
