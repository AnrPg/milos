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

  @doc """
  Before a device brings in health data (ADR-161, ADR-172): `:ok` when
  none is wanted or the consent is active; grants it when the person ticked
  the consent line in the same step; otherwise asks for it.
  """
  def for_device(%{user_id: user_id} = context, health_data?, granted_now?, now) do
    cond do
      not health_data? ->
        :ok

      active?(context, user_id) ->
        :ok

      granted_now? in [true, "true"] ->
        with {:ok, _consent} <- Body.grant_consent(context, user_id, @scope, now), do: :ok

      true ->
        {:error, :health_data_consent_required}
    end
  end

  def active?(context, user_id) do
    context
    |> Body.list_consents(user_id)
    |> Body.consent_summary()
    |> Enum.any?(&(&1.scope == @scope and &1.active))
  end
end
