defmodule Palee.Workouts.Domain.WorkoutType do
  @moduledoc """
  The training kinds a workout can be (ADR-275), one fixed list for the whole
  platform, grouped in families. The family is what stats, badges and colours
  read, so a new kind joins a family and needs nothing else.

  Keys match the box profile's disciplines (`BoxProfilePolicy`) where both
  name the same training. `aerobics` and `flexibility` are the original kinds
  and stay valid: stored workouts never change kind.
  """

  @families [
    {"functional", ~w(crossfit functional_fitness hyrox hiit bootcamp circuit_training)},
    {"strength", ~w(strength powerlifting olympic_lifting bodybuilding strongman kettlebell)},
    {"gymnastics", ~w(gymnastics calisthenics)},
    {"endurance", ~w(aerobics running cycling indoor_cycling rowing swimming endurance)},
    {"mind_body", ~w(yoga pilates barre flexibility mobility stretching tai_chi_qigong)},
    {"combat",
     ~w(boxing kickboxing muay_thai mma bjj_grappling wrestling martial_arts self_defense)},
    {"dance", ~w(dance dance_fitness pole_aerial)},
    {"outdoor", ~w(outdoor_training climbing_bouldering)},
    {"recovery", ~w(recovery)}
  ]

  @keys Enum.flat_map(@families, &elem(&1, 1))
  @values Enum.map(@keys, &String.to_atom/1)
  @family_of for {family, keys} <- @families, key <- keys, into: %{}, do: {key, family}

  @doc "Every kind, as atoms (the `master_workouts.type` enum)."
  def values, do: @values

  @doc "Every kind, as strings."
  def keys, do: @keys

  @doc "The families in display order, each with its kinds."
  def families, do: @families

  @doc "The family names."
  def family_keys, do: Enum.map(@families, &elem(&1, 0))

  def valid?(type) when is_atom(type) and not is_nil(type), do: valid?(Atom.to_string(type))
  def valid?(type) when is_binary(type), do: Map.has_key?(@family_of, type)
  def valid?(_type), do: false

  @doc "The family a kind belongs to, or nil for an unknown kind."
  def family(type) when is_atom(type) and not is_nil(type), do: family(Atom.to_string(type))
  def family(type) when is_binary(type), do: Map.get(@family_of, type)
  def family(_type), do: nil
end
