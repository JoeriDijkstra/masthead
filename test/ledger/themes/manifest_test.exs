defmodule Ledger.Themes.ManifestTest do
  use ExUnit.Case, async: true
  alias Ledger.Themes.Manifest

  describe "parse/1" do
    test "accepts a minimal valid manifest" do
      json = ~s({"name":"X","slug":"x","version":"1.0.0","tokens":[]})

      assert {:ok, %Manifest{name: "X", slug: "x", version: "1.0.0", tokens: []}} =
               Manifest.parse(json)
    end

    test "accepts tokens of every supported type" do
      json = """
      {"name":"X","slug":"x","version":"1.0.0","tokens":[
        {"key":"a","label":"A","type":"color","default":"#fff"},
        {"key":"b","label":"B","type":"string","default":"Inter"},
        {"key":"c","label":"C","type":"length","default":"4rem"},
        {"key":"d","label":"D","type":"number","default":"4"}
      ]}
      """

      assert {:ok, %Manifest{tokens: tokens}} = Manifest.parse(json)
      assert length(tokens) == 4
    end

    test "rejects invalid JSON" do
      assert {:error, [msg]} = Manifest.parse("not json")
      assert msg =~ "invalid JSON"
    end

    test "collects every validation failure" do
      json = ~s({"slug":"Bad Slug","tokens":[{"type":"weird"}]})
      {:error, errors} = Manifest.parse(json)
      assert Enum.any?(errors, &String.contains?(&1, "name"))
      assert Enum.any?(errors, &String.contains?(&1, "version"))
      assert Enum.any?(errors, &String.contains?(&1, "slug"))
      assert Enum.any?(errors, &String.contains?(&1, "tokens[0].key"))
      assert Enum.any?(errors, &String.contains?(&1, "tokens[0].type"))
    end
  end

  describe "effective_tokens/2" do
    setup do
      {:ok, m} =
        Manifest.parse(~s({
          "name":"X","slug":"x","version":"1.0.0",
          "tokens":[
            {"key":"accent","label":"Accent","type":"color","default":"#fff"},
            {"key":"width","label":"Width","type":"length","default":"800px"}
          ]
        }))

      {:ok, manifest: m}
    end

    test "falls back to manifest defaults when no overrides", %{manifest: m} do
      assert %{"accent" => "#fff", "width" => "800px"} = Manifest.effective_tokens(m, %{})
    end

    test "overrides win over defaults", %{manifest: m} do
      assert %{"accent" => "#000", "width" => "800px"} =
               Manifest.effective_tokens(m, %{"accent" => "#000"})
    end

    test "empty-string override falls back to default", %{manifest: m} do
      assert %{"accent" => "#fff"} = Manifest.effective_tokens(m, %{"accent" => ""})
    end

    test "unknown override keys are dropped", %{manifest: m} do
      out = Manifest.effective_tokens(m, %{"nope" => "x"})
      refute Map.has_key?(out, "nope")
    end
  end
end
