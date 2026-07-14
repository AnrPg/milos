defmodule MilosTraining.Notifications.Domain.VisibleTypes do
  @hidden_inbox_types ["workout_completed"]

  def hidden_inbox_types, do: @hidden_inbox_types

  def visible_inbox_type?(type) when is_atom(type), do: visible_inbox_type?(Atom.to_string(type))
  def visible_inbox_type?(type) when is_binary(type), do: type not in @hidden_inbox_types
end
