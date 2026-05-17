defmodule LedgerWeb.CustomDomainRoutingTest do
  use Ledger.DataCase

  import Plug.Test, only: [conn: 3]

  alias Ledger.{Accounts, Sites, CustomDomains}
  alias LedgerWeb.{Plugs, CheckOrigin}

  setup do
    Ledger.Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "route-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "route#{System.unique_integer([:positive])}",
        "name" => "Route Test",
        "owner_id" => user.id
      })

    %{site: site}
  end

  defp activate(site, domain) do
    {:ok, site} = CustomDomains.set_domain(site, domain)

    {:ok, site} =
      site
      |> Ledger.Sites.Site.custom_domain_state_changeset(%{custom_domain_status: "active"})
      |> Ledger.Repo.update()

    site
  end

  describe "Subdomain plug custom-domain fallback" do
    test "resolves an active custom domain to its site", %{site: site} do
      site = activate(site, "blog.example.com")

      conn =
        conn(:get, "/", "")
        |> Map.put(:host, "blog.example.com")
        |> Plugs.Subdomain.call([])

      assert conn.assigns[:current_site].id == site.id
    end

    test "does not resolve a non-active custom domain", %{site: site} do
      {:ok, _site} = CustomDomains.set_domain(site, "blog.example.com")

      conn =
        conn(:get, "/", "")
        |> Map.put(:host, "blog.example.com")
        |> Plugs.Subdomain.call([])

      refute conn.assigns[:current_site]
      refute conn.halted
    end
  end

  describe "CheckOrigin.allowed?/2" do
    @config %{host: "ledger-cloud.com", app_hosts: ["ledger-cloud.com"]}

    test "allows the bare app host and its subdomains" do
      assert CheckOrigin.allowed?(@config, URI.parse("https://ledger-cloud.com"))
      assert CheckOrigin.allowed?(@config, URI.parse("https://acme.ledger-cloud.com"))
    end

    test "rejects an unknown foreign host" do
      refute CheckOrigin.allowed?(@config, URI.parse("https://evil.example.com"))
    end

    test "allows an active custom domain", %{site: site} do
      activate(site, "blog.example.com")
      assert CheckOrigin.allowed?(@config, URI.parse("https://blog.example.com"))
    end
  end
end
