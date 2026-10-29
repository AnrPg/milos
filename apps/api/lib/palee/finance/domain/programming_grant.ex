defmodule Palee.Finance.Domain.ProgrammingGrant do
  @moduledoc """
  Which package grant lets staff program workouts for one person (ADR-225), pure.

  ANR (2026-10-28): a WOD can be assigned to a person only when their
  package includes online programming, personal training, or both. The role
  (member or athlete) never implies it.

  * `:online_programming` — the `personal_programming` channel with the
    assigned-workouts benefit; each delivery meters a coaching touchpoint
    (ADR-040).
  * `:personal_training` — the `personal_training` channel with PT sessions;
    the programme is part of the PT service, so no touchpoint is metered.

  Strict: no rollout leniency, no missing-profile pass, no admin bypass
  (`EntitlementPolicy.authorize_explicit/2`).
  """

  alias Palee.Finance.Domain.EntitlementPolicy

  @online %{channel: :personal_programming, capability: :execute_assigned_workouts}
  @personal_training %{channel: :personal_training, capability: :book_pt_sessions}

  @doc """
  `{:ok, :online_programming | :personal_training}` (online programming wins
  when both are included), or `{:error, reason}` with the reason the online
  programming check gave (e.g. `:finance_profile_missing`).
  """
  def of(entitlement) do
    case EntitlementPolicy.authorize_explicit(entitlement, @online) do
      :ok ->
        {:ok, :online_programming}

      {:error, reason} ->
        case EntitlementPolicy.authorize_explicit(entitlement, @personal_training) do
          :ok -> {:ok, :personal_training}
          {:error, _pt_reason} -> {:error, reason}
        end
    end
  end

  @doc "Whether a grant meters a coaching touchpoint per delivered workout."
  def meters_touchpoints?(:online_programming), do: true
  def meters_touchpoints?(_grant), do: false
end
