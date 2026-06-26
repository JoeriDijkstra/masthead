defmodule Masthead.Content.ChangesetHelpers do
  @moduledoc """
  Small `Ecto.Changeset` helpers shared by the content schemas (posts, pages,
  tags). Extracted so slug derivation lives in one place instead of being
  copy-pasted into each schema's changeset.
  """
  import Ecto.Changeset

  alias Masthead.Themes.Sandbox

  @doc """
  Validate that an `html`-format body is parseable Liquid (html bodies are
  rendered through the theme sandbox at request time, so a broken template
  would 500 the public page).

  If the body fails to parse as-is but parses once HTML-unescaped, it was
  entity-escaped in transit (a browser `<textarea>` round-trip can turn `"`
  into `&quot;`) — self-heal by storing the unescaped version. Only genuine
  syntax errors, which survive unescaping, are surfaced to the author. A
  non-html format is left untouched.
  """
  def validate_liquid_body(changeset, format_field \\ :format) do
    if get_field(changeset, format_field) == "html" do
      body = get_field(changeset, :body) || ""

      case Sandbox.parse(body) do
        {:ok, _} ->
          changeset

        {:error, _} ->
          unescaped = Sandbox.html_unescape(body)

          case Sandbox.parse(unescaped) do
            {:ok, _} -> put_change(changeset, :body, unescaped)
            {:error, err} -> add_error(changeset, :body, "Liquid error: " <> liquid_error(err))
          end
      end
    else
      changeset
    end
  end

  defp liquid_error(%{message: message}) when is_binary(message), do: message
  defp liquid_error(err), do: inspect(err)

  @doc """
  Ensure the changeset carries a URL-safe `:slug`.

  If `:slug` is present, slugify it; otherwise derive one from `source_field`
  (e.g. `:title` for posts/pages, `:name` for tags). When neither is set, leave
  the changeset untouched so the schema's `validate_required`/`validate_format`
  surface the error.
  """
  def ensure_slug(changeset, source_field) do
    case get_field(changeset, :slug) do
      slug when is_binary(slug) and slug != "" ->
        put_change(changeset, :slug, Slug.slugify(slug))

      _ ->
        case get_field(changeset, source_field) do
          source when is_binary(source) and source != "" ->
            put_change(changeset, :slug, Slug.slugify(source))

          _ ->
            changeset
        end
    end
  end
end
