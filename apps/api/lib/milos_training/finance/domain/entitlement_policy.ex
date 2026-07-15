defmodule MilosTraining.Finance.Domain.EntitlementPolicy do
  alias MilosTraining.Finance.Domain.EntitlementPlan

  @allowed_statuses ["active", "grace"]

  def authorize(entitlement, request) do
    case authorize(entitlement, request, mode: :observe) do
      {:ok, _decision} -> :ok
      result -> result
    end
  end

  def authorize(entitlement, request, opts) do
    if Keyword.get(opts, :actor_role) == :admin do
      :ok
    else
      authorize_customer(entitlement, request, opts)
    end
  end

  defp authorize_customer(nil, _request, opts) do
    case Keyword.get(opts, :mode, :observe) do
      :observe -> {:ok, %{observed?: true, reason: :finance_profile_missing}}
      :enforce_managed -> :ok
      :enforce_all -> {:error, :finance_profile_missing}
    end
  end

  defp authorize_customer(%{status: status} = entitlement, request, opts)
       when status in @allowed_statuses do
    mode = Keyword.get(opts, :mode, :observe)

    case Map.get(entitlement, :plan) || Map.get(entitlement, "plan") do
      nil when mode == :observe -> {:ok, %{observed?: true, reason: :entitlement_plan_missing}}
      nil when mode == :enforce_managed -> :ok
      nil -> {:error, :finance_entitlement_plan_missing}
      plan -> authorize_plan(plan, request, mode)
    end
  end

  defp authorize_customer(%{status: "blocked"}, _request, _opts),
    do: {:error, :finance_entitlement_blocked}

  defp authorize_customer(%{status: "inactive"}, _request, _opts),
    do: {:error, :finance_entitlement_inactive}

  defp authorize_customer(_entitlement, _request, _opts),
    do: {:error, :finance_entitlement_inactive}

  defp authorize_plan(raw_plan, request, mode) do
    result = authorize_plan_enforced(raw_plan, request, mode)

    case {mode, result} do
      {:observe, {:error, reason}} ->
        {:ok, %{observed?: true, reason: reason}}

      {:observe, {:error, reason, details}} ->
        {:ok, %{observed?: true, reason: reason, details: details}}

      _ ->
        result
    end
  end

  defp authorize_plan_enforced(raw_plan, request, mode) do
    with {:ok, plan} <- EntitlementPlan.parse(raw_plan),
         :ok <- require_member(plan.channels, request_value(request, :channel), :channel, mode),
         :ok <-
           require_member(
             plan.capabilities,
             request_value(request, :capability),
             :capability,
             mode
           ) do
      authorize_allowance(plan, request)
    else
      {:error, _reason} = error -> error
    end
  end

  defp require_member(_set, nil, _kind, _mode), do: :ok

  defp require_member(set, value, kind, mode) do
    if MapSet.member?(set, value) do
      :ok
    else
      missing_member_error(kind, mode)
    end
  end

  defp missing_member_error(kind, :observe), do: {:error, observed_error(kind)}
  defp missing_member_error(:channel, _mode), do: {:error, :finance_channel_not_included}
  defp missing_member_error(:capability, _mode), do: {:error, :finance_capability_not_included}

  defp observed_error(:channel), do: :finance_channel_not_included
  defp observed_error(:capability), do: :finance_capability_not_included

  defp authorize_allowance(plan, request) do
    allowance = request_value(request, :allowance)

    case allowance && Map.get(plan.allowances, allowance) do
      nil when is_nil(allowance) ->
        {:ok, %{remaining: :not_metered}}

      nil ->
        {:error, :finance_allowance_not_included}

      config ->
        limit = request_value(request, :limit) || config.limit
        committed = request_value(request, :committed) || 0
        quantity = request_value(request, :quantity) || 1
        decide_limit(limit, committed, quantity, allowance)
    end
  end

  defp decide_limit(:unlimited, committed, _quantity, allowance),
    do:
      {:ok,
       %{allowance: allowance, limit: :unlimited, committed: committed, remaining: :unlimited}}

  defp decide_limit(limit, committed, quantity, allowance)
       when committed + quantity <= limit do
    {:ok,
     %{
       allowance: allowance,
       limit: limit,
       committed: committed,
       remaining: limit - committed - quantity
     }}
  end

  defp decide_limit(limit, committed, _quantity, allowance) do
    {:error, :finance_allowance_exhausted,
     %{allowance: allowance, limit: limit, committed: committed}}
  end

  defp request_value(request, key) when is_atom(request) do
    case key do
      :capability -> request
      _ -> nil
    end
  end

  defp request_value(request, key) when is_map(request),
    do: Map.get(request, key) || Map.get(request, Atom.to_string(key))
end
