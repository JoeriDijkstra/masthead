defmodule Masthead.Themes.Filters do
  @moduledoc """
  Custom Liquid filters made available to every theme. Solid's
  `Solid.StandardFilter` set (`escape`, `default`, `date`, `size`, ...) is
  always loaded first; anything in this module takes precedence on name
  collision.

  Filters here must be pure and side-effect-free — they run inside the
  template sandbox and can't touch the database, the filesystem, or the
  request.
  """

  @doc """
  Build an asset URL given a theme's storage base and a relative file
  name:

      {{ 'logo.png' | asset_url: theme.asset_base }}
      # => "/uploads/themes/studio/1.0.0/assets/logo.png"

  Falls back to the bare filename if the base is missing (useful in tests).
  """
  def asset_url(filename, base) when is_binary(filename) and is_binary(base) do
    base
    |> String.trim_trailing("/")
    |> Kernel.<>("/")
    |> Kernel.<>(String.trim_leading(filename, "/"))
  end

  def asset_url(filename, _), do: filename

  @doc """
  Format a `DateTime` (or anything with `to_iso8601/1`) using
  `Calendar.strftime/2`. Solid ships a `date` filter but it's geared
  toward strings/Unix timestamps and trips on `%DateTime{}` structs.

      {{ post.published_at | strftime: "%B %-d, %Y" }}
  """
  def strftime(%DateTime{} = dt, format) when is_binary(format) do
    Calendar.strftime(dt, format)
  end

  def strftime(%NaiveDateTime{} = dt, format) when is_binary(format) do
    Calendar.strftime(dt, format)
  end

  def strftime(%Date{} = d, format) when is_binary(format) do
    Calendar.strftime(d, format)
  end

  def strftime(nil, _format), do: ""
  def strftime(other, _format), do: to_string(other)

  @doc """
  ISO-8601 string for use in `<time datetime="...">`. Defensive against
  nils so templates can do `{{ post.published_at | iso8601 }}`
  unconditionally.
  """
  def iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def iso8601(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  def iso8601(%Date{} = d), do: Date.to_iso8601(d)
  def iso8601(nil), do: ""
  def iso8601(other), do: to_string(other)
end
