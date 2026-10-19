defmodule MilosTraining.Organizations.Domain.BoxProfilePolicy do
  @moduledoc """
  Rules of a gym's public profile (ADR-142), the «Σχετικά» of its public
  page: what it may say, and the shared vocabularies that Γύρω μου filters
  on. Vocabularies are keys; clients translate them.
  """

  # Board 3b (plan §5a): researched against ClassPass, Urban Sports Club,
  # Mindbody, Wellhub and Google Business Profile. Keys are never renamed;
  # new ones are added. Group order is the picker's order.
  @discipline_groups [
    {"strength", ~w(strength powerlifting olympic_lifting bodybuilding strongman kettlebell)},
    {"functional",
     ~w(crossfit functional_fitness hyrox hiit bootcamp circuit_training calisthenics gymnastics)},
    {"endurance", ~w(running indoor_cycling cycling rowing endurance ems_training)},
    {"mind_body",
     ~w(yoga hot_yoga pilates pilates_reformer barre mobility stretching tai_chi_qigong)},
    {"combat",
     ~w(boxing kickboxing muay_thai mma bjj_grappling wrestling martial_arts self_defense)},
    {"dance", ~w(dance dance_fitness pole_aerial)},
    {"aquatic", ~w(swimming aqua_fitness)},
    {"outdoor", ~w(outdoor_training climbing_bouldering)},
    {"recovery", ~w(physio_rehab sports_massage recovery)}
  ]

  @disciplines Enum.flat_map(@discipline_groups, &elem(&1, 1))

  # Health conditions, weight loss, religion and body size are never tags
  # (EU consumer law, GDPR art. 9). The last two are the gym's own statement.
  @audiences ~w(
    beginners women_only kids teens over_40 seniors prenatal_postnatal adaptive
    athletes students lgbtq_friendly returning_from_injury
  )

  @amenities ~w(
    showers changing_rooms lockers towels parking bike_parking public_transport_nearby
    air_conditioning sauna cold_plunge childcare wheelchair_accessible accessible_restroom
    gender_neutral_restroom wifi water_refill outdoor_area drop_in_friendly
  )

  @services ~w(personal_training small_group_training open_gym nutrition_coaching online_coaching corporate)

  @suggestion_lists ~w(disciplines audiences amenities services)

  @max_about 2_000
  @max_photos 12

  def discipline_groups, do: @discipline_groups
  def disciplines, do: @disciplines
  def audiences, do: @audiences
  def amenities, do: @amenities
  def services, do: @services
  def suggestion_lists, do: @suggestion_lists

  @doc "The vocabularies clients render, groups in picker order."
  def vocabulary do
    %{
      discipline_groups:
        Enum.map(@discipline_groups, fn {key, items} -> %{key: key, items: items} end),
      audiences: @audiences,
      amenities: @amenities,
      services: @services
    }
  end

  @doc "Welcoming people back from injury is only for gyms that do rehab."
  def audiences_consistent?(audiences, disciplines),
    do: "returning_from_injury" not in audiences or "physio_rehab" in disciplines

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
  What a draft still needs before it can be published (board 3 Q8): the
  about text and at least one discipline.
  """
  def missing(%{about: about, disciplines: disciplines}) do
    [
      {"about", is_binary(about) and String.trim(about) != ""},
      {"disciplines", disciplines != []}
    ]
    |> Enum.reject(&elem(&1, 1))
    |> Enum.map(&elem(&1, 0))
  end

  def publishable?(profile), do: missing(profile) == []
end
