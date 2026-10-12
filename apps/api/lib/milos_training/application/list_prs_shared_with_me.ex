defmodule MilosTraining.Application.ListPRsSharedWithMe do
  @moduledoc """
  The grantee's "Shared with me" view (ADR-111): every PR, with history, of
  each account that has an active grant naming the acting user. Reads run in
  the grantee's own scope; `user_pr_records_grantee_read_policy` is what
  admits them, so a revoked grant returns nothing.
  """

  alias MilosTraining.Application.PRSharingProfiles
  alias MilosTraining.Pantheon

  def call(%{user_id: user_id} = context) do
    shared =
      Pantheon.with_user_context(context, fn ->
        user_id
        |> Pantheon.list_received_grants()
        |> Enum.map(fn grant -> {grant, read(grant.user_id)} end)
      end)

    profiles =
      shared |> Enum.map(fn {grant, _prs} -> grant.user_id end) |> PRSharingProfiles.call()

    {:ok,
     %{
       shared:
         shared
         |> Enum.filter(fn {grant, _prs} -> Map.has_key?(profiles, grant.user_id) end)
         |> Enum.map(fn {grant, prs} ->
           %{
             grant_id: grant.id,
             shared_at: grant.created_at,
             owner: profiles[grant.user_id],
             prs: prs
           }
         end)
     }}
  end

  defp read(owner_user_id) do
    owner_user_id
    |> Pantheon.list_records()
    |> Enum.map(&Pantheon.read_only_view(&1, Pantheon.list_record_history(&1.id)))
  end
end
