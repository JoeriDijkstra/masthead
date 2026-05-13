defmodule Ledger.Themes do
  @moduledoc """
  Theme registry.

  Themes are plain Elixir modules implementing the `Ledger.Themes.Theme`
  behaviour. New themes are registered by adding them to `@themes` below.
  There is intentionally no admin UI for editing themes — they live in code.
  """

  @themes %{
    "default" => Ledger.Themes.Default,
    "studio" => Ledger.Themes.Studio
  }

  def get(name) when is_binary(name) do
    Map.get(@themes, name, Ledger.Themes.Default)
  end

  def names, do: Map.keys(@themes)
end
