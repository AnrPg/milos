defmodule Palee.Infrastructure.Finance.EctoPackageRequestStore do
  @moduledoc "ADR-291: packages waiting to be paid at the front desk, in Postgres (RLS by tenant)."

  @behaviour Palee.Finance.Ports.PackageRequestStore

  import Ecto.Query

  alias Palee.Finance.PackageRequest
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  @impl true
  def request(params) do
    Repo.transaction(fn ->
      today = Map.fetch!(params, :today)

      case open_for(params.user_id, params.membership_package_id) do
        %PackageRequest{} = existing ->
          if Date.compare(existing.hold_until, today) == :lt do
            # Its 14 days ended before the hourly run closed it.
            lapse!(existing)
            insert!(params)
          else
            {normalize(existing), :existing}
          end

        nil ->
          insert!(params)
      end
    end)
    |> case do
      {:ok, {request, how}} -> {:ok, request, how}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lapse!(request) do
    now = DateTime.utc_now()

    request
    |> PackageRequest.close_changeset(%{status: "lapsed", closed_at: now})
    |> Repo.update!()
  end

  defp insert!(params) do
    params
    |> PackageRequest.create_changeset()
    |> Repo.insert()
    |> case do
      {:ok, request} -> {normalize(request), :created}
      {:error, changeset} -> Repo.rollback(conflict_or(changeset))
    end
  end

  # Two presses at once: the unique index refuses the second insert.
  defp conflict_or(%Ecto.Changeset{errors: errors} = changeset) do
    if Keyword.has_key?(errors, :organization_id), do: :package_request_exists, else: changeset
  end

  defp open_for(user_id, package_id) do
    PackageRequest
    |> tenant_scope()
    |> where([r], r.user_id == ^user_id and r.membership_package_id == ^package_id)
    |> where([r], r.status == "pending")
    |> Repo.one()
  end

  @impl true
  def get(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        PackageRequest |> tenant_scope() |> where([r], r.id == ^id) |> Repo.one() |> normalize()

      :error ->
        nil
    end
  end

  @impl true
  def list_open(%Date{} = today, opts) do
    PackageRequest
    |> tenant_scope()
    |> where([r], r.status == "pending" and r.hold_until >= ^today)
    |> maybe_user(opts[:user_id])
    |> maybe_users(opts[:user_ids])
    |> order_by([r], asc: r.inserted_at, asc: r.id)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  defp maybe_user(query, nil), do: query
  defp maybe_user(query, user_id), do: where(query, [r], r.user_id == ^user_id)

  defp maybe_users(query, nil), do: query
  defp maybe_users(query, user_ids), do: where(query, [r], r.user_id in ^user_ids)

  @impl true
  def close(id, status, params) do
    Repo.transaction(fn ->
      with {:ok, id} <- Ecto.UUID.cast(id),
           %PackageRequest{} = request <- locked(id) do
        if request.status == "pending" do
          request
          |> PackageRequest.close_changeset(Map.put(params, :status, status))
          |> Repo.update()
          |> case do
            {:ok, closed} -> normalize(closed)
            {:error, changeset} -> Repo.rollback(changeset)
          end
        else
          Repo.rollback({:package_request_closed, request.status})
        end
      else
        _ -> Repo.rollback(:not_found)
      end
    end)
  end

  defp locked(id) do
    PackageRequest
    |> tenant_scope()
    |> where([r], r.id == ^id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  @impl true
  def lapse_before(%Date{} = today, %DateTime{} = now) do
    {count, _rows} =
      PackageRequest
      |> tenant_scope()
      |> where([r], r.status == "pending" and r.hold_until < ^today)
      |> Repo.update_all(set: [status: "lapsed", closed_at: now, updated_at: now])

    count
  end

  defp tenant_scope(queryable) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        from(row in queryable, where: field(row, :organization_id) == ^organization_id)

      _ ->
        from(row in queryable, where: false)
    end
  end

  defp normalize(nil), do: nil

  defp normalize(%PackageRequest{} = request) do
    request
    |> Map.from_struct()
    |> Map.drop([:__meta__])
  end
end
