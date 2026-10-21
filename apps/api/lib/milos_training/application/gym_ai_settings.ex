defmodule MilosTraining.Application.GymAiSettings do
  @moduledoc """
  The gym's AI settings (ADR-174): read and write the switch for scaling
  suggestions, the gym's own key (write-only) and an optional model, plus
  this month's metered usage of the feature (ADR-152).
  """

  alias MilosTraining.Application.ScalingSuggestions
  alias MilosTraining.{AiUsage, Scaling}

  def get(context, now \\ DateTime.utc_now()) do
    context
    |> AiUsage.get_settings()
    |> AiUsage.public_settings(Scaling.default_model())
    |> Map.put(:usage, month_usage(context, now))
  end

  def update(context, params, now \\ DateTime.utc_now()) do
    current = AiUsage.get_settings(context)

    with {:ok, changes} <- AiUsage.settings_update_changes(current, params, context.user_id),
         {:ok, _settings} <- AiUsage.put_settings(context, changes) do
      {:ok, get(context, now)}
    end
  end

  # The current calendar month (UTC): suggestions asked and their cost.
  defp month_usage(context, now) do
    from = %{DateTime.truncate(now, :second) | day: 1, hour: 0, minute: 0, second: 0}

    summary =
      AiUsage.usage_summary(context, %{from: from, feature: ScalingSuggestions.feature()})

    %{
      since: from,
      suggestions: Enum.sum(Enum.map(summary.rows, & &1.operations)),
      cost_usd: summary.cost_usd || 0.0
    }
  end
end
