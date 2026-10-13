defmodule MilosTraining.Finance.Domain.SubscriptionSelection do
  @moduledoc """
  Pure ordering and eligibility rules for stacked subscriptions (ADR-096).

  Recurring subscriptions are tried first (newest first) because their
  allowances reset; one-off packages follow by earliest expiry so the units
  that would lapse first are consumed first.
  """

  alias MilosTraining.Finance.Domain.{PackageCatalog, PackageContract, PackageType}

  def order(subscriptions) do
    {one_off, recurring} = Enum.split_with(subscriptions, &one_off?/1)

    recurring =
      Enum.sort_by(recurring, &{date_key(field(&1, :starts_on)), timestamp(&1)}, :desc)

    one_off =
      Enum.sort_by(one_off, &{expiry_key(field(&1, :ends_on)), timestamp(&1)}, :asc)

    recurring ++ one_off
  end

  def one_off?(subscription) do
    case PackageType.fetch(type(subscription)) do
      {:ok, type} -> PackageType.one_off?(type)
      _ -> false
    end
  end

  def type(subscription),
    do: PackageContract.type_from_params(field(subscription, :params_snapshot))

  @doc "Inclusive end date for a new subscription of a package that has a validity."
  def ends_on(%Date{} = starts_on, params) do
    case PackageContract.fields_from_params(params)["terms.validity"] do
      nil -> nil
      validity -> PackageCatalog.duration_end(starts_on, validity)
    end
  end

  @doc """
  Checks trial-style eligibility for a membership's subscription history.
  `history` contains every prior subscription (any status) as maps with
  `:membership_package_id` and `:params_snapshot`.
  """
  def eligible?(package_id, params, history) do
    fields = PackageContract.fields_from_params(params)

    cond do
      fields["terms.once_per_person"] and
          Enum.any?(history, &(field(&1, :membership_package_id) == package_id)) ->
        {:error, :package_already_used}

      fields["terms.new_members_only"] and Enum.any?(history, &(type(&1) != "trial")) ->
        {:error, :package_new_members_only}

      true ->
        :ok
    end
  end

  def renewable?(params) do
    fields = PackageContract.fields_from_params(params)

    with {:ok, type} <- PackageType.fetch(PackageContract.type_from_params(params)),
         true <- PackageType.renewable?(type),
         true <- fields["terms.auto_renew"] do
      :ok
    else
      _ -> {:error, :package_not_renewable}
    end
  end

  defp field(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp date_key(nil), do: 0
  defp date_key(%Date{} = date), do: Date.to_gregorian_days(date)

  defp expiry_key(nil), do: :infinity
  defp expiry_key(%Date{} = date), do: Date.to_gregorian_days(date)

  defp timestamp(subscription) do
    case field(subscription, :inserted_at) do
      %DateTime{} = at ->
        DateTime.to_unix(at, :microsecond)

      %NaiveDateTime{} = at ->
        at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:microsecond)

      _ ->
        0
    end
  end
end
