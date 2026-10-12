defmodule MilosTraining.Application.GetPRSharing do
  @moduledoc """
  The owner's PR sharing settings (ADR-119): whether gym coaches may read
  their PRs, and the accounts they have explicitly granted read access to.
  """

  alias MilosTraining.Application.PRSharingProfiles
  alias MilosTraining.Pantheon

  def call(%{user_id: user_id} = context) do
    {preference, grants} =
      Pantheon.with_user_context(context, fn ->
        {Pantheon.get_sharing_preference(user_id), Pantheon.list_owned_grants(user_id)}
      end)

    profiles = grants |> Enum.map(& &1.grantee_user_id) |> PRSharingProfiles.call()

    {:ok,
     %{
       coach_visibility: preference.coach_visibility,
       grants:
         grants
         |> Enum.filter(&Map.has_key?(profiles, &1.grantee_user_id))
         |> Enum.map(fn grant ->
           %{id: grant.id, created_at: grant.created_at, grantee: profiles[grant.grantee_user_id]}
         end)
     }}
  end
end
