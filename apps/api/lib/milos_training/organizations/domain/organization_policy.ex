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
    # «Κυψέλη» → kypseli, «Παπαδόπουλος» → papadopoulos: a Greek or
    # Cyrillic name still gets a readable slug.
    |> String.replace("ου", "ou")
    |> MilosTraining.Transliteration.latin()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  def normalize_slug(_value), do: ""

  @doc """
  ADR-170: slugs to try, in order, for a self-serve organization named
  `name`: its own slug, then numbered ones, all valid. `fallback` stands in
  for a name with no Latin, Greek or Cyrillic letters.
  """
  def slug_candidates(name, fallback, count \\ 9) do
    base =
      case normalize_slug(name) do
        slug when byte_size(slug) >= 3 -> String.slice(slug, 0, 56) |> String.trim("-")
        _short -> fallback
      end

    [base | Enum.map(2..count, &"#{base}-#{&1}")]
  end

  def valid_slug?(slug) when is_binary(slug) do
    String.length(slug) in @slug_length and
      Regex.match?(~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, slug)
  end

  def valid_slug?(_slug), do: false
end
