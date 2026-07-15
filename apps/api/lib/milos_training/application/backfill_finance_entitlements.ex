defmodule MilosTraining.Application.BackfillFinanceEntitlements do
  @moduledoc """
  Idempotently prepares legacy members and athletes for strict entitlement enforcement.

  Dry-run and apply use the same classifier. The service crosses Identity and
  Finance only through their public APIs and never imports either context's schemas.
  """

  alias MilosTraining.{Finance, Identity}
  alias MilosTraining.Finance.Domain.EntitlementPlan

  def call(params) when is_map(params) do
    dry_run? = value(params, :dry_run, true)
    packages = value(params, :package_by_role, %{})

    with {:ok, targets} <- validate_packages(packages) do
      users =
        Identity.list_all_users()
        |> Enum.filter(&(normalize_role(&1.role) in ["member", "athlete"]))

      actions = Enum.map(users, &classify(&1, targets))

      if dry_run? do
        {:ok, report(actions, true, 0, [])}
      else
        {applied, failures} = apply_actions(actions)
        {:ok, report(actions, false, applied, failures)}
      end
    end
  end

  defp validate_packages(packages) do
    Enum.reduce_while(packages, {:ok, %{}}, fn {role, package_id}, {:ok, acc} ->
      role = normalize_role(role)
      package = Finance.get_package(package_id)

      result =
        cond do
          role not in ["member", "athlete"] -> {:error, :invalid_role}
          is_nil(package) -> {:error, :not_found}
          true -> EntitlementPlan.parse(package.params || %{})
        end

      case result do
        {:ok, _plan} -> {:cont, {:ok, Map.put(acc, role, package_id)}}
        {:error, reason} -> {:halt, {:error, {:invalid_backfill_package, role, reason}}}
      end
    end)
  end

  defp classify(user, targets) do
    role = normalize_role(user.role)
    profile = Finance.get_member_profile(user.id)
    package_id = Map.get(targets, role)

    action =
      cond do
        profile && profile.active_package_subscription -> :unchanged
        is_nil(package_id) -> :missing_package_mapping
        is_nil(profile) -> :create_and_assign
        true -> :assign
      end

    %{user_id: user.id, role: role, action: action, package_id: package_id, profile: profile}
  end

  defp apply_actions(actions) do
    Enum.reduce(actions, {0, []}, fn action, {applied, failures} ->
      case apply_action(action) do
        :unchanged ->
          {applied, failures}

        {:ok, _} ->
          {applied + 1, failures}

        {:error, reason} ->
          {applied, [%{user_id: action.user_id, reason: inspect(reason)} | failures]}
      end
    end)
  end

  defp apply_action(%{action: :unchanged}), do: :unchanged
  defp apply_action(%{action: :missing_package_mapping}), do: {:error, :missing_package_mapping}

  defp apply_action(action) do
    with {:ok, membership} <- ensure_membership(action),
         {:ok, subscription} <-
           Finance.assign_package(membership.id, action.package_id, %{
             starts_on: Date.utc_today(),
             status: "active",
             params: %{
               "backfilled_by" => "TD-017",
               "backfilled_on" => Date.to_iso8601(Date.utc_today())
             }
           }) do
      {:ok, subscription}
    end
  end

  defp ensure_membership(%{profile: %{membership: membership}}), do: {:ok, membership}

  defp ensure_membership(action) do
    Finance.upsert_membership(action.user_id, %{
      user_type_snapshot: action.role,
      status: "active",
      signup_source: "migrated",
      starts_on: Date.utc_today(),
      params: %{"backfilled_by" => "TD-017"}
    })
  end

  defp report(actions, dry_run?, applied, failures) do
    action_counts = Enum.frequencies_by(actions, & &1.action)

    unresolved =
      Map.get(action_counts, :create_and_assign, 0) + Map.get(action_counts, :assign, 0) +
        Map.get(action_counts, :missing_package_mapping, 0)

    %{
      dry_run: dry_run?,
      ready: if(dry_run?, do: unresolved == 0, else: failures == []),
      counts: %{
        total: length(actions),
        unchanged: Map.get(action_counts, :unchanged, 0),
        create_and_assign: Map.get(action_counts, :create_and_assign, 0),
        assign: Map.get(action_counts, :assign, 0),
        missing_package_mapping: Map.get(action_counts, :missing_package_mapping, 0),
        applied: applied,
        failed: length(failures)
      },
      actions: Enum.map(actions, &Map.take(&1, [:user_id, :role, :action, :package_id])),
      failures: Enum.reverse(failures)
    }
  end

  defp normalize_role(role) when is_atom(role), do: Atom.to_string(role)
  defp normalize_role(role) when is_binary(role), do: role
  defp normalize_role(_), do: "unknown"

  defp value(map, key, default), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
