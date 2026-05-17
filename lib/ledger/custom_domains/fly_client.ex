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

    with {:ok, token, app} <- credentials(),
         {:ok, _data} <- request(token, query, %{appId: app, hostname: domain}) do
      :ok
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

    with {:ok, token, app} <- credentials(),
         {:ok, data} <- request(token, query, %{appName: app, hostname: domain}) do
      case data do
        %{"app" => %{"certificate" => nil}} ->
          {:ok, %{ready?: false, status: "unknown"}}

        %{"app" => %{"certificate" => cert}} ->
          status = cert["clientStatus"] || "unknown"
          {:ok, %{ready?: status == "Ready", status: status}}

        _ ->
          {:ok, %{ready?: false, status: "unknown"}}
      end
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

    with {:ok, token, app} <- credentials(),
         {:ok, _data} <- request(token, query, %{appId: app, hostname: domain}) do
      :ok
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

    with {:ok, token, app} <- credentials(),
         {:ok, data} <- request(token, query, %{appName: app}) do
      case data do
        %{"app" => %{"ipAddresses" => %{"nodes" => nodes}}} ->
          {:ok, Enum.map(nodes, & &1["address"])}

        _ ->
          {:ok, []}
      end
    end
  end

  defp request(token, query, variables) do
    body = Jason.encode!(%{query: query, variables: variables})

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    case :hackney.request(:post, @endpoint, headers, body, [:with_body, recv_timeout: 15_000]) do
      {:ok, status, _headers, resp} when status in 200..299 ->
        decode(resp)

      {:ok, status, _headers, _resp} ->
        {:error, "certificate provider returned HTTP #{status}"}

      {:error, reason} ->
        {:error, "could not reach the certificate provider: #{inspect(reason)}"}
    end
  end

  defp decode(resp) do
    case Jason.decode(resp) do
      {:ok, %{"errors" => [%{"message" => msg} | _]}} ->
        {:error, msg}

      {:ok, %{"data" => data}} when not is_nil(data) ->
        {:ok, data}

      {:ok, other} ->
        {:error, "unexpected response from the certificate provider: #{inspect(other)}"}

      {:error, _} ->
        {:error, "invalid response from the certificate provider"}
    end
  end

  # Missing credentials is an expected state (dev, unconfigured prod) —
  # return an error tuple so callers degrade gracefully instead of the
  # whole LiveView crashing.
  defp credentials do
    case {System.get_env("FLY_API_TOKEN"), System.get_env("FLY_APP_NAME")} do
      {nil, _} ->
        {:error, "certificate management is not configured"}

      {_, nil} ->
        {:error, "certificate management is not configured"}

      {"", _} ->
        {:error, "certificate management is not configured"}

      {_, ""} ->
        {:error, "certificate management is not configured"}

      {token, app} ->
        {:ok, token, app}
    end
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
