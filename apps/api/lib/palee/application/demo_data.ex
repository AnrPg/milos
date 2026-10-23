defmodule Palee.Application.DemoData do
  @moduledoc """
  ADR-184: the floating «demo data» button of every admin screen of a demo
  business.

  - `status/1`: the business's activation state and which sections hold
    demo data.
  - `seed/3`: fills one section (or `"all"`) through the seeders registered
    in `Application.DemoSeeders`; sections it needs are filled first, a
    section already filled is left alone. One transaction per call; every
    row written is tracked in `demo_records`.
  - `remove/1` and `wipe/1`: delete exactly the tracked rows, mock people
    first (their bookings, finance memberships and invoices go with them).

  Owners and admins only, and only while the business is in demo mode: an
  active business never gets mock data.
  """

  alias Palee.Application.DemoSeeders
  alias Palee.{BusinessAccounts, Identity, Organizations}

  def status(context) do
    with :ok <- authorize(context) do
      {:ok, describe(context)}
    end
  end

  def seed(context, section, now \\ DateTime.utc_now()) when is_binary(section) do
    with :ok <- authorize(context),
         :ok <- demo_only(context),
         seeded = seeded_rows(context),
         {:ok, plan} <- DemoSeeders.plan(section, Map.keys(seeded)),
         {:ok, _rows} <-
           BusinessAccounts.transaction(fn -> run(plan, context, seeded, now) end) do
      {:ok, describe(context)}
    end
  end

  def remove(context) do
    with :ok <- authorize(context),
         :ok <- demo_only(context),
         {:ok, _removed} <- BusinessAccounts.transaction(fn -> wipe(context) end) do
      {:ok, describe(context)}
    end
  end

  @doc """
  Deletes every tracked demo row of the business in the caller's
  transaction. Used by `remove/1`, by activation and by the abandoned-demo
  sweep; the caller authorizes. `opts[:keep_user_ids]` are accounts that are
  never deleted even if a record named them (the sweep passes the owners).
  """
  def wipe(context, opts \\ []) do
    keep = MapSet.new(Keyword.get(opts, :keep_user_ids, []))
    records = BusinessAccounts.list_demo_records(context)

    people =
      for %{source: "users", record_id: id} <- records,
          not MapSet.member?(keep, id),
          do: id

    with :ok <- delete_people(people),
         :ok <- BusinessAccounts.delete_demo_rows(context, records),
         :ok <- BusinessAccounts.clear_demo_records(context) do
      {:ok, %{rows: length(records), people: length(people)}}
    end
  end

  defp run(plan, context, seeded, now) do
    Enum.reduce_while(plan, {:ok, seeded}, fn seeder, {:ok, seeded} ->
      section = seeder.section()

      with {:ok, rows} <- seeder.seed(context, seeded, now),
           :ok <- check_sources(seeder, rows),
           :ok <- BusinessAccounts.track_demo_records(context, section, rows) do
        {:cont, {:ok, Map.put(seeded, section, rows)}}
      else
        error -> {:halt, error}
      end
    end)
  end

  # A seeder may only write the tables it declares, and those must be
  # tables the wipe can delete: otherwise activation would leave them behind.
  defp check_sources(seeder, rows) do
    allowed = MapSet.new(seeder.sources())
    deletable = MapSet.new(["users" | BusinessAccounts.demo_deletable_sources()])

    if Enum.all?(rows, fn {source, _id} ->
         MapSet.member?(allowed, source) and MapSet.member?(deletable, source)
       end),
       do: :ok,
       else: {:error, :demo_source_not_deletable}
  end

  defp delete_people(user_ids) do
    Enum.reduce_while(user_ids, :ok, fn user_id, :ok ->
      case Identity.find_by_id(user_id) do
        nil ->
          {:cont, :ok}

        user ->
          case Identity.delete_tenant_scoped_user(user) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
      end
    end)
  end

  defp seeded_rows(context) do
    context
    |> BusinessAccounts.list_demo_records()
    |> Enum.group_by(& &1.section, &{&1.source, &1.record_id})
  end

  defp describe(context) do
    status = Organizations.business_status(context)
    counts = if status.gated, do: counts(context), else: %{}

    Map.merge(status, %{
      sections:
        Enum.map(DemoSeeders.sections(), fn section ->
          rows = Map.get(counts, section, 0)
          %{section: section, seeded: rows > 0, rows: rows}
        end)
    })
  end

  defp counts(context),
    do: context |> BusinessAccounts.list_demo_records() |> Enum.frequencies_by(& &1.section)

  defp authorize(context) do
    if Organizations.any_role?(context, [:owner, :admin]),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp demo_only(context) do
    if Organizations.business_gated?(context), do: :ok, else: {:error, :business_already_active}
  end
end
