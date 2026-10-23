defmodule Palee.Infrastructure.Perks.EctoPerkStore do
  @moduledoc """
  Ecto adapter of partner perks, code pools and claims (ADR-191).

  Every query names the organization in scope as well as relying on RLS.
  Claims and uses lock the perk row (`FOR UPDATE`) for the whole decision,
  and move `claims_count` / `uses_count` in the same transaction, so caps
  and the single use hold under concurrency; the table's check constraints
  are the last line (`claims_count <= max_claims`, `uses_count <=
  claims_count`).
  """

  @behaviour Palee.Perks.Ports.PerkStore

  import Ecto.Query

  alias Palee.Perks.{Perk, PerkClaim, PerkCode}
  alias Palee.Repo

  @export_limit 1_000

  @impl true
  def create_perk(%{organization_id: organization_id}, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> Perk.create_changeset()
    |> Repo.insert()
  end

  @impl true
  def update_perk(_context, %Perk{} = perk, attrs),
    do: perk |> Perk.update_changeset(attrs) |> Repo.update()

  @impl true
  def set_status(_context, %Perk{} = perk, changes),
    do: perk |> Perk.status_changeset(changes) |> Repo.update()

  @impl true
  def delete_perk(%{organization_id: organization_id}, %Perk{id: id}) do
    Repo.transaction(fn ->
      perk = lock_perk(organization_id, id)

      cond do
        is_nil(perk) ->
          :ok

        perk.claims_count > 0 or claims?(organization_id, id) ->
          Repo.rollback(:perk_has_claims)

        true ->
          {_count, _} =
            Repo.delete_all(
              from p in Perk, where: p.id == ^id and p.organization_id == ^organization_id
            )

          :ok
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp claims?(organization_id, perk_id),
    do:
      Repo.exists?(
        from c in PerkClaim, where: c.organization_id == ^organization_id and c.perk_id == ^perk_id
      )

  @impl true
  def get_perk(%{organization_id: organization_id}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Repo.one(from p in Perk, where: p.id == ^id and p.organization_id == ^organization_id)

      :error ->
        nil
    end
  end

  @impl true
  def list_perks(%{organization_id: organization_id}, filters) do
    Perk
    |> where([p], p.organization_id == ^organization_id)
    |> statuses(Map.get(filters, :statuses))
    |> ids(Map.get(filters, :ids))
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(500)
    |> Repo.all()
  end

  defp statuses(query, list) when is_list(list), do: where(query, [p], p.status in ^list)
  defp statuses(query, _all), do: query

  defp ids(query, list) when is_list(list), do: where(query, [p], p.id in ^list)
  defp ids(query, _all), do: query

  @impl true
  def add_codes(%{organization_id: organization_id}, perk_id, codes) do
    now = DateTime.utc_now()

    rows =
      Enum.map(codes, fn code ->
        %{
          id: Ecto.UUID.generate(),
          organization_id: organization_id,
          perk_id: perk_id,
          code: code,
          inserted_at: now
        }
      end)

    {added, _} =
      rows
      |> Enum.chunk_every(1_000)
      |> Enum.reduce({0, nil}, fn chunk, {total, _} ->
        {count, _} =
          Repo.insert_all(PerkCode, chunk, on_conflict: :nothing, conflict_target: [:perk_id, :code])

        {total + count, nil}
      end)

    {:ok, %{added: added, duplicates: length(codes) - added}}
  end

  @impl true
  def code_stats(_context, []), do: %{}

  def code_stats(%{organization_id: organization_id}, perk_ids) do
    from(c in PerkCode,
      where: c.organization_id == ^organization_id and c.perk_id in ^perk_ids,
      group_by: c.perk_id,
      select: {c.perk_id, count(c.id), filter(count(c.id), is_nil(c.claim_id))}
    )
    |> Repo.all()
    |> Map.new(fn {perk_id, total, free} -> {perk_id, %{total: total, free: free}} end)
  end

  @impl true
  def claim(%{organization_id: organization_id}, perk_id, user_id, decide) do
    Repo.transaction(fn ->
      perk = lock_perk(organization_id, perk_id) || Repo.rollback(:not_found)
      member = member_claims(organization_id, perk.id, user_id)

      facts = %{
        member_claims: length(member),
        open_claim: Enum.find(member, &(&1.status == "claimed"))
      }

      case decide.(perk, facts) do
        {:existing, %PerkClaim{} = claim} ->
          %{perk: perk, claim: claim, new?: false}

        {:new, attrs} ->
          insert_claim(organization_id, perk, user_id, attrs)

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp member_claims(organization_id, perk_id, user_id) do
    Repo.all(
      from c in PerkClaim,
        where:
          c.organization_id == ^organization_id and c.perk_id == ^perk_id and
            c.user_id == ^user_id and c.status != "revoked",
        order_by: [desc: c.claimed_at]
    )
  end

  defp insert_claim(organization_id, perk, user_id, attrs) do
    claim_id = Ecto.UUID.generate()
    pool_code = if perk.redemption_method == "unique_code", do: take_code(perk, claim_id, attrs)

    claim =
      attrs
      |> Map.merge(%{
        id: claim_id,
        organization_id: organization_id,
        perk_id: perk.id,
        user_id: user_id
      })
      |> then(&if(pool_code, do: Map.put(&1, :code, pool_code), else: &1))
      |> PerkClaim.create_changeset()
      |> Repo.insert()
      |> case do
        {:ok, claim} -> claim
        {:error, changeset} -> Repo.rollback(changeset)
      end

    {1, [perk]} =
      Repo.update_all(
        from(p in Perk,
          where: p.id == ^perk.id and p.organization_id == ^organization_id,
          select: p
        ),
        inc: [claims_count: 1]
      )

    %{perk: perk, claim: claim, new?: true}
  end

  # The perk row is locked, so the oldest free code is taken without racing
  # another claim of the same perk; SKIP LOCKED keeps a concurrent upload or
  # staff action on another code from blocking it.
  defp take_code(perk, claim_id, %{claimed_at: at}) do
    free =
      Repo.one(
        from c in PerkCode,
          where:
            c.organization_id == ^perk.organization_id and c.perk_id == ^perk.id and
              is_nil(c.claim_id),
          order_by: [asc: c.inserted_at, asc: c.id],
          limit: 1,
          lock: "FOR UPDATE SKIP LOCKED"
      ) || Repo.rollback(:perk_codes_exhausted)

    {1, _} =
      Repo.update_all(
        from(c in PerkCode, where: c.id == ^free.id and is_nil(c.claim_id)),
        set: [claim_id: claim_id, assigned_at: at]
      )

    free.code
  end

  @impl true
  def use_claim(%{organization_id: organization_id}, claim_id, via, actor_id, at, check) do
    Repo.transaction(fn ->
      claim = get_claim_row(organization_id, claim_id) || Repo.rollback(:not_found)
      perk = lock_perk(organization_id, claim.perk_id) || Repo.rollback(:not_found)
      claim = lock_claim(organization_id, claim.id)

      with :ok <- check.(perk, claim),
           {1, [used]} <-
             Repo.update_all(
               from(c in PerkClaim,
                 where:
                   c.id == ^claim.id and c.organization_id == ^organization_id and
                     c.status == "claimed" and is_nil(c.used_at),
                 select: c
               ),
               set: [
                 status: "used",
                 used_at: at,
                 used_via: via,
                 used_by_id: actor_id,
                 token_hash: nil,
                 updated_at: at
               ]
             ) do
        {1, [perk]} =
          Repo.update_all(
            from(p in Perk, where: p.id == ^perk.id and p.organization_id == ^organization_id, select: p),
            inc: [uses_count: 1]
          )

        %{perk: perk, claim: used}
      else
        {0, _} -> Repo.rollback(:perk_claim_already_used)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def revoke_claim(%{organization_id: organization_id}, claim_id, actor_id, at) do
    Repo.transaction(fn ->
      claim = get_claim_row(organization_id, claim_id) || Repo.rollback(:not_found)
      perk = lock_perk(organization_id, claim.perk_id) || Repo.rollback(:not_found)
      claim = lock_claim(organization_id, claim.id)

      if claim.status != "claimed", do: Repo.rollback(:perk_claim_not_open)

      revoked =
        case claim |> PerkClaim.revoke_changeset(actor_id, at) |> Repo.update() do
          {:ok, revoked} -> revoked
          {:error, changeset} -> Repo.rollback(changeset)
        end

      {1, [perk]} =
        Repo.update_all(
          from(p in Perk,
            where: p.id == ^perk.id and p.organization_id == ^organization_id and p.claims_count > 0,
            select: p
          ),
          inc: [claims_count: -1]
        )

      %{perk: perk, claim: revoked}
    end)
  end

  defp lock_perk(organization_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Repo.one(
          from p in Perk,
            where: p.id == ^id and p.organization_id == ^organization_id,
            lock: "FOR UPDATE"
        )

      :error ->
        nil
    end
  end

  defp lock_claim(organization_id, id),
    do:
      Repo.one!(
        from c in PerkClaim,
          where: c.id == ^id and c.organization_id == ^organization_id,
          lock: "FOR UPDATE"
      )

  defp get_claim_row(organization_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Repo.one(
          from c in PerkClaim, where: c.id == ^id and c.organization_id == ^organization_id
        )

      :error ->
        nil
    end
  end

  @impl true
  def rotate_token(%{organization_id: organization_id}, claim_id, user_id, token_hash) do
    query =
      from c in PerkClaim,
        where:
          c.id == ^claim_id and c.organization_id == ^organization_id and c.user_id == ^user_id and
            c.status == "claimed" and not is_nil(c.token_hash),
        select: c

    case Repo.update_all(query, set: [token_hash: token_hash, updated_at: DateTime.utc_now()]) do
      {1, [claim]} -> {:ok, claim}
      {0, _} -> {:error, :perk_claim_not_open}
    end
  end

  @impl true
  def get_claim(%{organization_id: organization_id}, id), do: get_claim_row(organization_id, id)

  @impl true
  def list_member_claims(%{organization_id: organization_id}, user_id) do
    Repo.all(
      from c in PerkClaim,
        where: c.organization_id == ^organization_id and c.user_id == ^user_id,
        order_by: [desc: c.claimed_at, desc: c.id],
        limit: 500
    )
  end

  @impl true
  def list_claims(%{organization_id: organization_id}, perk_id, opts) do
    limit = opts |> Map.get(:limit, @export_limit) |> min(@export_limit)

    PerkClaim
    |> join(:left, [c], u in "users", on: u.id == c.user_id)
    |> where([c], c.organization_id == ^organization_id and c.perk_id == ^perk_id)
    |> after_cursor(Map.get(opts, :after))
    |> order_by([c], asc: c.claimed_at, asc: c.id)
    |> limit(^limit)
    |> select([c, u], %{
      id: c.id,
      user_id: c.user_id,
      display_name: u.display_nickname,
      handle: u.nickname,
      code: c.code,
      status: c.status,
      claimed_at: c.claimed_at,
      used_at: c.used_at,
      used_via: c.used_via,
      revoked_at: c.revoked_at
    })
    |> Repo.all()
  end

  defp after_cursor(query, {%DateTime{} = at, id}),
    do: where(query, [c], c.claimed_at > ^at or (c.claimed_at == ^at and c.id > ^id))

  defp after_cursor(query, _none), do: query

  @impl true
  def member_package_ids(%{organization_id: organization_id}, user_id, today) do
    from(s in "membership_package_subscriptions",
      join: m in "memberships",
      on: m.id == s.membership_id,
      where: s.organization_id == type(^organization_id, :binary_id),
      where: m.user_id == type(^user_id, :binary_id),
      where: s.status in ["active", "paused"],
      where: is_nil(s.ends_on) or s.ends_on >= ^today,
      where: not is_nil(s.membership_package_id),
      distinct: true,
      select: type(s.membership_package_id, :binary_id)
    )
    |> Repo.all()
  end
end
