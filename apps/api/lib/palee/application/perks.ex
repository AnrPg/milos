defmodule Palee.Application.Perks do
  @moduledoc """
  Staff run the business's partner perks (ADR-191): the list with claim and
  use counts, create and edit, publish, pause and end, the pool of unique
  codes, the claims export, and marking a claim used or revoking it.

  Rules on top of `Perks` (pure in `Domain.PerkRules`):

    * Capability `manage_perks` (route level); branches follow ADR-186 §8:
      a perk is a covering item, visible to branch staff when it is valid
      everywhere or at one of their branches, and created or changed only
      inside their branches.
    * A business in demo mode (ADR-184) drafts perks but can't publish
      them (`business_not_activated`).
    * A unique-code perk can't go live with an empty pool.
    * The partner logo is one of the business's ready `box_photo` uploads,
      released when replaced.
    * Publishing, pausing, ending, claims, uses and revocations are each
      recorded as an analytics event (the audit trail) with a
      `[:palee, :perk, ...]` telemetry event.
  """

  alias Palee.Application.{BoxPhotoCovers, CoveringBranches, PerkPresenter, TrackAnalyticsEvent}
  alias Palee.{Facility, Finance, Organizations, Perks}

  @doc "`GET …/admin/perks`: the perks the acting staff see, with counts."
  def list(context, params \\ %{}) do
    filters =
      case Map.get(params, :status) do
        status when is_binary(status) -> %{statuses: stored_statuses(status)}
        _all -> %{}
      end

    today = today(context)

    perks =
      context
      |> Perks.list_perks(filters)
      |> visible(context)
      |> Enum.filter(&status_matches?(&1, Map.get(params, :status), today))

    %{perks: PerkPresenter.staff_all(context, perks, today)}
  end

  # A published perk past its window reads as expired, so the filter asks
  # for both stored statuses and keeps the effective one.
  defp stored_statuses("expired"), do: ["published", "expired"]
  defp stored_statuses(status), do: [status]

  defp status_matches?(_perk, nil, _today), do: true
  defp status_matches?(perk, status, today), do: Perks.effective_status(perk, today) == status

  @doc "`GET …/admin/perks/:id`."
  def show(context, id) do
    with {:ok, perk} <- fetch(context, id),
         do: {:ok, PerkPresenter.staff(context, perk, today(context))}
  end

  @doc "`POST …/admin/perks`: a new draft."
  def create(context, params) do
    with {:ok, target} <- CoveringBranches.for_new(context, CoveringBranches.requested(params)),
         :ok <- known_locations(context, target),
         :ok <- known_packages(context, params),
         :ok <- logo_ready(context, Map.get(params, :logo_media_id)),
         {:ok, perk} <-
           Perks.create_perk(
             context,
             params
             |> attrs()
             |> CoveringBranches.put_columns(target)
             |> Map.merge(%{created_by_id: context.user_id, updated_by_id: context.user_id})
           ) do
      BoxPhotoCovers.settle(context, nil, perk.logo_media_id)
      track("perk_created", context, perk)
      {:ok, PerkPresenter.staff(context, perk, today(context))}
    end
  end

  @doc "`PATCH …/admin/perks/:id`."
  def update(context, id, params) do
    today = today(context)
    changes = attrs(params)

    with {:ok, perk} <- fetch(context, id),
         :ok <- CoveringBranches.authorize(context, CoveringBranches.of_row(perk)),
         {:ok, changes} <- branch_changes(context, changes, params),
         :ok <- Perks.check_update(perk, changes, today),
         :ok <- known_packages(context, params),
         :ok <- logo_change(context, perk, changes),
         {:ok, updated} <-
           Perks.update_perk(context, perk, Map.put(changes, :updated_by_id, context.user_id)) do
      BoxPhotoCovers.settle(context, perk.logo_media_id, updated.logo_media_id)
      {:ok, PerkPresenter.staff(context, updated, today)}
    end
  end

  defp branch_changes(context, changes, params) do
    case CoveringBranches.requested(params) do
      nil ->
        {:ok, Map.drop(changes, [:all_locations, :location_ids])}

      requested ->
        target = CoveringBranches.target(requested)

        with :ok <- CoveringBranches.authorize(context, target),
             :ok <- known_locations(context, target),
             do: {:ok, CoveringBranches.put_columns(changes, target)}
    end
  end

  defp logo_change(context, perk, changes) do
    case Map.fetch(changes, :logo_media_id) do
      {:ok, id} when id != perk.logo_media_id -> logo_ready(context, id)
      _same -> :ok
    end
  end

  @doc "`DELETE …/admin/perks/:id`: only a perk nobody claimed."
  def delete(context, id) do
    with {:ok, perk} <- fetch(context, id),
         :ok <- CoveringBranches.authorize(context, CoveringBranches.of_row(perk)),
         :ok <- Perks.delete_perk(context, perk) do
      BoxPhotoCovers.settle(context, perk.logo_media_id, nil)
      :ok
    end
  end

  @doc "`POST …/admin/perks/:id/publish`: members see it (refused in demo mode)."
  def publish(context, id) do
    with {:ok, perk} <- fetch(context, id),
         :ok <- CoveringBranches.authorize(context, CoveringBranches.of_row(perk)),
         :ok <- Organizations.go_live(context, :publish_perk),
         :ok <- pool_ready(context, perk) do
      step(context, perk, :publish, "perk_published")
    end
  end

  @doc "`POST …/admin/perks/:id/pause`: no new claims; codes already claimed still work."
  def pause(context, id), do: simple_step(context, id, :pause, "perk_paused")

  @doc "`POST …/admin/perks/:id/expire`: ends the perk now; nothing can be claimed or used."
  def expire(context, id), do: simple_step(context, id, :expire, "perk_expired")

  defp simple_step(context, id, step, event) do
    with {:ok, perk} <- fetch(context, id),
         :ok <- CoveringBranches.authorize(context, CoveringBranches.of_row(perk)),
         do: step(context, perk, step, event)
  end

  defp step(context, perk, step, event) do
    today = today(context)

    with {:ok, updated} <- Perks.transition(context, perk, step, DateTime.utc_now(), today) do
      track(event, context, updated)
      {:ok, PerkPresenter.staff(context, updated, today)}
    end
  end

  defp pool_ready(context, %{redemption_method: "unique_code", id: id}) do
    case Perks.code_stats(context, [id]) do
      %{^id => %{free: free}} when free > 0 -> :ok
      _empty -> {:error, :perk_codes_required}
    end
  end

  defp pool_ready(_context, _perk), do: :ok

  @doc "`POST …/admin/perks/:id/codes`: adds the partner's single-use codes to the pool."
  def add_codes(context, id, codes) do
    with {:ok, perk} <- fetch(context, id),
         :ok <- CoveringBranches.authorize(context, CoveringBranches.of_row(perk)),
         :ok <- unique_code_perk(perk),
         :ok <- not_ended(perk, today(context)),
         {:ok, result} <- Perks.add_codes(context, perk.id, codes) do
      stats = Map.get(Perks.code_stats(context, [perk.id]), perk.id, %{total: 0, free: 0})
      {:ok, Map.merge(result, %{total: stats.total, free: stats.free})}
    end
  end

  defp unique_code_perk(%{redemption_method: "unique_code"}), do: :ok
  defp unique_code_perk(_perk), do: {:error, :perk_codes_not_used}

  defp not_ended(perk, today) do
    if Perks.effective_status(perk, today) == "expired",
      do: {:error, :perk_read_only},
      else: :ok
  end

  @doc """
  `GET …/admin/perks/:id/claims`: the claims export, oldest first, a page
  at a time (`after` is the cursor the previous page returned).
  """
  def claims(context, id, params \\ %{}) do
    limit = Map.get(params, :limit) || 500

    with {:ok, perk} <- fetch(context, id),
         {:ok, cursor} <- decode_cursor(Map.get(params, :after)) do
      rows = Perks.list_claims(context, perk.id, %{limit: limit, after: cursor})

      {:ok,
       %{
         perk: PerkPresenter.staff(context, perk, today(context)),
         claims: Enum.map(rows, &PerkPresenter.export_row/1),
         next: if(length(rows) == limit, do: encode_cursor(List.last(rows)))
       }}
    end
  end

  @doc "The whole export as CSV rows (header first), for `…/claims.csv`."
  def claims_csv(context, id) do
    with {:ok, perk} <- fetch(context, id) do
      rows = all_claims(context, perk.id, nil, [])
      {:ok, %{perk: perk, csv: PerkPresenter.csv(rows)}}
    end
  end

  # Pages of 1 000 up to 50 000 claims: an export never holds the table.
  defp all_claims(_context, _perk_id, _cursor, acc) when length(acc) >= 50_000, do: acc

  defp all_claims(context, perk_id, cursor, acc) do
    case Perks.list_claims(context, perk_id, %{limit: 1_000, after: cursor}) do
      [] ->
        acc

      rows when length(rows) < 1_000 ->
        acc ++ rows

      rows ->
        last = List.last(rows)
        all_claims(context, perk_id, {last.claimed_at, last.id}, acc ++ rows)
    end
  end

  defp decode_cursor(nil), do: {:ok, nil}

  defp decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         [at, id] <- String.split(raw, "|", parts: 2),
         {:ok, at, _offset} <- DateTime.from_iso8601(at),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {:ok, {at, id}}
    else
      _bad -> {:error, :invalid_cursor}
    end
  end

  defp encode_cursor(%{claimed_at: at, id: id}),
    do: Base.url_encode64(DateTime.to_iso8601(at) <> "|" <> id, padding: false)

  @doc "`POST …/admin/perk-claims/:id/use`: staff mark a claim used (the partner confirmed it)."
  def mark_used(context, claim_id) do
    today = today(context)
    now = DateTime.utc_now()

    with {:ok, _perk} <- claim_perk(context, claim_id),
         {:ok, %{perk: perk, claim: claim}} <-
           Perks.use_claim(context, claim_id, "staff", context.user_id, now, fn perk, claim ->
             usable(perk, claim, today)
           end) do
      track_claim("perk_redeemed", context, perk, claim, %{via: "staff"})
      {:ok, PerkPresenter.staff_claim(claim)}
    end
  end

  @doc "`POST …/admin/perk-claims/:id/revoke`: an unused claim stops working and frees its place."
  def revoke_claim(context, claim_id) do
    with {:ok, _perk} <- claim_perk(context, claim_id),
         {:ok, %{perk: perk, claim: claim}} <-
           Perks.revoke_claim(context, claim_id, context.user_id, DateTime.utc_now()) do
      track_claim("perk_claim_revoked", context, perk, claim, %{})
      {:ok, PerkPresenter.staff_claim(claim)}
    end
  end

  defp claim_perk(context, claim_id) do
    with %{} = claim <- Perks.get_claim(context, claim_id) || {:error, :not_found},
         {:ok, perk} <- fetch(context, claim.perk_id),
         :ok <- CoveringBranches.authorize(context, CoveringBranches.of_row(perk)),
         do: {:ok, perk}
  end

  @doc false
  def usable(perk, claim, today) do
    cond do
      claim.status == "used" -> {:error, :perk_claim_already_used}
      claim.status == "revoked" -> {:error, :perk_claim_not_open}
      Perks.usable?(perk, claim, today) -> :ok
      true -> {:error, :perk_not_available}
    end
  end

  # A perk the acting staff can't see is not found for them.
  defp fetch(context, id) do
    with %{} = perk <- Perks.get_perk(context, id) || {:error, :not_found},
         [^perk] <- visible([perk], context) do
      {:ok, perk}
    else
      [] -> {:error, :not_found}
      error -> error
    end
  end

  defp visible(perks, context), do: CoveringBranches.visible(context, perks, &CoveringBranches.of_row/1)

  defp known_locations(_context, :all), do: :ok

  defp known_locations(context, ids) do
    known = context |> Facility.list_locations() |> MapSet.new(& &1.id)
    if Enum.all?(ids, &MapSet.member?(known, &1)), do: :ok, else: {:error, :location_not_found}
  end

  defp known_packages(context, params) do
    case Map.get(params, :package_ids) do
      ids when is_list(ids) and ids != [] ->
        known = context |> Finance.list_packages() |> MapSet.new(& &1.id)

        if Enum.all?(ids, &MapSet.member?(known, &1)),
          do: :ok,
          else: {:error, :invalid_perk_packages}

      _none ->
        :ok
    end
  end

  defp logo_ready(_context, nil), do: :ok
  defp logo_ready(context, id), do: BoxPhotoCovers.ready(context, id)

  defp attrs(params), do: Map.take(params, Perks.editable_fields())

  @doc false
  def track(event, context, perk) do
    TrackAnalyticsEvent.call(event, context, perk, %{
      metadata: %{
        redemption_method: perk.redemption_method,
        benefit_type: perk.benefit_type,
        audience: perk.audience,
        status: perk.status
      }
    })
  end

  @doc false
  def track_claim(event, actor, perk, claim, metadata) do
    TrackAnalyticsEvent.call(event, actor, claim, %{
      organization_id: perk.organization_id,
      user_id: claim.user_id,
      metadata:
        Map.merge(metadata, %{
          perk_id: perk.id,
          redemption_method: perk.redemption_method,
          claims_count: perk.claims_count,
          uses_count: perk.uses_count
        })
    })
  end

  @doc "The business's date in its own time zone."
  def today(%{organization_id: organization_id}) do
    organization_id
    |> Organizations.organization_timezone()
    |> DateTime.now!()
    |> DateTime.to_date()
  end
end
