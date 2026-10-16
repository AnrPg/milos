defmodule MilosTraining.Application.GetPRSharing do
  @moduledoc """
  The owner's PR sharing settings: whether new gym PRs start visible to the
  gym's coaches (the member's `pr` default, ADR-139) and the accounts they
  have explicitly granted read access to (ADR-129).
  """

  alias MilosTraining.Application.PRSharingProfiles
  alias MilosTraining.{Journal, Pantheon}

  def call(%{user_id: user_id} = context) do
    {defaults, grants} =
      Pantheon.with_user_context(context, fn ->
        {Journal.visibility_defaults(user_id), Pantheon.list_owned_grants(user_id)}
      end)

    profiles = grants |> Enum.map(& &1.grantee_user_id) |> PRSharingProfiles.call()

    {:ok,
     %{
       coach_visibility: Journal.visibility_reaches_coach?(defaults["pr"]),
       grants:
         grants
         |> Enum.filter(&Map.has_key?(profiles, &1.grantee_user_id))
         |> Enum.map(fn grant ->
           %{id: grant.id, created_at: grant.created_at, grantee: profiles[grant.grantee_user_id]}
         end)
     }}
  end
end
