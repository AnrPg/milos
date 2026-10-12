defmodule MilosTraining.Application.SetPRCoachVisibility do
  @moduledoc """
  The owner's coach-visibility opt-out (ADR-119). Applies to every gym the
  user belongs to; explicit sharing grants are unaffected.
  """

  alias MilosTraining.Application.GetPRSharing
  alias MilosTraining.Pantheon

  def call(%{user_id: user_id} = context, params) when is_map(params) do
    enabled? = Map.get(params, "coach_visibility", Map.get(params, :coach_visibility))

    with {:ok, _preference} <-
           Pantheon.with_user_context(context, fn ->
             Pantheon.set_coach_visibility(user_id, normalize(enabled?))
           end) do
      GetPRSharing.call(context)
    end
  end

  defp normalize(value) when is_boolean(value), do: value
  defp normalize(_value), do: :invalid
end
