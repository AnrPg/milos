defmodule MilosTraining.Execution.Domain.TimerPresets do
  @moduledoc """
  Timer presets for workouts without a structured sequence (free text, or a
  class with no workout). Mirrors `apps/web/src/lib/free-text-timer.ts`
  (`buildFreeTextSegments`) so the class timer's server-side catch-up and
  every client agree on the same segments.
  """

  @formats ~w(untimed for_time amrap emom tabata custom_hiit death_by)

  def formats, do: @formats

  @doc "Reads a preset from untrusted input; nil when it is not a known format."
  def parse(%{} = raw) do
    format = value(raw, :format)

    if format in @formats do
      %{
        "format" => format,
        "duration_seconds" => positive(value(raw, :duration_seconds)),
        "rounds" => positive(value(raw, :rounds)),
        "work_seconds" => positive(value(raw, :work_seconds)),
        "rest_seconds" => positive(value(raw, :rest_seconds)),
        "interval_seconds" => positive(value(raw, :interval_seconds))
      }
    end
  end

  def parse(_raw), do: nil

  @doc "Builds the timer segments for a parsed preset."
  def build(%{"format" => "for_time"} = preset),
    do: [
      segment(0, %{
        format: "for_time",
        kind: :countup,
        duration_seconds: preset["duration_seconds"]
      })
    ]

  def build(%{"format" => "amrap"} = preset),
    do: [
      segment(0, %{
        format: "amrap",
        kind: :countdown,
        duration_seconds: preset["duration_seconds"] || 720
      })
    ]

  def build(%{"format" => "emom"} = preset),
    do: [
      segment(0, %{
        format: "emom",
        kind: :interval_cycle,
        duration_seconds: preset["interval_seconds"] || 60,
        total_rounds: preset["rounds"] || 10,
        label: "EMOM",
        label_key: "emom"
      })
    ]

  def build(%{"format" => "death_by"} = preset),
    do: [
      segment(0, %{
        format: "death_by",
        kind: :interval_cycle,
        duration_seconds: preset["interval_seconds"] || 60,
        total_rounds: preset["rounds"],
        label: "Death By",
        label_key: "death_by"
      })
    ]

  def build(%{"format" => format} = preset) when format in ["tabata", "custom_hiit"] do
    rounds = preset["rounds"] || 8
    work = preset["work_seconds"] || 20
    rest = preset["rest_seconds"] || if(format == "tabata", do: 10)

    1..rounds
    |> Enum.flat_map(fn round ->
      work_segment = %{
        format: format,
        kind: :countdown,
        duration_seconds: work,
        round: round,
        total_rounds: rounds,
        label: "Work #{round}/#{rounds}",
        label_key: "work",
        label_params: %{round: round, total: rounds}
      }

      if rest && round < rounds do
        [
          work_segment,
          %{
            format: format,
            kind: :countdown,
            phase: "rest",
            duration_seconds: rest,
            round: round,
            total_rounds: rounds,
            label: "Rest #{round}/#{rounds}",
            label_key: "rest_round",
            label_params: %{round: round, total: rounds}
          }
        ]
      else
        [work_segment]
      end
    end)
    |> Enum.with_index()
    |> Enum.map(fn {attrs, index} -> segment(index, attrs) end)
  end

  def build(_preset), do: [segment(0, %{format: "untimed", kind: :countup})]

  defp segment(index, attrs) do
    Map.merge(
      %{
        segment_key: "free-text:#{index}",
        section_id: "free-text",
        section_name: "",
        format: "untimed",
        kind: :countup,
        phase: "work",
        duration_seconds: nil,
        round: nil,
        total_rounds: nil,
        label: "",
        label_key: nil,
        label_params: %{},
        scoreable: false,
        score_config: nil,
        timer_config: %{},
        exercises: []
      },
      attrs
    )
  end

  defp positive(value) when is_integer(value) and value > 0, do: value
  defp positive(value) when is_float(value) and value > 0, do: round(value)
  defp positive(_value), do: nil

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
