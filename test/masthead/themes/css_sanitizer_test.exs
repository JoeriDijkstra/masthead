defmodule Masthead.Themes.CssSanitizerTest do
  use ExUnit.Case, async: true
  alias Masthead.Themes.CssSanitizer

  describe "sanitize_overrides/1" do
    test "passes ordinary CSS through" do
      assert CssSanitizer.sanitize_overrides("body { color: red; }") =~ "color: red"
    end

    test "nil and empty are normalised" do
      assert CssSanitizer.sanitize_overrides(nil) == ""
      assert CssSanitizer.sanitize_overrides("") == ""
    end

    test "strips @import" do
      out = CssSanitizer.sanitize_overrides(~s(@import "http://evil/x.css"; body{}))
      refute out =~ "@import"
    end

    test "neuters javascript: urls" do
      out = CssSanitizer.sanitize_overrides("a { background: url(javascript:alert(1)); }")
      refute out =~ "javascript:"
    end

    test "removes </style> breakout attempts" do
      out = CssSanitizer.sanitize_overrides("body{} </style><script>alert(1)</script>")
      refute out =~ "</style>"
      refute out =~ "<script"
    end
  end

  describe "sanitize_token_value/1" do
    test "leaves a color literal intact" do
      assert CssSanitizer.sanitize_token_value("#ff0066") == "#ff0066"
    end

    test "leaves a font stack intact" do
      assert CssSanitizer.sanitize_token_value("Inter, sans-serif") == "Inter, sans-serif"
    end

    test "strips braces, semicolons, quotes, and newlines" do
      assert CssSanitizer.sanitize_token_value("red; } body { display: none") =~ "red"

      refute CssSanitizer.sanitize_token_value("red; } body { display: none") =~ "}"
      refute CssSanitizer.sanitize_token_value("red; } body { display: none") =~ ";"
    end

    test "nil → empty string" do
      assert CssSanitizer.sanitize_token_value(nil) == ""
    end
  end
end
