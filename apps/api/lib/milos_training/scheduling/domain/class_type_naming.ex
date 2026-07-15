defmodule MilosTraining.Scheduling.Domain.ClassTypeNaming do
  @moduledoc "Pure naming rules for administrator-defined class types."

  def slugify(name) when is_binary(name) do
    name
    |> String.normalize(:nfd)
    |> String.replace(~r/[^\x00-\x7F]/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  def slugify(_), do: ""
end
