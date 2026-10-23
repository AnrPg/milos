defmodule Palee.Application.DemoSeeders do
  @moduledoc """
  ADR-184: the registry of demo seeders, one per admin section, in the order
  «fill everything» runs them. Adding a screen's demo data is adding a module
  implementing `Application.DemoSeeder` here.
  """

  alias Palee.Application.DemoSeeders.{Finance, Members, Schedule, Workouts}

  @seeders [Members, Schedule, Finance, Workouts]

  @doc "The seeder modules, dependencies first."
  def all, do: @seeders

  @doc "Section keys, in run order."
  def sections, do: Enum.map(@seeders, & &1.section())

  @doc "The seeder of a section."
  def fetch(section) do
    case Enum.find(@seeders, &(&1.section() == section)) do
      nil -> {:error, :unknown_demo_section}
      seeder -> {:ok, seeder}
    end
  end

  @doc """
  The seeders to run for `section` (its requirements first, each once),
  skipping the sections already seeded. `"all"` means every section.
  """
  def plan("all", seeded_sections), do: plan_many(sections(), seeded_sections)

  def plan(section, seeded_sections) do
    with {:ok, _seeder} <- fetch(section), do: plan_many([section], seeded_sections)
  end

  defp plan_many(sections, seeded_sections) do
    sections
    |> Enum.reduce({:ok, []}, fn
      section, {:ok, acc} -> expand(section, acc, seeded_sections)
      _section, error -> error
    end)
    |> case do
      {:ok, ordered} -> {:ok, Enum.reverse(ordered)}
      error -> error
    end
  end

  defp expand(section, acc, seeded_sections) do
    with {:ok, seeder} <- fetch(section) do
      if section in seeded_sections or seeder in acc do
        {:ok, acc}
      else
        seeder.requires()
        |> Enum.reduce({:ok, acc}, fn
          required, {:ok, acc} -> expand(required, acc, seeded_sections)
          _required, error -> error
        end)
        |> case do
          {:ok, acc} -> {:ok, [seeder | acc]}
          error -> error
        end
      end
    end
  end
end
