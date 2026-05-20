defmodule Ledger.Themes.Sandbox do
  @moduledoc """
  Thin wrapper around `Solid` that pins parse/render to the configuration we
  consider safe for user-uploaded themes:

    * No file system — `{% include %}` and `{% render %}` (partials) are
      disabled in v1. If a template tries to use them, parsing fails with a
      clear error.
    * Custom filter allowlist via `Ledger.Themes.Filters`. Solid's
      standard filters (`escape`, `default`, `date`, ...) remain available.
    * Solid (and Liquid) **does not auto-escape**. Theme authors are
      expected to call `| escape` on user-supplied strings (`site.name`,
      `post.title`, ...). The renderer pre-sanitizes `body_html`, which is
      the one variable that intentionally emits raw HTML.
  """

  alias Solid.Template

  @doc """
  Parse a template string. Returns `{:ok, %Solid.Template{}}` or
  `{:error, reason}`.
  """
  @spec parse(String.t()) :: {:ok, Template.t()} | {:error, term()}
  def parse(source) when is_binary(source) do
    case Solid.parse(source) do
      {:ok, template} -> {:ok, template}
      {:error, %Solid.TemplateError{} = err} -> {:error, err}
      other -> {:error, other}
    end
  end

  @doc """
  Render a previously-parsed template against the given context.

  Returns `{:ok, iodata, errors}` where `errors` is a (usually empty) list
  of per-tag rendering errors. Solid is strict-by-default — unknown
  variables render as empty strings rather than raising.
  """
  @spec render(Template.t(), map()) :: {:ok, iodata(), list()} | {:error, term()}
  def render(%Template{} = template, context) when is_map(context) do
    Solid.render(template, context, custom_filters: Ledger.Themes.Filters)
  end

  @doc """
  Convenience: parse + render in one shot. Useful for tiny strings (e.g.
  inlining a token-substituted CSS snippet); production rendering should
  cache the parsed template.
  """
  @spec render_string(String.t(), map()) :: {:ok, iodata()} | {:error, term()}
  def render_string(source, context) do
    with {:ok, template} <- parse(source),
         {:ok, out, _errs} <- render(template, context) do
      {:ok, out}
    end
  end
end
