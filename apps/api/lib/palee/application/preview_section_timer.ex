defmodule Palee.Application.PreviewSectionTimer do
  @moduledoc """
  Shows authors the exact timer sequence a draft section will run, using the
  same builder as execution so the preview can never disagree with it.
  """

  alias Palee.{Execution, Workouts}

  def call(section) when is_map(section) do
    with {:ok, timer_config} <- Workouts.normalize_timer_config(value(section, :timer_config)) do
      section =
        section
        |> Map.take([
          "name",
          "timer_config",
          "exercises",
          "section_metadata",
          "rest_before_next_section_seconds"
        ])
        |> Map.put("timer_config", timer_config)
        |> Map.put("id", "preview")
        |> Map.put_new("exercises", [])

      {:ok, Execution.preview_timer_sequence(%{sections: [section]})}
    else
      {:error, message} -> {:error, {:invalid_timer_config, message}}
    end
  end

  def call(_section), do: {:error, {:invalid_timer_config, "must be an object"}}

  defp value(map, key), do: Map.get(map, Atom.to_string(key)) || Map.get(map, key)
end
