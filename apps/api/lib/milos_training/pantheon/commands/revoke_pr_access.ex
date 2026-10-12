defmodule MilosTraining.Pantheon.Commands.RevokePRAccess do
  @moduledoc """
  Revokes one of the owner's active PR sharing grants (ADR-111). The row is
  kept with `revoked_at` as a record of past sharing. Must run in the owner's
  scope.
  """

  alias MilosTraining.Pantheon.PRStore

  def call(user_id, grant_id, revoked_at \\ DateTime.utc_now()),
    do: PRStore.revoke_grant(user_id, grant_id, revoked_at)
end
