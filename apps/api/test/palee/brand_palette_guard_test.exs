defmodule Palee.BrandPaletteGuardTest do
  use ExUnit.Case, async: true

  # Every colour the API renders (emails, receipts, wallet passes) comes from
  # Palee.BrandPalette, which is generated from the web theme
  # (docs/brand/THEME.md). This fails on any colour literal anywhere else.

  @generated "lib/palee/brand_palette.ex"
  @patterns [
    {"hex colour", ~r/(?<![\w&])#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3})(?![\w-])/},
    {"rgb/hsl colour", ~r/\b(?:rgba?|hsla?)\(\s*\d/}
  ]

  test "no colour literal outside Palee.BrandPalette" do
    offences =
      for file <- Path.wildcard("lib/**/*.{ex,heex,eex}"),
          file != @generated,
          {line, number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          not String.starts_with?(String.trim_leading(line), "#"),
          {name, pattern} <- @patterns,
          match <- Regex.scan(pattern, line),
          do: "#{file}:#{number} #{name} #{hd(match)}"

    assert offences == []
  end
end
