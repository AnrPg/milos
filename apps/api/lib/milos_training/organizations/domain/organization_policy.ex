defmodule MilosTraining.Organizations.Domain.OrganizationPolicy do
  @moduledoc false

  @statuses [:active, :suspended, :archived]
  @slug_length 3..63

  def statuses, do: @statuses

  def normalize_slug(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> :unicode.characters_to_nfkd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  def normalize_slug(_value), do: ""

  def valid_slug?(slug) when is_binary(slug) do
    String.length(slug) in @slug_length and
      Regex.match?(~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, slug)
  end

  def valid_slug?(_slug), do: false
end
