defmodule MilosTraining.Organizations.Domain.BoxProfilePolicy do
  @moduledoc """
  Rules of a gym's public profile (ADR-142), the «Σχετικά» of its public
  page: what it may say, and the shared vocabularies that Γύρω μου filters
  on. Vocabularies are keys; clients translate them.
  """

  @disciplines ~w(
    crossfit functional_fitness hyrox strength powerlifting olympic_lifting
    bodybuilding gymnastics running endurance bootcamp hiit yoga pilates
    mobility martial_arts boxing calisthenics swimming cycling dance kids
  )

  @audiences ~w(beginners women over_40 seniors teens athletes prenatal adaptive)

  @max_about 2_000
  @max_photos 12

  def disciplines, do: @disciplines
  def audiences, do: @audiences
  def max_about, do: @max_about
  def max_photos, do: @max_photos

  @doc "Lowercase ISO 639-1 codes, unique, at most 10."
  def normalize_languages(languages) when is_list(languages) do
    languages =
      languages
      |> Enum.map(&(&1 |> to_string() |> String.trim() |> String.downcase()))
      |> Enum.uniq()

    if length(languages) <= 10 and Enum.all?(languages, &(&1 =~ ~r/^[a-z]{2}$/)),
      do: {:ok, languages},
      else: {:error, :invalid_languages}
  end

  def normalize_languages(_languages), do: {:error, :invalid_languages}

  @doc "Unique ids, order kept, at most #{@max_photos}."
  def normalize_photo_ids(ids) when is_list(ids) do
    ids = Enum.uniq(ids)

    cond do
      length(ids) > @max_photos -> {:error, :too_many_photos}
      Enum.all?(ids, &match?({:ok, _}, Ecto.UUID.cast(&1))) -> {:ok, ids}
      true -> {:error, :invalid_media}
    end
  end

  def normalize_photo_ids(_ids), do: {:error, :invalid_media}

  @doc """
  A profile can be published only when it says something: an about text or
  at least one discipline. Unpublishing is always allowed.
  """
  def publishable?(%{about: about, disciplines: disciplines}),
    do: (is_binary(about) and String.trim(about) != "") or disciplines != []
end
