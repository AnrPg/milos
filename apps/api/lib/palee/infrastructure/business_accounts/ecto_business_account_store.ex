defmodule Palee.Infrastructure.BusinessAccounts.EctoBusinessAccountStore do
  @moduledoc "Ecto adapter of `BusinessAccounts.Ports.BusinessAccountStore` (ADR-184)."

  @behaviour Palee.BusinessAccounts.Ports.BusinessAccountStore

  import Ecto.Query

  alias Palee.BusinessAccounts.{ActivationLink, BusinessRequest, DemoRecord}
  alias Palee.Repo

  # The tables demo seeders may write, so the only tables the generic
  # deletion below may ever touch. Each one has `id` and `organization_id`.
  # Accounts (`users`) are deleted through Identity by the application.
  @deletable_sources ~w(
    organization_memberships
    class_types scheduled_classes bookings
    membership_packages memberships membership_payments finance_invoices
    master_workouts
    appointment_slots
  )

  @impl true
  def deletable_sources, do: @deletable_sources

  @impl true
  def transaction(fun) do
    if Repo.in_transaction?() do
      fun.()
    else
      Repo.transaction(fn ->
        case fun.() do
          {:ok, value} -> value
          {:error, reason} -> Repo.rollback(reason)
          other -> Repo.rollback({:unexpected, other})
        end
      end)
    end
  end

  @impl true
  def issue_activation_link(attrs, now) do
    transaction(fn ->
      from(link in ActivationLink,
        where:
          link.organization_id == ^attrs.organization_id and is_nil(link.redeemed_at) and
            is_nil(link.revoked_at)
      )
      |> Repo.update_all(set: [revoked_at: now, updated_at: now])

      attrs |> ActivationLink.issue_changeset() |> Repo.insert()
    end)
  end

  @impl true
  def revoke_activation_link(link_id, now) do
    case Repo.get(ActivationLink, link_id) do
      %ActivationLink{redeemed_at: nil, revoked_at: nil} = link ->
        link |> ActivationLink.revoke_changeset(now) |> Repo.update()

      _missing_or_spent ->
        {:error, :not_found}
    end
  end

  @impl true
  def list_activation_links(:all),
    do: ActivationLink |> order_by(desc: :inserted_at) |> Repo.all()

  def list_activation_links(organization_ids) when is_list(organization_ids) do
    ActivationLink
    |> where([link], link.organization_id in ^organization_ids)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @impl true
  def get_activation_link_by_digest(digest),
    do: Repo.get_by(ActivationLink, token_digest: digest)

  @impl true
  def activate_business(digest, now) do
    case Repo.query("SELECT palee_activate_business($1, $2)", [digest, now]) do
      {:ok, %{rows: [[organization_id]]}} ->
        {:ok, Ecto.UUID.cast!(organization_id)}

      {:error, %Postgrex.Error{postgres: %{message: "business_already_active"}}} ->
        {:error, :business_already_active}

      {:error, %Postgrex.Error{postgres: %{message: "invalid_activation_link"}}} ->
        {:error, :invalid_activation_link}
    end
  end

  @impl true
  def create_request(attrs), do: attrs |> BusinessRequest.create_changeset() |> Repo.insert()

  @impl true
  def get_request(id), do: Repo.get(BusinessRequest, id)

  @impl true
  def list_requests(filters) do
    BusinessRequest
    |> filter_requests(filters)
    |> order_by([request], asc: request.inserted_at)
    |> limit(500)
    |> Repo.all()
  end

  defp filter_requests(query, filters) do
    Enum.reduce(filters, query, fn
      {:user_id, user_id}, query -> where(query, [request], request.user_id == ^user_id)
      {:status, status}, query -> where(query, [request], request.status == ^status)
      {:kind, kind}, query -> where(query, [request], request.kind == ^kind)
      {:organization_id, id}, query -> where(query, [request], request.organization_id == ^id)
      _other, query -> query
    end)
  end

  @impl true
  def update_request(_request, changeset), do: Repo.update(changeset)

  @impl true
  def track_demo_records(_organization_id, _section, []), do: :ok

  def track_demo_records(organization_id, section, rows) do
    now = DateTime.utc_now()

    entries =
      Enum.map(rows, fn {source, record_id} ->
        %{
          organization_id: organization_id,
          section: section,
          source: source,
          record_id: record_id,
          inserted_at: now
        }
      end)

    Repo.insert_all(DemoRecord, entries, on_conflict: :nothing)
    :ok
  end

  @impl true
  def list_demo_records(organization_id) do
    DemoRecord
    |> where([record], record.organization_id == ^organization_id)
    |> order_by(asc: :id)
    |> Repo.all()
  end

  # Newest first, one statement per run of the same table, so children
  # seeded after their parents (bookings after classes) go first.
  @impl true
  def delete_demo_rows(organization_id, records) do
    records
    |> Enum.filter(&(&1.source in @deletable_sources))
    |> Enum.sort_by(& &1.id, :desc)
    |> Enum.chunk_by(& &1.source)
    |> Enum.each(fn [%{source: source} | _rest] = chunk ->
      ids = Enum.map(chunk, & &1.record_id)

      from(row in source,
        where:
          field(row, :organization_id) == type(^organization_id, Ecto.UUID) and
            field(row, :id) in type(^ids, {:array, Ecto.UUID})
      )
      |> Repo.delete_all()
    end)

    :ok
  end

  @impl true
  def clear_demo_records(organization_id) do
    DemoRecord |> where([record], record.organization_id == ^organization_id) |> Repo.delete_all()
    :ok
  end

  @impl true
  def demo_person?(organization_id, user_id) do
    DemoRecord
    |> where(
      [record],
      record.organization_id == ^organization_id and record.source == "users" and
        record.record_id == ^user_id
    )
    |> Repo.exists?()
  end

  @impl true
  def notification_suppressed?(organization_id, user_id) when is_binary(user_id) do
    case Repo.query("SELECT palee_notification_suppressed($1, $2)", [
           dump(organization_id),
           Ecto.UUID.dump!(user_id)
         ]) do
      {:ok, %{rows: [[suppressed]]}} -> suppressed == true
      _error -> false
    end
  end

  def notification_suppressed?(_organization_id, _user_id), do: false

  defp dump(nil), do: nil

  defp dump(id) do
    case Ecto.UUID.dump(id) do
      {:ok, binary} -> binary
      :error -> nil
    end
  end
end
