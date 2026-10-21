defmodule Palee.Application.SetPRCoachVisibility do
  @moduledoc """
  "Coaches can see my PRs" (ADR-129, reshaped by ADR-139): sets the member's
  `pr` default rung and moves every gym PR between `private` and
  `coach_can_view` to match, so the switch keeps meaning what it says. PRs on
  a higher rung (a reply request, a post) and explicit grants are unaffected.
  """

  alias Palee.Application.GetPRSharing
  alias Palee.{Journal, Pantheon}

  def call(%{user_id: user_id} = context, params) when is_map(params) do
    case Map.get(params, "coach_visibility", Map.get(params, :coach_visibility)) do
      enabled? when is_boolean(enabled?) ->
        {rung, other} =
          if enabled?, do: {"coach_can_view", "private"}, else: {"private", "coach_can_view"}

        with :ok <-
               Pantheon.with_user_context(context, fn ->
                 with :ok <- Journal.put_visibility_default(user_id, "pr", rung) do
                   _moved = Pantheon.move_records(user_id, [other], rung)
                   :ok
                 end
               end) do
          GetPRSharing.call(context)
        end

      _invalid ->
        {:error, :bad_request}
    end
  end
end
