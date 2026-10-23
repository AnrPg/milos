defmodule Palee.Application.Perks do
  @moduledoc """
  Staff run the business's partner perks (ADR-191): the list with claim and
  use counts, create and edit (the open policy: method, benefit, rules,
  terms), publish, pause and end, the versions, the pool of codes the
  partner gave (pasted or CSV, topped up later, low-pool alert), the claims
  export, and marking a claim used or revoking it.

  Rules on top of `Perks` (pure in `Domain.PerkRules` and the method
  strategies):

    * Capability `manage_perks` (route level); branches follow ADR-186 §8:
      a perk is a covering item, visible to branch staff when it is valid
      everywhere or at one of their branches, and created or changed only
      inside their branches.
    * A business in demo mode (ADR-184) drafts perks but can't publish
      them (`business_not_activated`).
    * A method may refuse to go live (a code pool with no free code).
    * Eligibility names this business's packages and club groups only.
    * The partner logo is one of the business's ready `box_photo` uploads,
      released when replaced.
    * Every action on a perk or a claim is recorded as an analytics event
      (the audit trail) with a `[:palee, :perk, ...]` telemetry event.
  """

  alias Palee.Application.{BoxPhotoCovers, CoveringBranches, PerkPresenter, TrackAnalyticsEvent}
  alias Palee.{Facility, Finance, Organizations, Perks}
  alias Palee.Perks.Rules

  @version_keys [:benefit, :rules, :redemption, :terms]

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

  defp stored_statuses("expired"), do: ["published", "expired"]
  defp stored_statuses(status), do: [status]

  defp status_matches?(_perk, nil, _today), do: true
  defp status_matches?(perk, status, today), do: Perks.effective_status(perk, today) == status

  @doc "`GET …/admin/perks/:id`."
  def show(context, id) do
    with {:ok, perk} <- fetch(context, id),
         do: {:ok, PerkPresenter.staff(context, perk, today(context))}
  end

  @doc "`GET …/admin/perks/:id/versions`: every version, newest first."
  def versions(context, id) do
    with {:ok, perk} <- fetch(context, id) do
      {:ok, %{versions: context |> Perks.list_versions(perk.id) |> Enum.map(&PerkPresenter.version/1)}}
    end
  end

  @doc "`POST …/admin/perks`: a new draft (version 1)."
  def create(context, params) do
    attrs = params |> attrs() |> Map.put_new(:redemption_method, Perks.default_method())
    version = version_attrs(params, true)

    with {:ok, target} <- CoveringBranches.for_new(context, CoveringBranches.requested(params)),
         :ok <- known_locations(context, target),
         :ok <- known_eligibility(context, version),
         :ok <- logo_ready(context, Map.get(params, :logo_media_id)),
         {:ok, perk} <-
           Perks.create_perk(
             context,
             attrs
             |> CoveringBranches.put_columns(target)
             |> Map.merge(%{created_by_id: context.user_id, updated_by_id: context.user_id}),
             Map.put(version, :created_by_id, context.user_id)
           ) do
      BoxPhotoCovers.settle(context, nil, perk.logo_media_id)
      track("perk_created", context, perk)
      {:ok, PerkPresenter.staff(context, perk, today(context))}
    end
  end

  @doc """
  `PATCH …/admin/perks/:id`. Perk fields change in place; benefit, rules,
  method settings and terms amend the current version until the first
  claim, and make a new version after it.
  """
  def update(context, id, params) do
    today = today(context)
    changes = attrs(params)
    version = version_attrs(params, false)

    with {:ok, perk} <- fetch(context, id),
         :ok <- CoveringBranches.authorize(context, CoveringBranches.of_row(perk)),
         {:ok, changes} <- branch_changes(context, changes, params),
         {:ok, new_rules} <- preview_rules(perk, version),
         :ok <- Perks.check_update(perk, changes, new_rules, today),
         :ok <- known_eligibility(context, version),
         :ok <- logo_change(context, perk, changes),
         {:ok, updated} <-
           Perks.revise_perk(
             context,
             perk,
             Map.put(changes, :updated_by_id, context.user_id),
             version && Map.put(version, :created_by_id, context.user_id)
           ) do
      BoxPhotoCovers.settle(context, perk.logo_media_id, updated.logo_media_id)

      if updated.current_version != perk.current_version,
        do: track("perk_versioned", context, updated)

      {:ok, PerkPresenter.staff(context, updated, today)}
    end
  end

  # The rules a change would leave, to check the cap before writing.
  defp preview_rules(_perk, nil), do: {:ok, nil}

  defp preview_rules(perk, %{rules: rules}) do
    case Rules.changeset(perk.version.rules, rules) do
      %{valid?: true} = changeset -> {:ok, Ecto.Changeset.apply_changes(changeset)}
      changeset -> {:error, changeset}
    end
  end

  defp preview_rules(_perk, _version), do: {:ok, nil}

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
         :ok <- Perks.method_ready(perk.redemption_method, %{free_codes: free_codes(context, perk)}) do
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

  defp free_codes(context, perk) do
    context |> Perks.code_stats([perk.id]) |> Map.get(perk.id, %{free: 0}) |> Map.fetch!(:free)
  end

  @doc """
  `POST …/admin/perks/:id/codes`: adds the partner's codes to the pool
  (`codes`, or `csv` read by its first column); any time, to top it up.
  """
  def add_codes(context, id, params) do
    input =
      case params do
        %{csv: csv} when is_binary(csv) -> {:csv, csv}
        %{codes: codes} when is_list(codes) -> codes
        _neither -> []
      end

    with {:ok, perk} <- fetch(context, id),
         :ok <- CoveringBranches.authorize(context, CoveringBranches.of_row(perk)),
         :ok <- pool_perk(perk),
         :ok <- not_ended(perk, today(context)),
         {:ok, result} <- Perks.add_codes(context, perk.id, input) do
      stats = Map.get(Perks.code_stats(context, [perk.id]), perk.id, %{total: 0, free: 0})
      track("perk_codes_added", context, perk)

      {:ok,
       Map.merge(result, %{
         total: stats.total,
         free: stats.free,
         low: Perks.pool_low?(Map.from_struct(perk.version.redemption), stats.free)
       })}
    end
  end

  defp pool_perk(%{redemption_method: "code_pool"}), do: :ok
  defp pool_perk(_perk), do: {:error, :perk_codes_not_used}

  defp not_ended(perk, today) do
    if Perks.effective_status(perk, today) == "expired", do: {:error, :perk_read_only}, else: :ok
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

  @doc "The whole export as CSV, for `…/claims.csv`."
  def claims_csv(context, id) do
    with {:ok, perk} <- fetch(context, id) do
      rows = all_claims(context, perk.id, nil, [])
      track("perk_claims_exported", context, perk)
      {:ok, %{perk: perk, csv: PerkPresenter.csv(rows)}}
    end
  end

  # Pages of 1 000 up to 50 000 claims: an export never holds the table.
  defp all_claims(_context, _perk_id, _cursor, acc) when length(acc) >= 50_000, do: acc

  defp all_claims(context, perk_id, cursor, acc) do
    case Perks.list_claims(context, perk_id, %{limit: 1_000, after: cursor}) do
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
    now = DateTime.utc_now()

    with {:ok, _perk} <- claim_perk(context, claim_id),
         {:ok, %{perk: perk, claim: claim}} <-
           Perks.use_claim(context, claim_id, "staff", context.user_id, now, fn perk, claim ->
             usable(context, perk, claim)
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

  @doc """
  Whether a claim can be used now, under the rules of the version it was
  claimed under (the business's local date and time).
  """
  def usable(context, perk, claim) do
    rules = claim_rules(context, perk, claim)
    Perks.usable(perk, rules, claim, today(context), local_now(context))
  end

  @doc "The rules of the version a claim agreed to."
  def claim_rules(context, perk, claim) do
    if claim.perk_version == perk.current_version do
      perk.version.rules
    else
      context
      |> Perks.get_versions([{perk.id, claim.perk_version}])
      |> Map.get({perk.id, claim.perk_version}, perk.version)
      |> Map.fetch!(:rules)
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

  defp known_eligibility(context, %{rules: %{eligibility: eligibility}}) when is_map(eligibility) do
    with :ok <- known(Map.get(eligibility, :package_ids), fn -> package_ids(context) end, :invalid_perk_packages),
         do: known(Map.get(eligibility, :group_ids), fn -> group_ids(context) end, :invalid_perk_groups)
  end

  defp known_eligibility(_context, _version), do: :ok

  defp known(ids, _known, _error) when ids in [nil, []], do: :ok

  defp known(ids, known, error) when is_list(ids) do
    set = MapSet.new(known.())
    if Enum.all?(ids, &MapSet.member?(set, &1)), do: :ok, else: {:error, error}
  end

  defp known(_ids, _known, error), do: {:error, error}

  defp package_ids(context), do: context |> Finance.list_packages() |> Enum.map(& &1.id)
  defp group_ids(context), do: Perks.group_ids(context)

  defp logo_ready(_context, nil), do: :ok
  defp logo_ready(context, id), do: BoxPhotoCovers.ready(context, id)

  defp attrs(params), do: Map.take(params, Perks.editable_fields())

  # Version documents of a request; a create always has all of them.
  defp version_attrs(params, create?) do
    taken = Map.take(params, @version_keys)

    cond do
      create? -> Map.merge(%{rules: %{}, redemption: %{}}, taken)
      taken == %{} -> nil
      true -> taken
    end
  end

  @doc false
  def track(event, context, perk) do
    TrackAnalyticsEvent.call(event, context, perk, %{
      metadata: %{
        redemption_method: perk.redemption_method,
        benefit_type: perk.version && perk.version.benefit.type,
        version: perk.current_version,
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
          perk_version: claim.perk_version,
          redemption_method: perk.redemption_method,
          claims_count: perk.claims_count,
          uses_count: perk.uses_count
        })
    })
  end

  @doc "The business's date in its own time zone."
  def today(context), do: context |> local_now() |> NaiveDateTime.to_date()

  @doc "The business's local wall-clock time."
  def local_now(%{organization_id: organization_id}) do
    organization_id
    |> Organizations.organization_timezone()
    |> DateTime.now!()
    |> DateTime.to_naive()
  end

  @doc "A local wall-clock time of the business as UTC (DST gaps move forward)."
  def to_utc(%{organization_id: organization_id}, %NaiveDateTime{} = local) do
    zone = Organizations.organization_timezone(organization_id)

    case DateTime.from_naive(local, zone) do
      {:ok, at} -> at
      {:ambiguous, first, _second} -> first
      {:gap, _before, after_gap} -> after_gap
    end
    |> DateTime.shift_zone!("Etc/UTC")
  end
end
