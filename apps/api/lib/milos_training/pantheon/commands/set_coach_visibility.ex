defmodule MilosTraining.Pantheon.Commands.SetCoachVisibility do
  @moduledoc """
  Owner-only opt-out (ADR-119): when disabled, no coach of any gym can read
  the user's PRs. Explicit grants are unaffected. Must run in the owner's scope.
  """

  alias MilosTraining.Pantheon.PRStore

  def call(user_id, enabled?) when is_boolean(enabled?),
    do: PRStore.put_coach_visibility(user_id, enabled?)

  def call(_user_id, _enabled?), do: {:error, :bad_request}
end
