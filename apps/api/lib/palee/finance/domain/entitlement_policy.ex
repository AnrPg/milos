defmodule Palee.Finance.Domain.EntitlementPolicy do
  alias Palee.Finance.Domain.EntitlementPlan

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

  @doc """
  ADR-125: authorizes only an *explicit* package grant.

  Evaluates the customer's contract in the strictest mode regardless of the
  tenant's rollout mode: no `observe` leniency, no missing-profile or
  missing-plan pass and no admin-actor bypass (the subject is the customer, not
  the caller). Used where a role does not imply the benefit — e.g. personal
  programming for gym members.
  """
  def authorize_explicit(entitlement, request) do
    case authorize_customer(entitlement, Map.delete(request, :actor_role), mode: :enforce_all) do
      {:ok, _decision} -> :ok
      :ok -> :ok
      {:error, reason, _details} -> {:error, reason}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Phase 2 «μόνο ό,τι καλύπτει το πακέτο μου»: whether one subscription's
  plan includes a request (channel, capability, class type, time window,
  location, and an allowance of that kind), regardless of how much of the
  allowance is left. Strict: no observe leniency, no admin bypass.
  """
  def covers?(nil, _plan, _request), do: false

  def covers?(entitlement, plan, request) do
    request = Map.merge(Map.delete(request, :actor_role), %{limit: :unlimited, committed: 0})

    case authorize_customer(Map.put(entitlement, :plan, plan), request, mode: :enforce_all) do
      {:ok, _decision} -> true
      :ok -> true
      _denied -> false
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
           ),
         :ok <- require_class_type(plan, request),
         :ok <- require_time_window(plan, request),
         :ok <- require_location(plan, request_value(request, :location_id)) do
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

  # Class-type scope and time windows govern group classes; events and the
  # facility have their own access rules (ADR-097).
  defp require_class_type(plan, request) do
    if request_value(request, :channel) in [nil, :in_person] and
         not EntitlementPlan.class_type_included?(plan, request_value(request, :class_type_id)),
       do: {:error, :finance_class_type_not_included},
       else: :ok
  end

  defp require_time_window(plan, request) do
    if request_value(request, :channel) in [nil, :in_person] and
         not EntitlementPlan.within_time_windows?(
           plan,
           request_value(request, :local_weekday),
           request_value(request, :local_time)
         ),
       do: {:error, :finance_time_window_not_included},
       else: :ok
  end

  defp require_location(plan, location_id) do
    if EntitlementPlan.location_included?(plan, location_id),
      do: :ok,
      else: {:error, :finance_location_not_included}
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
