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

  describe "metadata schema parsing" do
    test "accepts all supported field types" do
      json = """
      {"name":"X","slug":"x","version":"1.0.0","tokens":[],
       "metadata":[
         {"key":"s","label":"S","type":"string","default":""},
         {"key":"t","label":"T","type":"text","default":""},
         {"key":"b","label":"B","type":"boolean","default":false},
         {"key":"c","label":"C","type":"color","default":"#fff"},
         {"key":"u","label":"U","type":"url","default":""},
         {"key":"n","label":"N","type":"number","default":0},
         {"key":"sel","label":"Sel","type":"select","options":["a","b"],"default":"a"}
       ]}
      """

      assert {:ok, %Manifest{metadata: fields}} = Manifest.parse(json)
      assert length(fields) == 7
    end

    test "select fields require a non-empty options list" do
      json = ~s({"name":"X","slug":"x","version":"1.0.0","tokens":[],
                 "metadata":[{"key":"sel","label":"S","type":"select","default":"a"}]})

      assert {:error, errs} = Manifest.parse(json)
      assert Enum.any?(errs, &String.contains?(&1, "options"))
    end

    test "default is required for every field" do
      json = ~s({"name":"X","slug":"x","version":"1.0.0","tokens":[],
                 "metadata":[{"key":"k","label":"K","type":"string"}]})

      assert {:error, errs} = Manifest.parse(json)
      assert Enum.any?(errs, &String.contains?(&1, "default"))
    end

    test "unknown type is rejected" do
      json = ~s({"name":"X","slug":"x","version":"1.0.0","tokens":[],
                 "metadata":[{"key":"k","label":"K","type":"weird","default":""}]})

      assert {:error, errs} = Manifest.parse(json)
      assert Enum.any?(errs, &String.contains?(&1, "type:"))
    end

    test "missing metadata key is fine (defaults to empty list)" do
      json = ~s({"name":"X","slug":"x","version":"1.0.0","tokens":[]})
      assert {:ok, %Manifest{metadata: []}} = Manifest.parse(json)
    end
  end

  describe "effective_metadata/2" do
    setup do
      {:ok, m} =
        Manifest.parse(~s({
          "name":"X","slug":"x","version":"1.0.0","tokens":[],
          "metadata":[
            {"key":"layout","label":"L","type":"select","options":["a","b"],"default":"a"},
            {"key":"hero","label":"H","type":"url","default":""},
            {"key":"hide","label":"D","type":"boolean","default":false},
            {"key":"count","label":"C","type":"number","default":0}
          ]
        }))

      {:ok, manifest: m}
    end

    test "falls back to declared defaults", %{manifest: m} do
      assert %{
               "layout" => "a",
               "hero" => "",
               "hide" => false,
               "count" => 0
             } = Manifest.effective_metadata(m, %{})
    end

    test "overrides win", %{manifest: m} do
      assert %{"layout" => "b", "hero" => "/x.jpg"} =
               Manifest.effective_metadata(m, %{"layout" => "b", "hero" => "/x.jpg"})
    end

    test "booleans coerce from form strings", %{manifest: m} do
      assert %{"hide" => true} = Manifest.effective_metadata(m, %{"hide" => "true"})
      assert %{"hide" => false} = Manifest.effective_metadata(m, %{"hide" => "false"})
    end

    test "numbers coerce from form strings", %{manifest: m} do
      assert %{"count" => 42} = Manifest.effective_metadata(m, %{"count" => "42"})
      assert %{"count" => 3.5} = Manifest.effective_metadata(m, %{"count" => "3.5"})
    end

    test "unknown override keys are preserved (theme-switch resilience)", %{manifest: m} do
      out = Manifest.effective_metadata(m, %{"from_old_theme" => "still here"})
      assert out["from_old_theme"] == "still here"
    end
  end
end
