defmodule Ledger.Themes.Manifest do
  @moduledoc """
  Parses and validates a theme's `manifest.json`.

  A manifest declares the theme's identity (name, slug, version, author,
  description) and the customisable tokens it exposes to site owners.

      {
        "name": "Studio",
        "slug": "studio",
        "version": "1.0.0",
        "author": "Ledger",
        "description": "Editorial / blue accent.",
        "tokens": [
          {"key": "accent", "label": "Accent color", "type": "color", "default": "#2563eb"}
        ]
      }

  Token types control how the per-site customization UI renders the input:

    * `color`  — `<input type="color">`, value is a `#rrggbb` string
    * `string` — free-text input (e.g. font stack)
    * `length` — CSS length string (`880px`, `60ch`, `4rem`)
    * `number` — numeric input, stored as a string for CSS embedding
  """

  @valid_token_types ~w(color string length number)

  @slug_re ~r/^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$/
  @token_key_re ~r/^[a-z][a-z0-9_]*$/

  @enforce_keys [:name, :slug, :version, :tokens]
  defstruct [:name, :slug, :version, :author, :description, tokens: []]

  @type token :: %{
          key: String.t(),
          label: String.t(),
          type: String.t(),
          default: String.t()
        }

  @type t :: %__MODULE__{
          name: String.t(),
          slug: String.t(),
          version: String.t(),
          author: String.t() | nil,
          description: String.t() | nil,
          tokens: [token()]
        }

  @doc """
  Parse a manifest from a JSON-encoded binary. Returns
  `{:ok, %Manifest{}}` or `{:error, [reason, ...]}` with all validation
  failures collected.
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> from_map(map)
      {:ok, _} -> {:error, ["manifest must be a JSON object"]}
      {:error, %Jason.DecodeError{} = e} -> {:error, ["invalid JSON: " <> Exception.message(e)]}
    end
  end

  @doc """
  Build a manifest struct from an already-decoded map (used by tests and by
  the seed task that reads on-disk JSON via `Jason.decode!/1`).
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, [String.t()]}
  def from_map(map) when is_map(map) do
    errors =
      []
      |> require_string(map, "name", 1, 100)
      |> require_slug(map, "slug")
      |> require_string(map, "version", 1, 32)
      |> optional_string(map, "author", 0, 100)
      |> optional_string(map, "description", 0, 500)
      |> validate_tokens(map)

    case errors do
      [] ->
        manifest = %__MODULE__{
          name: map["name"],
          slug: map["slug"],
          version: map["version"],
          author: map["author"],
          description: map["description"],
          tokens: normalize_tokens(Map.get(map, "tokens", []))
        }

        {:ok, manifest}

      errs ->
        {:error, Enum.reverse(errs)}
    end
  end

  @doc """
  Return the merge of manifest token defaults with a map of per-site
  override values. Unknown override keys are dropped. Values are always
  strings — tokens are interpolated directly into CSS, so we never coerce
  to other types.
  """
  @spec effective_tokens(t(), map()) :: %{String.t() => String.t()}
  def effective_tokens(%__MODULE__{tokens: tokens}, overrides) when is_map(overrides) do
    Enum.reduce(tokens, %{}, fn %{key: key, default: default}, acc ->
      value =
        case Map.get(overrides, key) do
          v when is_binary(v) and v != "" -> v
          _ -> default
        end

      Map.put(acc, key, value)
    end)
  end

  # ---- internal validators ----

  defp require_string(errors, map, key, min, max) do
    case Map.get(map, key) do
      v when is_binary(v) ->
        len = String.length(v)

        cond do
          len < min -> ["#{key}: must be at least #{min} chars" | errors]
          len > max -> ["#{key}: must be at most #{max} chars" | errors]
          true -> errors
        end

      nil ->
        ["#{key}: is required" | errors]

      _ ->
        ["#{key}: must be a string" | errors]
    end
  end

  defp optional_string(errors, map, key, _min, max) do
    case Map.get(map, key) do
      nil ->
        errors

      v when is_binary(v) ->
        if String.length(v) > max do
          ["#{key}: must be at most #{max} chars" | errors]
        else
          errors
        end

      _ ->
        ["#{key}: must be a string" | errors]
    end
  end

  defp require_slug(errors, map, key) do
    case Map.get(map, key) do
      v when is_binary(v) ->
        if Regex.match?(@slug_re, v) do
          errors
        else
          ["#{key}: must be 1-32 chars, lowercase letters/digits/hyphens" | errors]
        end

      nil ->
        ["#{key}: is required" | errors]

      _ ->
        ["#{key}: must be a string" | errors]
    end
  end

  defp validate_tokens(errors, map) do
    case Map.get(map, "tokens", []) do
      list when is_list(list) ->
        list
        |> Enum.with_index()
        |> Enum.reduce(errors, fn {tok, idx}, acc -> validate_token(acc, tok, idx) end)

      _ ->
        ["tokens: must be a list" | errors]
    end
  end

  defp validate_token(errors, tok, idx) when is_map(tok) do
    prefix = "tokens[#{idx}]"

    errors =
      case Map.get(tok, "key") do
        k when is_binary(k) ->
          if Regex.match?(@token_key_re, k) do
            errors
          else
            ["#{prefix}.key: must match #{inspect(@token_key_re.source)}" | errors]
          end

        _ ->
          ["#{prefix}.key: is required and must be a string" | errors]
      end

    errors =
      case Map.get(tok, "label") do
        l when is_binary(l) and l != "" -> errors
        _ -> ["#{prefix}.label: is required and must be a non-empty string" | errors]
      end

    errors =
      case Map.get(tok, "type") do
        t when t in @valid_token_types ->
          errors

        _ ->
          ["#{prefix}.type: must be one of #{Enum.join(@valid_token_types, ", ")}" | errors]
      end

    case Map.get(tok, "default") do
      d when is_binary(d) -> errors
      _ -> ["#{prefix}.default: is required and must be a string" | errors]
    end
  end

  defp validate_token(errors, _, idx),
    do: ["tokens[#{idx}]: must be an object" | errors]

  defp normalize_tokens(list) when is_list(list) do
    Enum.map(list, fn tok ->
      %{
        key: tok["key"],
        label: tok["label"],
        type: tok["type"],
        default: tok["default"]
      }
    end)
  end
end
