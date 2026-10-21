defmodule MilosTraining.Scaling do
  @moduledoc """
  The Scaling bounded context (ADR-174, P3-M12): AI scaling suggestions for
  an injured athlete's programmed workout, held for the coach's approval.

  It owns the suggestion and its review. The advisor sits behind the
  `ScalingAdvisor` port; the gym's key and the usage meter live in AiUsage;
  workouts, injuries and coaching scope are read by the application layer.
  Every function runs in the gym's scope.
  """

  alias MilosTraining.Scaling.{ScalingAdvisor, ScalingStore}
  alias MilosTraining.Scaling.Domain.{Advice, AdvisorInput, SuggestionPolicy, TenantDataPolicy}

  defdelegate get(context, id), to: ScalingStore
  defdelegate latest_live(context, assignment_id, athlete_id), to: ScalingStore
  defdelegate insert(context, attrs), to: ScalingStore
  defdelegate replace(context, previous, attrs), to: ScalingStore
  defdelegate update(context, suggestion, changes), to: ScalingStore
  defdelegate list(context, filters), to: ScalingStore
  defdelegate approved_for_member(context, athlete_id, workout_id, from), to: ScalingStore
  defdelegate approved_history(context, athlete_id, limit), to: ScalingStore

  defdelegate suggest(input, options), to: ScalingAdvisor
  defdelegate default_model(), to: ScalingAdvisor

  defdelegate build_input(params), to: AdvisorInput, as: :build
  defdelegate movements(workout), to: AdvisorInput
  defdelegate injury_regions(warnings), to: AdvisorInput, as: :regions
  defdelegate digest(input), to: AdvisorInput
  defdelegate normalize_advice(raw, movements, scale_levels), to: Advice, as: :normalize

  defdelegate scan_window(today), to: SuggestionPolicy
  defdelegate next_step(latest, digest), to: SuggestionPolicy

  defdelegate approve_changes(suggestion, params, actor_id, now),
    to: SuggestionPolicy,
    as: :approve

  defdelegate dismiss_changes(suggestion, actor_id, now), to: SuggestionPolicy, as: :dismiss
  defdelegate member_view(suggestion), to: SuggestionPolicy

  # ADR-117 reviewed tenant export/purge.
  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
