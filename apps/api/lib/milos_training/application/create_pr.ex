defmodule MilosTraining.Application.CreatePR do
  alias MilosTraining.Application.{InvalidateLandingPages, PRSearchIndex}
  alias MilosTraining.{Gamification, Journal, Organizations, Pantheon}
  alias MilosTraining.Pantheon.Domain.PRResultMetrics

  # ADR-129: a PR may record the gym it was achieved in (`organization_slug`).
  # The slug must resolve to an active membership of the acting user; the PR's
  # organization provenance is what makes it visible to that gym's coaches.
  # Without a slug the PR is personal. Everything runs in the owner's scope.
  def call(%{user_id: user_id, account: account} = context, params) when is_map(params) do
    with {:ok, organization_id} <- provenance(account, params) do
      Pantheon.with_user_context(context, fn -> create(user_id, organization_id, params) end)
    end
  end

  # Caller-scoped entry point (the caller already runs in the owner's scope).
  def call(user_id, params) when is_binary(user_id), do: create(user_id, nil, params)

  defp create(user_id, organization_id, params) do
    with {:ok, normalized_params} <- normalize_params(params),
         {:ok, pr} <-
           normalized_params
           |> Map.drop(["organization_slug", :organization_slug, "organization_id"])
           |> Map.put("user_id", user_id)
           |> Map.put("organization_id", organization_id)
           |> Map.put(
             "journal_visibility",
             Journal.initial_visibility(user_id, "pr", is_binary(organization_id))
           )
           |> Pantheon.create_record() do
      {:ok, _stats} = Gamification.increment_advancement(user_id, DateTime.utc_now())
      :ok = PRSearchIndex.enqueue_upsert(pr)
      InvalidateLandingPages.for_users([user_id])
      {:ok, pr}
    end
  end

  defp provenance(account, params) do
    case params["organization_slug"] || params[:organization_slug] do
      slug when is_binary(slug) and slug != "" ->
        case Organizations.resolve_tenant_context(account, slug) do
          {:ok, tenant_context} -> {:ok, tenant_context.organization_id}
          {:error, _reason} -> {:error, :pr_organization_unavailable}
        end

      _personal ->
        {:ok, nil}
    end
  end

  # Creation always requires supporting metrics, so they are normalized
  # unconditionally (an absent value is validated by PRResultMetrics).
  defp normalize_params(params) do
    with {:ok, metrics} <-
           PRResultMetrics.normalize(params["supporting_metrics"] || params[:supporting_metrics]) do
      {:ok, Map.put(params, "supporting_metrics", metrics)}
    end
  end
end
