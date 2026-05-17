defmodule Ledger.CustomDomains do
  @moduledoc """
  Custom-domain lifecycle for a site.

      unconfigured → pending_dns → verified → cert_provisioning → active
                          ↑
                        failed ←── (any step, with last_error)

  - `set_domain/2`         — store + normalize a domain, generate the
                             ownership token, move to `pending_dns`.
  - `verify/1`             — confirm the TXT token and the CNAME
                             delegation, then request the cert.
  - `refresh_status/1`     — poll Fly; promote to `active` once issued.
  - `clear_domain/1`       — remove the Fly cert and reset to
                             `unconfigured`.

  DNS and Fly access go through swappable adapters
  (`Ledger.CustomDomains.DnsResolver`, `Ledger.CustomDomains.FlyClient`)
  so tests and dev never touch the network.
  """
  import Ecto.Changeset

  alias Ledger.Repo
  alias Ledger.Sites.Site
  alias Ledger.CustomDomains.{DnsResolver, FlyClient}

  @doc "Set or change the site's custom domain. Moves it to `pending_dns`."
  def set_domain(%Site{} = site, domain) do
    changeset = Site.custom_domain_changeset(site, %{"custom_domain" => domain})

    if changeset.valid? do
      changeset
      |> put_change(:custom_domain_status, "pending_dns")
      |> put_change(:custom_domain_token, generate_token())
      |> put_change(:custom_domain_verified_at, nil)
      |> put_change(:custom_domain_last_checked_at, nil)
      |> put_change(:custom_domain_last_error, nil)
      |> Repo.update()
    else
      {:error, %{changeset | action: :validate}}
    end
  end

  @doc """
  Verify ownership (TXT token) and delegation (CNAME → Fly edge). On
  success, transitions to `verified` and immediately requests the cert.
  """
  def verify(%Site{custom_domain: domain} = site) when is_binary(domain) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    with :ok <- check_txt(site),
         :ok <- check_cname(site) do
      site
      |> state_changeset(%{
        custom_domain_status: "verified",
        custom_domain_verified_at: now,
        custom_domain_last_checked_at: now,
        custom_domain_last_error: nil
      })
      |> Repo.update()
      |> case do
        {:ok, verified} -> request_certificate(verified)
        other -> other
      end
    else
      {:error, reason} ->
        fail(site, reason, now)
    end
  end

  def verify(%Site{} = site), do: {:error, "no custom domain set", site}

  @doc """
  Poll Fly for the certificate status and promote to `active` once the
  cert has been issued. Powers the manual "Refresh status" button.
  """
  def refresh_status(%Site{custom_domain: domain} = site) when is_binary(domain) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case FlyClient.get_certificate(domain) do
      {:ok, %{ready?: true}} ->
        site
        |> state_changeset(%{
          custom_domain_status: "active",
          custom_domain_last_checked_at: now,
          custom_domain_last_error: nil
        })
        |> Repo.update()

      {:ok, %{ready?: false, status: status}} ->
        site
        |> state_changeset(%{
          custom_domain_status: "cert_provisioning",
          custom_domain_last_checked_at: now,
          custom_domain_last_error: "Certificate not ready yet (Fly status: #{status})"
        })
        |> Repo.update()

      {:error, reason} ->
        fail(site, "Fly certificate check failed: #{inspect(reason)}", now)
    end
  end

  def refresh_status(%Site{} = site), do: {:error, "no custom domain set", site}

  @doc "Remove the Fly cert (best effort) and reset to `unconfigured`."
  def clear_domain(%Site{custom_domain: domain} = site) do
    if is_binary(domain), do: FlyClient.delete_certificate(domain)

    site
    |> state_changeset(%{
      custom_domain: nil,
      custom_domain_status: "unconfigured",
      custom_domain_token: nil,
      custom_domain_verified_at: nil,
      custom_domain_last_checked_at: nil,
      custom_domain_last_error: nil
    })
    |> Repo.update()
  end

  @doc """
  The DNS records the user must create, for display in the admin UI.
  """
  def dns_instructions(%Site{custom_domain: domain, custom_domain_token: token})
      when is_binary(domain) do
    %{
      cname: %{type: "CNAME", name: domain, value: cname_target()},
      txt: %{type: "TXT", name: "#{txt_prefix()}.#{domain}", value: token}
    }
  end

  def dns_instructions(_site), do: nil

  # --- internals ---------------------------------------------------------

  defp request_certificate(%Site{custom_domain: domain} = site) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case FlyClient.add_certificate(domain) do
      :ok ->
        site
        |> state_changeset(%{
          custom_domain_status: "cert_provisioning",
          custom_domain_last_checked_at: now,
          custom_domain_last_error: nil
        })
        |> Repo.update()

      {:error, reason} ->
        fail(site, "Fly certificate request failed: #{inspect(reason)}", now)
    end
  end

  defp check_txt(%Site{custom_domain: domain, custom_domain_token: token}) do
    name = "#{txt_prefix()}.#{domain}"

    if token in DnsResolver.lookup_txt(name) do
      :ok
    else
      {:error, "TXT record #{name} not found or does not match the verification token"}
    end
  end

  defp check_cname(%Site{custom_domain: domain}) do
    target = cname_target()

    if target in DnsResolver.lookup_cname(domain) do
      :ok
    else
      {:error, "CNAME for #{domain} does not point at #{target}"}
    end
  end

  defp fail(site, reason, now) do
    {:ok, updated} =
      site
      |> state_changeset(%{
        custom_domain_status: "failed",
        custom_domain_last_checked_at: now,
        custom_domain_last_error: reason
      })
      |> Repo.update()

    {:error, reason, updated}
  end

  defp state_changeset(site, attrs), do: Site.custom_domain_state_changeset(site, attrs)

  defp generate_token do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp cname_target do
    Application.get_env(:ledger, :custom_domain, [])
    |> Keyword.get(:cname_target, "dijkstra-ledger.fly.dev")
  end

  defp txt_prefix do
    Application.get_env(:ledger, :custom_domain, [])
    |> Keyword.get(:txt_prefix, "_ledger-verify")
  end
end
