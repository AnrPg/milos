defmodule MilosTraining.Workouts.Domain.TimerConfigContractTest do
  @moduledoc """
  The web authoring editor builds `timer_config` payloads from
  `apps/web/src/types/timer-config-contract.json`. This test keeps that file in
  lockstep with the backend vocabulary so the editor never sends fields the
  backend rejects or omits fields it requires.
  """
  use ExUnit.Case, async: true

  alias MilosTraining.Workouts.Domain.TimerConfig
  alias MilosTraining.Workouts.Domain.WorkoutDsl.Vocabulary

  @contract_path Path.expand(
                   "../../../../../web/src/types/timer-config-contract.json",
                   __DIR__
                 )
  @external_resource @contract_path
  @contract @contract_path |> File.read!() |> Jason.decode!()

  test "the web contract lists every backend section format" do
    assert @contract |> Map.keys() |> Enum.sort() ==
             Enum.sort(Vocabulary.export().section_formats)
  end

  for {format, %{"required" => required, "optional" => optional}} <- @contract do
    test "#{format} matches the backend timer vocabulary" do
      format = unquote(format)

      assert unquote(required) ==
               format |> Vocabulary.required_timer_fields() |> Enum.map(&Atom.to_string/1)

      assert unquote(optional) ==
               format |> Vocabulary.optional_timer_fields() |> Enum.map(&Atom.to_string/1)
    end
  end

  test "a config built from the contract's required fields normalizes" do
    for {format, %{"required" => required}} <- @contract do
      config =
        Map.new(required, fn field -> {field, sample_value(String.to_existing_atom(field))} end)

      assert {:ok, %{type: ^format}} = TimerConfig.normalize(Map.put(config, "type", format)),
             "#{format} rejected its own required fields"
    end
  end

  defp sample_value(field) do
    case Vocabulary.timer_value_kind(field) do
      :enum -> field |> Vocabulary.timer_enum_values() |> hd()
      :string -> "sample"
      _numeric -> 1
    end
  end
end
