defmodule Masthead.Themes.Manifest do
  @moduledoc """
  Parses and validates a theme's `manifest.json`.

  A manifest declares the theme's identity (name, slug, version, author,
  description) and the customisable tokens it exposes to site owners.

      {
        "name": "Studio",
        "slug": "studio",
        "version": "1.0.0",
        "author": "Masthead",
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
    * `file`   — a picker over the site's existing uploads; the stored
      value is the chosen upload's **id**, resolved to a public URL at
      render time (see `Masthead.Themes.Renderer`). Useful for favicons,
      header images, logos, etc. Default should be `""` (no file).
    * `select` — a `<select>` over a fixed `options` list (required);
      value is the chosen option string. Use for layout switches like
      contained vs. full-width.
    * `boolean` — a checkbox. The value reaches templates as a real
      boolean (default is a JSON `true`/`false`), so themes can branch with
      `{% if theme.tokens.show_search %}`. Use for on/off feature toggles.
  """

  @valid_token_types ~w(color string length number file select boolean)
  @valid_metadata_types ~w(string text boolean color url select number)

  @slug_re ~r/^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$/
  @token_key_re ~r/^[a-z][a-z0-9_]*$/

  @enforce_keys [:name, :slug, :version, :tokens]
  defstruct [
    :name,
    :slug,
    :version,
    :author,
    :description,
    tokens: [],
    metadata: []
  ]

  @type token :: %{
          key: String.t(),
          label: String.t(),
          type: String.t(),
          default: String.t() | boolean(),
          options: [String.t()] | nil,
          category: String.t() | nil
        }

  @type metadata_field :: %{
          key: String.t(),
          label: String.t(),
          type: String.t(),
          default: term(),
          description: String.t() | nil,
          options: [String.t()] | nil
        }

  @type t :: %__MODULE__{
          name: String.t(),
          slug: String.t(),
          version: String.t(),
          author: String.t() | nil,
          description: String.t() | nil,
          tokens: [token()],
          metadata: [metadata_field()]
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
      |> validate_metadata(map)

    case errors do
      [] ->
        manifest = %__MODULE__{
          name: map["name"],
          slug: map["slug"],
          version: map["version"],
          author: map["author"],
          description: map["description"],
          tokens: normalize_tokens(Map.get(map, "tokens", [])),
          metadata: normalize_metadata(Map.get(map, "metadata", []))
        }

        {:ok, manifest}

      errs ->
        {:error, Enum.reverse(errs)}
    end
  end

  @doc """
  Return the merge of manifest token defaults with a map of per-site
  override values. Unknown override keys are dropped. Values are strings
  (interpolated directly into CSS) except `boolean` tokens, which are coerced
  to real booleans for template branching.
  """
  @spec effective_tokens(t(), map()) :: %{String.t() => String.t() | boolean()}
  def effective_tokens(%__MODULE__{tokens: tokens}, overrides) when is_map(overrides) do
    Enum.reduce(tokens, %{}, fn %{key: key, type: type, default: default}, acc ->
      raw =
        case Map.get(overrides, key) do
          v when is_binary(v) and v != "" -> v
          _ -> default
        end

      Map.put(acc, key, coerce_token_value(type, raw))
    end)
  end

  # Tokens are interpolated into CSS as strings, except `boolean` tokens which
  # are coerced to real booleans so templates can branch on them with
  # `{% if theme.tokens.show_search %}` (a non-empty string is truthy in
  # Liquid, so "false" would otherwise read as true).
  defp coerce_token_value("boolean", v) when is_boolean(v), do: v
  defp coerce_token_value("boolean", v) when v in ["true", "on", "1", 1], do: true
  defp coerce_token_value("boolean", _), do: false
  defp coerce_token_value(_type, v), do: v

  @doc """
  Return the merge of manifest metadata defaults with per-page overrides.

  Differences from `effective_tokens/2`:

    * Unknown override keys are **preserved** — the page may have been
      authored under a different theme. Tokens disappear silently because
      they're inert without a matching CSS variable; metadata is meant to
      survive theme switches so the user doesn't lose data.
    * Values are coerced to the declared type at the boundary so the
      template sees a typed value (boolean true vs. "true", etc).
  """
  @spec effective_metadata(t(), map()) :: %{String.t() => term()}
  def effective_metadata(%__MODULE__{metadata: fields}, overrides) when is_map(overrides) do
    defaults =
      Enum.reduce(fields, %{}, fn %{key: key, type: type, default: default}, acc ->
        Map.put(acc, key, coerce_metadata_value(type, default))
      end)

    # Apply overrides for declared fields (with coercion). Unknown keys are
    # passed through verbatim so theme-specific data is preserved across
    # theme changes.
    field_keys = Enum.map(fields, & &1.key) |> MapSet.new()

    Enum.reduce(overrides, defaults, fn {k, v}, acc ->
      if MapSet.member?(field_keys, k) do
        type = Enum.find_value(fields, fn f -> if f.key == k, do: f.type end)
        Map.put(acc, k, coerce_metadata_value(type, v))
      else
        Map.put(acc, k, v)
      end
    end)
  end

  defp coerce_metadata_value("boolean", v) when is_boolean(v), do: v
  defp coerce_metadata_value("boolean", v) when v in ["true", "on", "1", 1], do: true
  defp coerce_metadata_value("boolean", _), do: false
  defp coerce_metadata_value("number", v) when is_number(v), do: v

  defp coerce_metadata_value("number", v) when is_binary(v) do
    case Float.parse(v) do
      {n, ""} -> if n == trunc(n), do: trunc(n), else: n
      _ -> v
    end
  end

  defp coerce_metadata_value(_type, v), do: v

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

    type = Map.get(tok, "type")

    errors =
      cond do
        type not in @valid_token_types ->
          ["#{prefix}.type: must be one of #{Enum.join(@valid_token_types, ", ")}" | errors]

        type == "select" and not is_list(Map.get(tok, "options")) ->
          ["#{prefix}.options: select tokens require a non-empty options list" | errors]

        type == "select" and Map.get(tok, "options") == [] ->
          ["#{prefix}.options: select tokens require a non-empty options list" | errors]

        true ->
          errors
      end

    case {Map.get(tok, "type"), Map.get(tok, "default")} do
      {"boolean", d} when is_boolean(d) ->
        errors

      {_, d} when is_binary(d) ->
        errors

      _ ->
        [
          "#{prefix}.default: is required and must be a string (or boolean for boolean tokens)"
          | errors
        ]
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
        default: tok["default"],
        options: tok["options"],
        # Optional grouping label; tokens with a category render in an
        # accordion in the settings UI (uncategorized → "General").
        category: tok["category"]
      }
    end)
  end

  defp validate_metadata(errors, map) do
    case Map.get(map, "metadata", []) do
      list when is_list(list) ->
        list
        |> Enum.with_index()
        |> Enum.reduce(errors, fn {field, idx}, acc ->
          validate_metadata_field(acc, field, idx)
        end)

      _ ->
        ["metadata: must be a list" | errors]
    end
  end

  defp validate_metadata_field(errors, field, idx) when is_map(field) do
    prefix = "metadata[#{idx}]"

    errors =
      case Map.get(field, "key") do
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
      case Map.get(field, "label") do
        l when is_binary(l) and l != "" -> errors
        _ -> ["#{prefix}.label: is required and must be a non-empty string" | errors]
      end

    type = Map.get(field, "type")

    errors =
      cond do
        type not in @valid_metadata_types ->
          [
            "#{prefix}.type: must be one of #{Enum.join(@valid_metadata_types, ", ")}"
            | errors
          ]

        type == "select" and not is_list(Map.get(field, "options")) ->
          ["#{prefix}.options: select fields require a non-empty options list" | errors]

        type == "select" and Map.get(field, "options") == [] ->
          ["#{prefix}.options: select fields require a non-empty options list" | errors]

        true ->
          errors
      end

    # default is required but its allowed shape depends on the type — we
    # accept anything JSON-serializable and coerce at read time.
    case Map.has_key?(field, "default") do
      true -> errors
      false -> ["#{prefix}.default: is required" | errors]
    end
  end

  defp validate_metadata_field(errors, _, idx),
    do: ["metadata[#{idx}]: must be an object" | errors]

  defp normalize_metadata(list) when is_list(list) do
    Enum.map(list, fn field ->
      %{
        key: field["key"],
        label: field["label"],
        type: field["type"],
        default: field["default"],
        description: field["description"],
        options: field["options"]
      }
    end)
  end
end
