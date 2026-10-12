defmodule MilosTraining.Pantheon.Commands.GrantPRAccess do
  @moduledoc """
  Grants another account read access to all of the owner's PRs (ADR-111).
  Idempotent: an already-active grant is returned unchanged. Must run in the
  owner's scope.
  """

  alias MilosTraining.Pantheon.PRStore

  def call(user_id, user_id), do: {:error, :cannot_share_prs_with_self}

  def call(user_id, grantee_user_id) do
    case PRStore.get_active_grant(user_id, grantee_user_id) do
      nil -> PRStore.create_grant(user_id, grantee_user_id)
      grant -> {:ok, grant}
    end
  end
end
