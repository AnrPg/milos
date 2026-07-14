defmodule MilosTraining.Finance.Domain.EntitlementPolicy do
  @allowed_statuses ["active", "grace"]

  # Users without a Finance membership remain unmanaged during the additive rollout.
  def authorize(nil, _capability), do: :ok

  def authorize(%{status: status}, _capability) when status in @allowed_statuses, do: :ok

  def authorize(%{status: "blocked"}, _capability),
    do: {:error, :finance_entitlement_blocked}

  def authorize(%{status: "inactive"}, _capability),
    do: {:error, :finance_entitlement_inactive}

  def authorize(_entitlement, _capability), do: {:error, :finance_entitlement_inactive}
end
