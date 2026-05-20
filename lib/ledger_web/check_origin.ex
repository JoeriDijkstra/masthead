defmodule LedgerWeb.CheckOrigin do
  @moduledoc """
  Dynamic `check_origin` for the endpoint. Allows the bare app host,
  any `*.app_host` subdomain, and any custom domain that is currently
  `active`. Without the custom-domain clause, LiveView websockets and
  CSRF-protected POSTs would be rejected on a site's own custom domain.

  Wired in `config/runtime.exs` as:

      check_origin: {LedgerWeb.CheckOrigin, :allowed?, [%{host: host, app_hosts: app_hosts}]}

  Phoenix invokes the MFA with the request origin `%URI{}` as the
  FIRST argument, followed by the configured args — so the URI comes
  before the config map here.
  """
  def allowed?(%URI{host: origin_host}, %{host: host, app_hosts: app_hosts})
      when is_binary(origin_host) do
    origin_host == host or
      Enum.any?(app_hosts, &String.ends_with?(origin_host, "." <> &1)) or
      active_custom_domain?(origin_host)
  end

  def allowed?(_uri, _config), do: false

  defp active_custom_domain?(origin_host) do
    origin_host in Ledger.Sites.list_active_custom_domains()
  end
end
