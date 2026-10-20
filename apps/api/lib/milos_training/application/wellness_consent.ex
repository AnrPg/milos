defmodule MilosTraining.Application.WellnessConsent do
  @moduledoc """
  Water, sleep, meals and cravings are health data (ADR-159 §7, plan D8):
  the member records them only with an active `health_data` consent
  (ADR-158's consents), asked once when they start using Ευεξία. Reading
  what is already there never needs it; withdrawing it hides everything
  from coaches at once (row security checks it).
  """

  alias MilosTraining.Body

  @scope "health_data"

  def scope, do: @scope

  def require(%{user_id: user_id} = context) do
    if active?(context, user_id), do: :ok, else: {:error, :health_data_consent_required}
  end

  def active?(context, user_id) do
    context
    |> Body.list_consents(user_id)
    |> Body.consent_summary()
    |> Enum.any?(&(&1.scope == @scope and &1.active))
  end
end
