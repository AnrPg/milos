defmodule MilosTraining.Application.ListClassTypes do
  alias MilosTraining.Scheduling

  def call(opts \\ []), do: {:ok, Scheduling.list_class_types(opts)}
end
