defmodule Ledger.CustomDomains.FlyClient do
  @moduledoc """
  Behaviour for talking to Fly.io's certificate API. The real adapter
  (`Http`) calls the Fly GraphQL endpoint; tests/dev use `Stub`.

  `add_certificate/1` registers a hostname on the Fly app so Fly will
  provision a Let's Encrypt cert for it.
  `get_certificate/1` returns `{:ok, %{ready?: boolean, status: string}}`.
  `delete_certificate/1` removes a hostname's cert from the Fly app.
  """
  @type cert_status :: %{ready?: boolean(), status: String.t()}

  @callback add_certificate(String.t()) :: :ok | {:error, term()}
  @callback get_certificate(String.t()) :: {:ok, cert_status()} | {:error, term()}
  @callback delete_certificate(String.t()) :: :ok | {:error, term()}
  @callback get_ips() :: {:ok, [String.t()]} | {:error, term()}

  def adapter do
    Application.get_env(
      :ledger,
      :fly_client,
      Ledger.CustomDomains.FlyClient.Http
    )
  end

  def add_certificate(domain), do: adapter().add_certificate(domain)
  def get_certificate(domain), do: adapter().get_certificate(domain)
  def delete_certificate(domain), do: adapter().delete_certificate(domain)
  def get_ips, do: adapter().get_ips()
end

defmodule Ledger.CustomDomains.FlyClient.Http do
  @moduledoc """
  Real Fly.io client. Talks to the Fly GraphQL API
  (`https://api.fly.io/graphql`). Requires:

    * `FLY_API_TOKEN` — a Fly API/deploy token
    * `FLY_APP_NAME`  — the app to attach certs to (e.g. `dijkstra-ledger`)
  """
  @behaviour Ledger.CustomDomains.FlyClient

  @endpoint "https://api.fly.io/graphql"

  @impl true
  def add_certificate(domain) do
    query = """
    mutation($appId: ID!, $hostname: String!) {
      addCertificate(appId: $appId, hostname: $hostname) {
        certificate { hostname }
      }
    }
    """

    case request(query, %{appId: app_name(), hostname: domain}) do
      {:ok, _data} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_certificate(domain) do
    query = """
    query($appName: String!, $hostname: String!) {
      app(name: $appName) {
        certificate(hostname: $hostname) {
          clientStatus
          acmeDnsConfigured
          acmeAlpnConfigured
        }
      }
    }
    """

    case request(query, %{appName: app_name(), hostname: domain}) do
      {:ok, %{"app" => %{"certificate" => nil}}} ->
        {:ok, %{ready?: false, status: "unknown"}}

      {:ok, %{"app" => %{"certificate" => cert}}} ->
        status = cert["clientStatus"] || "unknown"
        {:ok, %{ready?: status == "Ready", status: status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def delete_certificate(domain) do
    query = """
    mutation($appId: ID!, $hostname: String!) {
      deleteCertificate(appId: $appId, hostname: $hostname) {
        app { name }
      }
    }
    """

    case request(query, %{appId: app_name(), hostname: domain}) do
      {:ok, _data} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_ips do
    query = """
    query($appName: String!) {
      app(name: $appName) {
        ipAddresses { nodes { address } }
      }
    }
    """

    case request(query, %{appName: app_name()}) do
      {:ok, %{"app" => %{"ipAddresses" => %{"nodes" => nodes}}}} ->
        {:ok, Enum.map(nodes, & &1["address"])}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(query, variables) do
    body = Jason.encode!(%{query: query, variables: variables})

    headers = [
      {"Authorization", "Bearer #{token()}"},
      {"Content-Type", "application/json"}
    ]

    case :hackney.request(:post, @endpoint, headers, body, [:with_body, recv_timeout: 15_000]) do
      {:ok, status, _headers, resp} when status in 200..299 ->
        decode(resp)

      {:ok, status, _headers, resp} ->
        {:error, "Fly API HTTP #{status}: #{resp}"}

      {:error, reason} ->
        {:error, "Fly API request failed: #{inspect(reason)}"}
    end
  end

  defp decode(resp) do
    case Jason.decode(resp) do
      {:ok, %{"errors" => [%{"message" => msg} | _]}} -> {:error, msg}
      {:ok, %{"data" => data}} when not is_nil(data) -> {:ok, data}
      {:ok, other} -> {:error, "Unexpected Fly API response: #{inspect(other)}"}
      {:error, _} -> {:error, "Invalid JSON from Fly API"}
    end
  end

  defp token do
    System.get_env("FLY_API_TOKEN") ||
      raise "FLY_API_TOKEN is not set — cannot manage custom-domain certificates"
  end

  defp app_name do
    System.get_env("FLY_APP_NAME") ||
      raise "FLY_APP_NAME is not set — cannot manage custom-domain certificates"
  end
end

defmodule Ledger.CustomDomains.FlyClient.Stub do
  @moduledoc """
  Test/dev Fly client. Behaviour is driven by application env:

      config :ledger, :fly_stub, %{add: :ok, status: "Ready", delete: :ok}

  `status` is the `clientStatus` returned by `get_certificate/1`
  (`"Ready"` means the cert is issued).
  """
  @behaviour Ledger.CustomDomains.FlyClient

  @impl true
  def add_certificate(_domain), do: cfg(:add, :ok)

  @impl true
  def get_certificate(_domain) do
    status = cfg(:status, "Ready")
    {:ok, %{ready?: status == "Ready", status: status}}
  end

  @impl true
  def delete_certificate(_domain), do: cfg(:delete, :ok)

  @impl true
  def get_ips, do: {:ok, cfg(:ips, ["66.66.66.66", "2a09:8280::1"])}

  defp cfg(key, default) do
    :ledger
    |> Application.get_env(:fly_stub, %{})
    |> Map.get(key, default)
  end
end
