defmodule MilosTraining.Application.ListPRDossierMembers do
  @moduledoc """
  The coach's way into members' PR dossiers (ADR-132, TD-091).

  Every coach of a gym reads the PRs its active members recorded there
  (ADR-129), but the people directory is narrowed to a coach's own clients
  (ADR-100). This list closes the gap without widening the directory: it names
  the gym's active members (public identity only - nickname and avatar, the
  same co-member identity any member already sees) so a coach can open any of
  their PR panels. Staff who are not coaches get the same role-safe empty
  state as the dossier PR endpoint, without any member read.
  """

  alias MilosTraining.Application.TenantUserAccess
  alias MilosTraining.Organizations
  alias MilosTraining.Organizations.TenantContext

  def call(%TenantContext{} = context) do
    if Organizations.acting_user_coaches?(context) do
      {:ok, %{visibility: "coach", members: members(context)}}
    else
      {:ok, %{visibility: "coach_role_required", members: []}}
    end
  end

  def call(_context), do: {:error, :organization_context_required}

  defp members(context) do
    context
    |> TenantUserAccess.list_active_users()
    |> Enum.reject(&(&1.id == context.user_id))
    |> Enum.sort_by(&String.downcase(&1.nickname))
    |> Enum.map(fn user ->
      %{
        id: user.id,
        nickname: user.nickname,
        avatar_url: user.avatar_url,
        role: to_string(user.role),
        joined_at: timestamp(user.inserted_at)
      }
    end)
  end

  defp timestamp(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp timestamp(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp timestamp(_value), do: nil
end
