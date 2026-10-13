defmodule MilosTraining.Application.JoinOrganizationByLink do
  @moduledoc """
  An authenticated account joins an organization through its public join link.

  Like invitation redemption (ADR-095), a client account that had no
  organization yet gets its global role aligned with the client role it joined
  with. Staff and vendor accounts, and clients that already belong elsewhere,
  keep their account role.
  """

  alias MilosTraining.{Identity, Organizations}

  def call(%{id: user_id} = user, slug) do
    with {:ok, result} <- Organizations.join_by_link(slug, user_id),
         {:ok, _user} <- maybe_align_role(user, result) do
      {:ok, result}
    end
  end

  defp maybe_align_role(user, %{created: true, membership: membership}) do
    role = membership.role

    if user.role in [:member, :athlete] and user.role != role and only_membership?(user.id) do
      Identity.update_role(user, role)
    else
      {:ok, user}
    end
  end

  defp maybe_align_role(user, _result), do: {:ok, user}

  defp only_membership?(user_id) do
    user_id |> Organizations.list_memberships() |> length() <= 1
  end
end
