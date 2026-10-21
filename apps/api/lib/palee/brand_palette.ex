defmodule Palee.BrandPalette do
  @moduledoc """
  The Palee print colours for emails and documents the API renders.

  Generated from apps/web/src/lib/theme.ts by `npm run theme:native`; do not edit.
  """

  @colours %{
    paper: "#FFFFFF",
    bg: "#F4F5F7",
    text: "#17181C",
    text_soft: "#3A3D45",
    muted: "#5E6470",
    border: "#DFE2E8",
    primary: "#2F5BFF",
    primary_contrast: "#FFFFFF"
  }

  @doc "A print colour by its theme token name, e.g. `colour(:primary)`."
  def colour(token), do: Map.fetch!(@colours, token)
end
