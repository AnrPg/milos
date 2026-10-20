defmodule MilosTraining.Places.Domain.SearchKey do
  @moduledoc """
  How gazetteer names are matched (ADR-154): lower case, accents and
  diacritics dropped, final sigma folded, so «Κυψέλη», «κυψελη» and
  «ΚΥΨΕΛΗ» find the same place, as do Latin spellings.
  """

  def normalize(nil), do: ""

  def normalize(text) when is_binary(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace("ς", "σ")
    |> String.split()
    |> Enum.join(" ")
  end
end
