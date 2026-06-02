defmodule Masthead.CustomDomains.DnsResolver do
  @moduledoc """
  Behaviour for the DNS lookups used to verify domain ownership and
  delegation. The real adapter (`Inet`) uses Erlang's built-in
  `:inet_res`; tests/dev use `Stub`.

  `lookup_txt/1` returns the list of TXT record strings for a name.
  `lookup_cname/1` returns the list of CNAME targets (lowercased, no
  trailing dot) for a name — usually zero or one entries.
  """
  @callback lookup_txt(String.t()) :: [String.t()]
  @callback lookup_cname(String.t()) :: [String.t()]
  @callback lookup_a(String.t()) :: [String.t()]
  @callback lookup_aaaa(String.t()) :: [String.t()]

  def adapter do
    Application.get_env(
      :masthead,
      :dns_resolver,
      Masthead.CustomDomains.DnsResolver.Inet
    )
  end

  def lookup_txt(name), do: adapter().lookup_txt(name)
  def lookup_cname(name), do: adapter().lookup_cname(name)
  def lookup_a(name), do: adapter().lookup_a(name)
  def lookup_aaaa(name), do: adapter().lookup_aaaa(name)
end

defmodule Masthead.CustomDomains.DnsResolver.Inet do
  @moduledoc "Real DNS resolver backed by Erlang `:inet_res`."
  @behaviour Masthead.CustomDomains.DnsResolver

  @impl true
  def lookup_txt(name) do
    name
    |> to_charlist()
    |> :inet_res.lookup(:in, :txt)
    |> Enum.map(fn parts -> parts |> Enum.map(&to_string/1) |> Enum.join("") end)
  rescue
    _ -> []
  end

  @impl true
  def lookup_cname(name) do
    name
    |> to_charlist()
    |> :inet_res.lookup(:in, :cname)
    |> Enum.map(fn target ->
      target |> to_string() |> String.downcase() |> String.trim_trailing(".")
    end)
  rescue
    _ -> []
  end

  @impl true
  def lookup_a(name), do: lookup_ip(name, :a)

  @impl true
  def lookup_aaaa(name), do: lookup_ip(name, :aaaa)

  defp lookup_ip(name, type) do
    name
    |> to_charlist()
    |> :inet_res.lookup(:in, type)
    |> Enum.map(fn addr -> addr |> :inet.ntoa() |> to_string() end)
  rescue
    _ -> []
  end
end

defmodule Masthead.CustomDomains.DnsResolver.Stub do
  @moduledoc """
  Test/dev DNS resolver. Reads canned answers from application env:

      config :masthead, :dns_stub, %{
        txt: %{"_masthead-verify.blog.example.com" => ["token123"]},
        cname: %{"blog.example.com" => ["dijkstra-masthead.fly.dev"]}
      }
  """
  @behaviour Masthead.CustomDomains.DnsResolver

  @impl true
  def lookup_txt(name), do: get(:txt, name)

  @impl true
  def lookup_cname(name), do: get(:cname, name)

  @impl true
  def lookup_a(name), do: get(:a, name)

  @impl true
  def lookup_aaaa(name), do: get(:aaaa, name)

  defp get(kind, name) do
    :masthead
    |> Application.get_env(:dns_stub, %{})
    |> Map.get(kind, %{})
    |> Map.get(name, [])
  end
end
