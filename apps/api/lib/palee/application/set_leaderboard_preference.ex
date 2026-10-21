defmodule Palee.Application.SetLeaderboardPreference do
  alias Palee.Application.GetLeaderboardSnippet
  alias Palee.Application.InvalidateLandingPages
  alias Palee.Gamification

  # TD-092: opt-ins are tenant rows (one per organization), so the write and
  # the snippet read run in the member's tenant scope. The former unscoped
  # entry point could only fail under the production runtime role.
  def call(%{organization_id: organization_id} = context, user, params)
      when is_binary(organization_id) do
    Gamification.with_tenant_context(context, fn ->
      with {:ok, opted_in} <- extract_opt_in(params),
           {:ok, %{opted_in: persisted_opted_in}} <-
             Gamification.set_leaderboard_opt_in(user.id, opted_in) do
        build_response(user, persisted_opted_in)
      end
    end)
  end

  def call(_context, _user, _params), do: {:error, :organization_context_required}

  defp extract_opt_in(%{opted_in: opted_in}) when is_boolean(opted_in), do: {:ok, opted_in}
  defp extract_opt_in(%{"opted_in" => opted_in}) when is_boolean(opted_in), do: {:ok, opted_in}
  defp extract_opt_in(%{body: body}) when is_map(body), do: extract_opt_in(body)
  defp extract_opt_in(%{"body" => body}) when is_map(body), do: extract_opt_in(body)
  defp extract_opt_in(_params), do: {:error, :bad_request}

  defp build_response(user, persisted_opted_in) do
    _ = Gamification.refresh_leaderboard()
    InvalidateLandingPages.for_all_users()

    leaderboard = GetLeaderboardSnippet.call(user)

    {:ok,
     %{
       opted_in: persisted_opted_in,
       visible: leaderboard.visible,
       weekly: leaderboard.weekly,
       monthly: leaderboard.monthly
     }}
  end
end
