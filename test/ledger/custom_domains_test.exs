defmodule Ledger.CustomDomainsTest do
  use Ledger.DataCase

  alias Ledger.{Accounts, Sites, CustomDomains}

  @cname_target "dijkstra-ledger.fly.dev"

  setup do
    Ledger.Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "cd-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "cd#{System.unique_integer([:positive])}",
        "name" => "CD Test",
        "owner_id" => user.id
      })

    on_exit(fn ->
      Application.delete_env(:ledger, :dns_stub)
      Application.delete_env(:ledger, :fly_stub)
    end)

    %{site: site}
  end

  defp put_dns(domain, token) do
    Application.put_env(:ledger, :dns_stub, %{
      txt: %{"_ledger-verify.#{domain}" => [token]},
      cname: %{domain => [@cname_target]}
    })
  end

  defp put_apex_dns(domain, token, ips) do
    Application.put_env(:ledger, :dns_stub, %{
      txt: %{"_ledger-verify.#{domain}" => [token]},
      a: %{domain => ips}
    })

    Application.put_env(:ledger, :fly_stub, %{add: :ok, ips: ips})
  end

  describe "set_domain/2" do
    test "normalizes input and moves to pending_dns with a token", %{site: site} do
      assert {:ok, site} = CustomDomains.set_domain(site, "  HTTPS://Blog.Example.com/path  ")
      assert site.custom_domain == "blog.example.com"
      assert site.custom_domain_status == "pending_dns"
      assert is_binary(site.custom_domain_token) and byte_size(site.custom_domain_token) > 0
    end

    test "accepts apex domains", %{site: site} do
      assert {:ok, site} = CustomDomains.set_domain(site, "example.com")
      assert site.custom_domain == "example.com"
      assert site.custom_domain_status == "pending_dns"
    end

    test "rejects a platform host", %{site: site} do
      assert {:error, changeset} = CustomDomains.set_domain(site, "foo.lvh.me")
      assert %{custom_domain: [_ | _]} = errors_on(changeset)
    end
  end

  describe "verify/1" do
    test "fails and records error when TXT token is missing", %{site: site} do
      {:ok, site} = CustomDomains.set_domain(site, "blog.example.com")
      Application.put_env(:ledger, :dns_stub, %{cname: %{"blog.example.com" => [@cname_target]}})

      assert {:error, reason, site} = CustomDomains.verify(site)
      assert reason =~ "TXT"
      assert site.custom_domain_status == "failed"
      assert site.custom_domain_last_error =~ "TXT"
    end

    test "fails when CNAME does not point at the edge", %{site: site} do
      {:ok, site} = CustomDomains.set_domain(site, "blog.example.com")

      Application.put_env(:ledger, :dns_stub, %{
        txt: %{"_ledger-verify.blog.example.com" => [site.custom_domain_token]},
        cname: %{"blog.example.com" => ["wrong.example.net"]}
      })

      assert {:error, reason, site} = CustomDomains.verify(site)
      assert reason =~ "CNAME"
      assert site.custom_domain_status == "failed"
    end

    test "verifies and requests a certificate when DNS is correct", %{site: site} do
      {:ok, site} = CustomDomains.set_domain(site, "blog.example.com")
      put_dns("blog.example.com", site.custom_domain_token)
      Application.put_env(:ledger, :fly_stub, %{add: :ok, status: "Awaiting configuration"})

      assert {:ok, site} = CustomDomains.verify(site)
      assert site.custom_domain_status == "cert_provisioning"
      assert is_nil(site.custom_domain_last_error)
      refute is_nil(site.custom_domain_verified_at)
    end

    test "verifies an apex domain via A records pointing at Fly IPs", %{site: site} do
      {:ok, site} = CustomDomains.set_domain(site, "example.com")
      put_apex_dns("example.com", site.custom_domain_token, ["66.66.66.66"])

      assert {:ok, site} = CustomDomains.verify(site)
      assert site.custom_domain_status == "cert_provisioning"
    end

    test "fails an apex domain whose A records point elsewhere", %{site: site} do
      {:ok, site} = CustomDomains.set_domain(site, "example.com")

      Application.put_env(:ledger, :dns_stub, %{
        txt: %{"_ledger-verify.example.com" => [site.custom_domain_token]},
        a: %{"example.com" => ["9.9.9.9"]}
      })

      Application.put_env(:ledger, :fly_stub, %{ips: ["66.66.66.66"]})

      assert {:error, reason, site} = CustomDomains.verify(site)
      assert reason =~ "delegated"
      assert site.custom_domain_status == "failed"
    end
  end

  describe "refresh_status/1" do
    setup %{site: site} do
      {:ok, site} = CustomDomains.set_domain(site, "blog.example.com")
      put_dns("blog.example.com", site.custom_domain_token)
      {:ok, site} = CustomDomains.verify(site)
      %{site: site}
    end

    test "promotes to active once Fly reports the cert ready", %{site: site} do
      Application.put_env(:ledger, :fly_stub, %{status: "Ready"})
      assert {:ok, site} = CustomDomains.refresh_status(site)
      assert site.custom_domain_status == "active"
    end

    test "stays provisioning while the cert is not ready", %{site: site} do
      Application.put_env(:ledger, :fly_stub, %{status: "Awaiting certificate"})
      assert {:ok, site} = CustomDomains.refresh_status(site)
      assert site.custom_domain_status == "cert_provisioning"
    end
  end

  describe "FlyClient.Http without credentials" do
    alias Ledger.CustomDomains.FlyClient.Http

    test "returns an error tuple instead of raising" do
      # FLY_API_TOKEN / FLY_APP_NAME are unset in test — the adapter
      # must degrade gracefully, never raise (which used to crash the
      # whole LiveView via fly_ips/0).
      assert {:error, msg} = Http.get_ips()
      assert msg =~ "FLY_"
      assert {:error, _} = Http.add_certificate("blog.example.com")
      assert {:error, _} = Http.get_certificate("blog.example.com")
      assert {:error, _} = Http.delete_certificate("blog.example.com")
    end

    test "CustomDomains.fly_ips/0 always returns a list, never raises" do
      assert is_list(CustomDomains.fly_ips())
    end
  end

  describe "clear_domain/1 and lookup" do
    test "resets all custom-domain fields", %{site: site} do
      {:ok, site} = CustomDomains.set_domain(site, "blog.example.com")
      assert {:ok, site} = CustomDomains.clear_domain(site)
      assert site.custom_domain == nil
      assert site.custom_domain_status == "unconfigured"
      assert site.custom_domain_token == nil
    end

    test "get_site_by_custom_domain only resolves active domains", %{site: site} do
      {:ok, site} = CustomDomains.set_domain(site, "blog.example.com")
      put_dns("blog.example.com", site.custom_domain_token)
      {:ok, site} = CustomDomains.verify(site)

      refute Sites.get_site_by_custom_domain("blog.example.com")

      Application.put_env(:ledger, :fly_stub, %{status: "Ready"})
      {:ok, _site} = CustomDomains.refresh_status(site)

      assert %{id: id} = Sites.get_site_by_custom_domain("blog.example.com")
      assert id == site.id
      assert "blog.example.com" in Sites.list_active_custom_domains()
    end
  end
end
