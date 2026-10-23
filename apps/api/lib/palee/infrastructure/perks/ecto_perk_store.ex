defmodule Palee.Infrastructure.Perks.EctoPerkStore do
  @moduledoc """
  Ecto adapter of partner perks, versions, code pools and claims (ADR-191).

  Every query names the organization in scope as well as relying on RLS.
  Revisions, claims, uses and revocations lock the perk row (`FOR
  UPDATE`) for the whole decision and move `current_version`,
  `claims_count` / `uses_count` in the same transaction, so versioning,
  caps and the single use hold under concurrency; the tables' check
  constraints are the last line (`uses_count <= claims_count`).
  """

  @behaviour Palee.Perks.Ports.PerkStore

  import Ecto.Query

  alias Palee.Perks.{Perk, PerkClaim, PerkCode, PerkVersion}
  alias Palee.Perks.Domain.PerkRules
  alias Palee.Repo

  @export_limit 1_000

  # -- perks and versions ------------------------------------------------------

  @impl true
  def create_perk(%{organization_id: organization_id}, attrs, version_attrs) do
    transaction(fn ->
      perk =
        attrs
        |> Map.put(:organization_id, organization_id)
        |> Perk.create_changeset()
        |> Repo.insert()
        |> or_rollback()

      version = insert_version(perk, %PerkVersion{}, version_attrs, 1)
      perk |> mirror(version) |> Map.put(:version, version)
    end)
  end

  @impl true
  def revise_perk(%{organization_id: organization_id}, %Perk{id: id}, attrs, version_attrs) do
    transaction(fn ->
      perk = lock_perk(organization_id, id) || Repo.rollback(:not_found)
      current = current_version(perk)

      {version, number} =
        case {version_attrs, PerkRules.version_mode(perk)} do
          {nil, _mode} ->
            {current, perk.current_version}

          {version_attrs, :amend} ->
            {current
             |> PerkVersion.changeset(version_attrs, Map.get(attrs, :redemption_method, perk.redemption_method))
             |> Repo.update()
             |> or_rollback(), perk.current_version}

          {version_attrs, :new} ->
            next = perk.current_version + 1
            {insert_version(perk, PerkVersion.next_base(current), version_attrs, next), next}
        end

      perk
      |> Perk.update_changeset(
        Map.merge(attrs, %{
          current_version: number,
          valid_from: version.rules.valid_from,
          valid_until: version.rules.valid_until
        })
      )
      |> Repo.update()
      |> or_rollback()
      |> Map.put(:version, version)
    end)
  end

  defp insert_version(perk, base, version_attrs, number) do
    base
    |> PerkVersion.changeset(version_attrs, perk.redemption_method)
    |> Ecto.Changeset.change(%{
      organization_id: perk.organization_id,
      perk_id: perk.id,
      version: number
    })
    |> Repo.insert()
    |> or_rollback()
  end

  # The perk's window columns follow its current version.
  defp mirror(perk, version) do
    perk
    |> Ecto.Changeset.change(
      valid_from: version.rules.valid_from,
      valid_until: version.rules.valid_until
    )
    |> Ecto.Changeset.check_constraint(:valid_until, name: :perks_window_check)
    |> Repo.update()
    |> or_rollback()
  end

  defp current_version(perk) do
    Repo.one!(
      from v in PerkVersion,
        where:
          v.organization_id == ^perk.organization_id and v.perk_id == ^perk.id and
            v.version == ^perk.current_version
    )
  end

  @impl true
  def set_status(_context, %Perk{} = perk, changes) do
    with {:ok, updated} <- perk |> Perk.status_changeset(changes) |> Repo.update(),
         do: {:ok, Map.put(updated, :version, perk.version)}
  end

  @impl true
  def delete_perk(%{organization_id: organization_id}, %Perk{id: id}) do
    transaction(fn ->
      perk = lock_perk(organization_id, id)

      cond do
        is_nil(perk) ->
          :ok

        perk.claims_count > 0 or claims?(organization_id, id) ->
          Repo.rollback(:perk_has_claims)

        true ->
          {1, _} =
            Repo.delete_all(
              from p in Perk, where: p.id == ^id and p.organization_id == ^organization_id
            )

          :ok
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      error -> error
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
        organization_id |> with_version() |> where([p], p.id == ^id) |> Repo.one() |> loaded()

      :error ->
        nil
    end
  end

  @impl true
  def list_perks(%{organization_id: organization_id}, filters) do
    organization_id
    |> with_version()
    |> statuses(Map.get(filters, :statuses))
    |> ids(Map.get(filters, :ids))
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(500)
    |> Repo.all()
    |> Enum.map(&loaded/1)
  end

  defp with_version(organization_id) do
    from p in Perk,
      join: v in PerkVersion,
      on: v.perk_id == p.id and v.version == p.current_version and v.organization_id == p.organization_id,
      where: p.organization_id == ^organization_id,
      select: {p, v}
  end

  defp loaded(nil), do: nil
  defp loaded({perk, version}), do: %{perk | version: version}

  defp statuses(query, list) when is_list(list), do: where(query, [p], p.status in ^list)
  defp statuses(query, _all), do: query

  defp ids(query, list) when is_list(list), do: where(query, [p], p.id in ^list)
  defp ids(query, _all), do: query

  @impl true
  def list_versions(%{organization_id: organization_id}, perk_id) do
    Repo.all(
      from v in PerkVersion,
        where: v.organization_id == ^organization_id and v.perk_id == ^perk_id,
        order_by: [desc: v.version]
    )
  end

  @impl true
  def get_versions(_context, []), do: %{}

  def get_versions(%{organization_id: organization_id}, keys) do
    perk_ids = keys |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    wanted = MapSet.new(keys)

    from(v in PerkVersion,
      where: v.organization_id == ^organization_id and v.perk_id in ^perk_ids
    )
    |> Repo.all()
    |> Enum.filter(&MapSet.member?(wanted, {&1.perk_id, &1.version}))
    |> Map.new(&{{&1.perk_id, &1.version}, &1})
  end

  # -- code pool -------------------------------------------------------------

  @impl true
  def add_codes(%{organization_id: organization_id}, perk_id, codes) do
    now = DateTime.utc_now()

    added =
      codes
      |> Enum.map(fn code ->
        %{
          id: Ecto.UUID.generate(),
          organization_id: organization_id,
          perk_id: perk_id,
          code: code,
          inserted_at: now
        }
      end)
      |> Enum.chunk_every(1_000)
      |> Enum.reduce(0, fn chunk, total ->
        {count, _} =
          Repo.insert_all(PerkCode, chunk, on_conflict: :nothing, conflict_target: [:perk_id, :code])

        total + count
      end)

    {:ok, %{added: added}}
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

  # -- claims ----------------------------------------------------------------

  @impl true
  def claim(%{organization_id: organization_id}, perk_id, user_id, decide) do
    transaction(fn ->
      perk = lock_perk(organization_id, perk_id) || Repo.rollback(:not_found)
      perk = %{perk | version: current_version(perk)}
      member = member_claims(organization_id, perk.id, user_id)

      facts = %{
        member_claims: length(member),
        open_claim: Enum.find(member, &(&1.status == "claimed")),
        count_since: fn since -> count_since(organization_id, perk.id, user_id, since) end
      }

      case decide.(perk, facts) do
        {:existing, %PerkClaim{} = claim} ->
          %{perk: perk, claim: claim, new?: false, free_codes: nil}

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

  defp count_since(organization_id, perk_id, user_id, %DateTime{} = since) do
    from(c in PerkClaim,
      where:
        c.organization_id == ^organization_id and c.perk_id == ^perk_id and
          c.status != "revoked" and c.claimed_at >= ^since,
      select: %{all: count(c.id), member: filter(count(c.id), c.user_id == ^user_id)}
    )
    |> Repo.one()
  end

  defp insert_claim(organization_id, perk, user_id, attrs) do
    claim_id = Ecto.UUID.generate()

    {code, free} =
      if Map.get(attrs, :issue) == :pool,
        do: take_code(perk, claim_id, attrs.claimed_at),
        else: {Map.get(attrs, :code), nil}

    claim =
      attrs
      |> Map.drop([:issue])
      |> Map.merge(%{
        id: claim_id,
        organization_id: organization_id,
        perk_id: perk.id,
        perk_version: perk.current_version,
        user_id: user_id,
        code: code
      })
      |> PerkClaim.create_changeset()
      |> Repo.insert()
      |> or_rollback()

    {1, [counted]} =
      Repo.update_all(
        from(p in Perk, where: p.id == ^perk.id and p.organization_id == ^organization_id, select: p),
        inc: [claims_count: 1]
      )

    %{perk: %{counted | version: perk.version}, claim: claim, new?: true, free_codes: free}
  end

  # The perk row is locked, so the oldest free code is taken without racing
  # another claim of the same perk; SKIP LOCKED keeps a concurrent upload
  # from blocking it.
  defp take_code(perk, claim_id, at) do
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

    left =
      Repo.one(
        from c in PerkCode,
          where:
            c.organization_id == ^perk.organization_id and c.perk_id == ^perk.id and
              is_nil(c.claim_id),
          select: count(c.id)
      )

    {free.code, left}
  end

  @impl true
  def use_claim(%{organization_id: organization_id}, claim_id, via, actor_id, at, check) do
    transaction(fn ->
      claim = get_claim_row(organization_id, claim_id) || Repo.rollback(:not_found)
      perk = lock_perk(organization_id, claim.perk_id) || Repo.rollback(:not_found)
      perk = %{perk | version: current_version(perk)}
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
        {1, [counted]} =
          Repo.update_all(
            from(p in Perk, where: p.id == ^perk.id and p.organization_id == ^organization_id, select: p),
            inc: [uses_count: 1]
          )

        %{perk: %{counted | version: perk.version}, claim: used}
      else
        {0, _} -> Repo.rollback(:perk_claim_already_used)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def revoke_claim(%{organization_id: organization_id}, claim_id, actor_id, at) do
    transaction(fn ->
      claim = get_claim_row(organization_id, claim_id) || Repo.rollback(:not_found)
      perk = lock_perk(organization_id, claim.perk_id) || Repo.rollback(:not_found)
      claim = lock_claim(organization_id, claim.id)

      if claim.status != "claimed", do: Repo.rollback(:perk_claim_not_open)

      revoked = claim |> PerkClaim.revoke_changeset(actor_id, at) |> Repo.update() |> or_rollback()

      {1, [counted]} =
        Repo.update_all(
          from(p in Perk,
            where: p.id == ^perk.id and p.organization_id == ^organization_id and p.claims_count > 0,
            select: p
          ),
          inc: [claims_count: -1]
        )

      %{perk: counted, claim: revoked}
    end)
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
        Repo.one(from c in PerkClaim, where: c.id == ^id and c.organization_id == ^organization_id)

      :error ->
        nil
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
      perk_version: c.perk_version,
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

  # -- member facts ------------------------------------------------------------

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

  @impl true
  def group_ids(%{organization_id: organization_id}) do
    from(c in "community_channels",
      where: c.organization_id == type(^organization_id, :binary_id) and c.status == "active",
      select: type(c.id, :binary_id)
    )
    |> Repo.all()
  end

  @impl true
  def member_group_ids(%{organization_id: organization_id}, user_id) do
    from(m in "community_channel_memberships",
      where: m.organization_id == type(^organization_id, :binary_id),
      where: m.user_id == type(^user_id, :binary_id),
      select: type(m.channel_id, :binary_id)
    )
    |> Repo.all()
  end

  @impl true
  def member_first_name(_context, user_id) do
    from(u in "users",
      where: u.id == type(^user_id, :binary_id),
      select: {u.display_nickname, u.nickname}
    )
    |> Repo.one()
    |> case do
      nil -> nil
      {name, handle} -> (name || handle || "") |> String.split(~r/\s+/u, trim: true) |> List.first()
    end
  end

  # -- helpers -----------------------------------------------------------------

  defp transaction(fun) do
    case Repo.transaction(fun) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp or_rollback({:ok, value}), do: value
  defp or_rollback({:error, reason}), do: Repo.rollback(reason)
end
