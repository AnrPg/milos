defmodule MilosTraining.Application.Referrals do
  @moduledoc """
  ADR-156 (P2-M8, board 11): members bring friends.

  * **Member** (`Εγώ › Φέρε φίλο`): `overview/2` - the personal link, the
    box's programme, the events a friend can come to, and the member's
    invites with each friend's stage and reward.
  * **Friend**: `invite/1` (what the invite page shows) and `claim/3`, which
    records the invite when the friend signs up or opens the link signed in.
  * **Funnel**: `step/4`, fed by `ReferralReactions` (event attendance, trial
    attendance, joining, the first package payment). When an invite reaches
    the step its programme rewards it `qualify`s: Finance gets a pending
    referral under the programme the invite was made with, approved by the
    admin (or at once when the programme says so).
  * **Staff** (Finance › Συστάσεις): `staff_list/2`, `approve/3`,
    `reject/4`, `mark_given/3`, `reassign/4`, `apply_friend_gift/3`.

  Who sees what (board 11 Q5): the member sees each friend's display name,
  stage and reward state, never packages, payments or bookings.
  """

  require Logger

  alias MilosTraining.Application.{CommunityPeople, PublicBox}
  alias MilosTraining.{Community, Finance, Identity, Notifications, Organizations}
  alias MilosTraining.{Referrals, Trials}
  alias MilosTraining.Referrals.ReferralAttribution

  @staff_roles [:owner, :admin, :coach]
  @earning_roles [:member, :athlete]
  @reviewer_roles [:owner, :admin]
  @cap_period_days 365
  @events_limit 8
  @invites_limit 100
  @code_attempts 5

  # ---------------------------------------------------------------- member

  @doc """
  The member's «Φέρε φίλο» at the box in `context` (their tenant context):
  their code (made on first use), the active programme, events a friend can
  come to and their invites.
  """
  def overview(%{organization_id: organization_id, user_id: user_id} = context, now \\ now()) do
    with {:ok, code} <- ensure_code(context) do
      program = Finance.active_referral_program(box(organization_id))

      invites =
        Referrals.list_attributions(context, %{referrer_user_id: user_id, limit: @invites_limit})

      programs = programs_of(organization_id, invites, program)

      {:ok,
       %{
         code: code.code,
         path: invite_path(code.code),
         earns_rewards: earns_rewards?(organization_id, user_id),
         program: program && present_program(program),
         events: invitable_events(context, now),
         invites: present_invites(organization_id, invites, programs, :member),
         totals: totals(invites)
       }}
    end
  end

  @doc "A new code for the member at the box; the old link stops working."
  def rotate_code(%{organization_id: _organization_id, user_id: user_id} = context) do
    case Referrals.get_active_code(context, user_id) do
      nil -> :ok
      code -> Referrals.revoke_code(context, code, now())
    end

    with {:ok, code} <- ensure_code(context),
         do: {:ok, %{code: code.code, path: invite_path(code.code)}}
  end

  defp ensure_code(%{user_id: user_id} = context) do
    case Referrals.get_active_code(context, user_id) do
      nil -> insert_code(context, @code_attempts)
      code -> {:ok, code}
    end
  end

  defp insert_code(_context, 0), do: {:error, :referral_code_unavailable}

  defp insert_code(%{organization_id: organization_id, user_id: user_id} = context, attempts) do
    case Referrals.insert_code(context, %{
           organization_id: organization_id,
           user_id: user_id,
           code: Referrals.generate_code()
         }) do
      {:ok, code} ->
        {:ok, code}

      {:error, %Ecto.Changeset{errors: errors}} ->
        if Keyword.has_key?(errors, :organization_id) do
          # Another request made the member's code first.
          {:ok, Referrals.get_active_code(context, user_id)}
        else
          insert_code(context, attempts - 1)
        end
    end
  end

  # Board 11 Q3: open events anyone signed in can come to, and events with
  # guest passes the member is going to (their guests count as invites too).
  defp invitable_events(%{organization_id: organization_id, user_id: user_id}, now) do
    gym = %{organization_id: organization_id, user_id: user_id}

    open =
      Community.list_events(gym, %{
        organization_ids: [organization_id],
        open_only: true,
        from: now,
        limit: @events_limit
      })

    going_ids =
      %{user_id: user_id}
      |> Community.attendances_of(user_id, ["going"])
      |> Enum.filter(&(&1.organization_id == organization_id))
      |> Enum.map(& &1.event_id)

    with_guests =
      case going_ids do
        [] ->
          []

        ids ->
          gym
          |> Community.list_events(%{organization_ids: [organization_id], ids: ids, from: now})
          |> Enum.filter(& &1.guest_pass_allowed)
      end

    (open ++ with_guests)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&{&1.starts_at, &1.id}, fn {a, ida}, {b, idb} ->
      case DateTime.compare(a, b) do
        :lt -> true
        :gt -> false
        :eq -> ida <= idb
      end
    end)
    |> Enum.take(@events_limit)
    |> Enum.map(fn event ->
      %{
        id: event.id,
        title: event.title,
        starts_at: event.starts_at,
        ends_at: event.ends_at,
        price_cents: event.price_cents,
        currency: event.currency,
        place_name: event.place_name,
        access: if(event.open_to_non_members, do: "open", else: "guest_pass")
      }
    end)
  end

  # ---------------------------------------------------------------- friend

  @doc """
  What the invite page shows for a code (no sign-in needed): the box, who
  invites, the friend's gift and whether the box takes trials.
  """
  def invite(code_input) do
    with %{} = resolved <- Referrals.resolve_code(code_input) || {:error, :not_found} do
      box_context = box(resolved.organization_id)
      program = Finance.active_referral_program(box_context)

      inviter =
        [resolved.user_id] |> CommunityPeople.by_ids() |> CommunityPeople.person(resolved.user_id)

      {:ok,
       %{
         code: code_of(code_input),
         box: present_invite_box(resolved.box, box_context),
         inviter: %{nickname: inviter.nickname, avatar_url: inviter.avatar_url},
         gift: program && present_gift(program),
         window_days: program && program.attribution_days,
         trials_enabled: Trials.policy(box_context).enabled
       }}
    end
  end

  defp code_of(input) do
    case Referrals.normalize_code(input) do
      {:ok, code} -> code
      :error -> input
    end
  end

  defp present_invite_box(box, context) do
    card = if box.published, do: PublicBox.card(context)

    %{
      slug: box.slug,
      name: box.name,
      logo_url: box.logo_url,
      primary_color: box.primary_color,
      published: box.published,
      cover: card && card.cover,
      disciplines: (card && card.disciplines) || [],
      neighbourhood: card && card.neighbourhood
    }
  end

  @doc """
  Records that `user` came through a member's invite. `opts`: `channel`
  (`link` default, `qr`, `event`), `event_id` with an event invite, and
  `new_account` when the account was just made from the invite page.

  Returns `{:ok, %{outcome: outcome, box: %{slug, name}}}` where `outcome`
  is `:claimed`, `:unchanged` (the same member's invite already stands),
  `:already_member`, `:already_invited` or `:self`; an unknown or revoked
  code is `{:error, :not_found}`. Telling the friend no more than that keeps
  other members' invites private.
  """
  def claim(%{id: user_id}, code_input, opts \\ %{}) do
    now = now()

    with %{} = resolved <- Referrals.resolve_code(code_input) || {:error, :not_found} do
      context = %{organization_id: resolved.organization_id, user_id: user_id}

      outcome =
        Referrals.with_friend_lock(context, user_id, fn ->
          existing = Referrals.get_attribution_for(context, user_id)

          facts = %{
            referrer_id: resolved.user_id,
            referred_id: user_id,
            referred_standing:
              Organizations.membership_standing(resolved.organization_id, user_id),
            existing: existing,
            now: now
          }

          case Referrals.claim_check(facts) do
            :ok -> record_claim(context, resolved, existing, opts, now)
            {:existing, _attribution} -> {:ok, :unchanged}
            {:error, reason} -> {:ok, reason}
          end
        end)

      with {:ok, result} <- outcome do
        {:ok, %{outcome: outcome_name(result), box: Map.take(resolved.box, [:slug, :name])}}
      end
    end
  end

  defp outcome_name(%ReferralAttribution{}), do: :claimed
  defp outcome_name(:self_referral), do: :self
  defp outcome_name(other), do: other

  defp record_claim(context, resolved, existing, opts, now) do
    program = Finance.active_referral_program(box(context.organization_id))
    channel = claim_channel(opts)

    attrs = %{
      organization_id: context.organization_id,
      referrer_user_id: resolved.user_id,
      referred_user_id: context.user_id,
      code_id: resolved.code_id,
      community_event_id: (channel == "event" && opts[:event_id]) || nil,
      channel: channel,
      referral_program_id: program && program.id,
      new_account: opts[:new_account] == true,
      attributed_at: now,
      expires_at: Referrals.expires_at(now, program && program.attribution_days)
    }

    result =
      case existing do
        nil -> Referrals.insert_attribution(context, attrs)
        stale -> Referrals.replace_attribution(context, stale, attrs)
      end

    with {:ok, attribution} <- result do
      notify_progress(context.organization_id, attribution, "signed_up")
      {:ok, attribution}
    end
  end

  defp claim_channel(opts) do
    case opts[:channel] do
      channel when channel in ["qr", "event", "guest_pass"] -> channel
      _ -> "link"
    end
  end

  # ---------------------------------------------------------------- funnel

  @doc """
  Moves the friend's invite at the box one funnel step (`:event`, `:trial`,
  `:joined`, `:paid`) and qualifies it when it reached the step its
  programme rewards. Steps replayed or out of order change nothing.
  """
  def step(organization_id, user_id, step, at \\ now()) do
    context = box(organization_id)

    Referrals.with_friend_lock(context, user_id, fn ->
      case Referrals.get_attribution_for(context, user_id) do
        nil -> :ok
        attribution -> advance(context, attribution, step, at)
      end
    end)
  end

  defp advance(context, attribution, step, at) do
    case Referrals.advance(context, attribution, step, at) do
      {:ok, %ReferralAttribution{status: "open"} = moved} ->
        notify_step(context.organization_id, moved, step)
        maybe_qualify(context, moved, at)

      {:ok, _moved_or_expired} ->
        :ok

      :noop ->
        # An invite that waited for the friend's Finance record retries.
        if attribution.status == "open", do: maybe_qualify(context, attribution, at), else: :ok

      {:error, reason} ->
        Logger.warning("referral_step_failed step=#{step} #{inspect(reason)}")
        :ok
    end
  end

  defp notify_step(organization_id, attribution, step) when step in [:event, :trial, :paid],
    do: notify_progress(organization_id, attribution, Atom.to_string(step))

  defp notify_step(_organization_id, _attribution, _step), do: :ok

  defp maybe_qualify(context, attribution, at) do
    program = program_of(context, attribution)

    if program && Referrals.qualifies?(attribution, program),
      do: qualify(context, attribution, program, at),
      else: :ok
  end

  defp program_of(context, %{referral_program_id: nil}),
    do: Finance.active_referral_program(context)

  defp program_of(context, %{referral_program_id: id}),
    do: Finance.get_referral_program(context, id)

  defp qualify(context, attribution, program, at) do
    with {:eligible, true} <-
           {:eligible, earns_rewards?(context.organization_id, attribution.referrer_user_id)},
         {:cap, false} <- {:cap, cap_reached?(context, attribution, program, at)},
         {:membership, %{membership: membership}} <-
           {:membership, Finance.get_member_profile(context, attribution.referred_user_id)},
         {:ok, event} <- open_finance_referral(context, attribution, program, membership),
         {:ok, qualified} <-
           Referrals.update_attribution(context, attribution, %{
             status: "qualified",
             qualified_at: at,
             finance_referral_event_id: event.id
           }) do
      after_qualify(context, qualified, program, event)
    else
      {:eligible, false} ->
        Referrals.update_attribution(context, attribution, %{
          status: "void",
          void_reason: "referrer_not_eligible"
        })

      {:cap, true} ->
        Referrals.update_attribution(context, attribution, %{status: "capped", qualified_at: at})

      # No Finance record yet (a trial-stage programme): the next step retries.
      {:membership, _none} ->
        :ok

      {:error, reason} ->
        Logger.warning("referral_qualify_failed attribution=#{attribution.id} #{inspect(reason)}")
        :ok
    end
  end

  defp cap_reached?(_context, _attribution, %{yearly_cap: nil}, _at), do: false

  defp cap_reached?(context, attribution, program, at) do
    since = DateTime.add(at, -@cap_period_days, :day)

    context
    |> Finance.count_referral_events_since(attribution.referrer_user_id, since)
    |> Referrals.cap_reached?(program.yearly_cap)
  end

  defp open_finance_referral(context, attribution, program, membership) do
    roles =
      [attribution.referrer_user_id, attribution.referred_user_id]
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1.role})

    Finance.open_attributed_referral(context, %{
      referral_program_id: program.id,
      referrer_user_id: attribution.referrer_user_id,
      referred_user_id: attribution.referred_user_id,
      membership_id: membership.id,
      referrer_role_snapshot: to_string(roles[attribution.referrer_user_id]),
      referred_role_snapshot: to_string(roles[attribution.referred_user_id]),
      notes:
        "#{attribution.channel} · #{Date.to_iso8601(DateTime.to_date(attribution.attributed_at))}",
      params: %{"attribution_id" => attribution.id, "channel" => attribution.channel}
    })
  end

  defp after_qualify(context, attribution, %{approval: "auto"} = program, event) do
    case approve_referral(context, event, program) do
      {:ok, reward} -> notify_reward(context.organization_id, attribution, reward)
      {:error, reason} -> Logger.warning("referral_auto_approve_failed #{inspect(reason)}")
    end

    :ok
  end

  defp after_qualify(context, attribution, _program, _event) do
    notify_review(context.organization_id, attribution)
    :ok
  end

  # ---------------------------------------------------------------- staff

  @doc """
  Every invite at the box (Finance › Συστάσεις), newest first; `filter`
  `"review"` keeps those whose referral waits for approval.
  """
  def staff_list(%{organization_id: organization_id} = context, filter \\ nil) do
    invites =
      Referrals.list_attributions(context, %{
        awaiting_review: filter == "review",
        limit: 300
      })

    programs = programs_of(organization_id, invites, nil)
    stats = Referrals.stats(context, DateTime.add(now(), -90, :day))

    %{
      invites: present_invites(organization_id, invites, programs, :staff),
      stats: stats
    }
  end

  @doc "Approves the invite's referral and creates its reward (a credit lands at once)."
  def approve(%{organization_id: organization_id} = context, attribution_id, _actor_id) do
    with {:ok, attribution, event} <- reviewable(context, attribution_id),
         %{} = program <- program_of(context, attribution) || {:error, :not_found},
         {:ok, reward} <-
           Referrals.with_friend_lock(context, attribution.referred_user_id, fn ->
             approve_referral(context, event, program)
           end) do
      notify_reward(organization_id, attribution, reward)
      {:ok, show(context, attribution.id)}
    end
  end

  @doc "Rejects the invite's referral; no reward is made."
  def reject(context, attribution_id, _actor_id, note) do
    with {:ok, attribution, event} <- reviewable(context, attribution_id),
         {:ok, _event} <- Finance.update_referral_status(context, event.id, "rejected"),
         {:ok, _attribution} <- maybe_note(context, attribution, note) do
      {:ok, show(context, attribution.id)}
    end
  end

  @doc "«Δόθηκε»: a non-credit reward was handed over (the referral is applied)."
  def mark_given(%{organization_id: organization_id} = context, attribution_id, _actor_id) do
    with %ReferralAttribution{finance_referral_event_id: event_id} = attribution
         when is_binary(event_id) <-
           Referrals.get_attribution(context, attribution_id) || {:error, :not_found},
         %{reward: %{status: "approved"} = reward} <-
           Finance.referral_outcomes(context, [event_id])[event_id] ||
             {:error, :invalid_referral_status_transition},
         true <-
           (reward.reward_type != "credit" or
              has_finance_record?(context, attribution.referrer_user_id)) ||
             {:error, :recipient_membership_not_found},
         {:ok, given} <-
           Referrals.with_friend_lock(context, attribution.referred_user_id, fn ->
             Finance.update_referral_reward_status(context, reward.id, "applied")
           end) do
      notify_reward(organization_id, attribution, given)
      {:ok, show(context, attribution.id)}
    else
      %{} -> {:error, :invalid_referral_status_transition}
      %ReferralAttribution{} -> {:error, :invalid_referral_status_transition}
      error -> error
    end
  end

  @doc "Gives an invite that hasn't qualified yet to another member, with a note (Q4)."
  def reassign(%{organization_id: organization_id} = context, attribution_id, params, actor_id) do
    new_referrer = params[:referrer_user_id]

    with %ReferralAttribution{} = attribution <-
           Referrals.get_attribution(context, attribution_id) || {:error, :not_found},
         true <-
           Organizations.membership_standing(organization_id, new_referrer) == :member ||
             {:error, :referrer_not_member},
         {:ok, _moved} <-
           Referrals.reassign(context, attribution, new_referrer, actor_id, params[:note], now()) do
      {:ok, show(context, attribution.id)}
    end
  end

  @doc """
  «Εφάρμοσε» the friend's gift on their first sale (Q7): free days extend
  their current package, a credit lands on their account, a described gift
  is only recorded. Once per invite.
  """
  def apply_friend_gift(context, attribution_id, actor_id) do
    with %ReferralAttribution{friend_gift_applied_at: nil} = attribution <-
           Referrals.get_attribution(context, attribution_id) || {:error, :not_found},
         %{} = program <-
           program_of(context, attribution) || {:error, :referral_program_required},
         %{membership: membership} <-
           Finance.get_member_profile(context, attribution.referred_user_id) ||
             {:error, :referral_membership_required},
         :ok <- grant_gift(context, attribution, program, membership, actor_id),
         {:ok, _applied} <-
           Referrals.update_attribution(context, attribution, %{
             friend_gift_applied_at: now(),
             friend_gift_applied_by_id: actor_id
           }) do
      {:ok, show(context, attribution.id)}
    else
      %ReferralAttribution{} -> {:error, :referral_gift_already_applied}
      error -> error
    end
  end

  defp grant_gift(_context, _attribution, %{friend_reward_type: "none"}, _membership, _actor),
    do: {:error, :referral_no_friend_gift}

  defp grant_gift(
         context,
         _attribution,
         %{friend_reward_type: "free_days"} = program,
         membership,
         _actor
       ) do
    with {:ok, _extended} <-
           Finance.extend_current_subscription(
             context,
             membership.id,
             program.friend_reward_value
           ),
         do: :ok
  end

  defp grant_gift(
         context,
         attribution,
         %{friend_reward_type: "credit"} = program,
         membership,
         actor
       ) do
    with {:ok, _entry} <-
           Finance.create_manual_credit(context, membership.id, %{
             amount_cents: program.friend_reward_value,
             description: "Referral gift",
             created_by_id: actor,
             request_id: "referral-gift:#{attribution.id}"
           }),
         do: :ok
  end

  defp grant_gift(_context, _attribution, %{friend_reward_type: "custom"}, _membership, _actor),
    do: :ok

  defp reviewable(context, attribution_id) do
    with %ReferralAttribution{finance_referral_event_id: event_id} = attribution
         when is_binary(event_id) <-
           Referrals.get_attribution(context, attribution_id) || {:error, :not_found},
         %{event: %{status: "pending"} = event} <-
           Finance.referral_outcomes(context, [event_id])[event_id] ||
             {:error, :invalid_referral_status_transition} do
      {:ok, attribution, event}
    else
      %ReferralAttribution{} -> {:error, :invalid_referral_status_transition}
      %{event: _} -> {:error, :invalid_referral_status_transition}
      error -> error
    end
  end

  # Approve the referral, make its reward approved, and hand over a credit at
  # once (it lands in the member's credit ledger); other kinds wait for
  # «Δόθηκε».
  #
  # A credit needs the member's own Finance record to land in; without one it
  # stays approved and «Δόθηκε» hands it over once they have one.
  defp approve_referral(context, event, program) do
    with {:ok, _approved} <- Finance.update_referral_status(context, event.id, "approved"),
         {:ok, reward} <- Finance.create_referral_reward(context, event.id, %{status: "approved"}) do
      if program.reward_type == "credit" and has_finance_record?(context, event.referrer_user_id),
        do: Finance.update_referral_reward_status(context, reward.id, "applied"),
        else: {:ok, reward}
    end
  end

  defp has_finance_record?(context, user_id),
    do: match?(%{membership: %{}}, Finance.get_member_profile(context, user_id))

  defp maybe_note(_context, attribution, note) when note in [nil, ""], do: {:ok, attribution}

  defp maybe_note(context, attribution, note),
    do: Referrals.update_attribution(context, attribution, %{notes: String.slice(note, 0, 500)})

  defp show(%{organization_id: organization_id} = context, attribution_id) do
    attribution = Referrals.get_attribution(context, attribution_id)
    programs = programs_of(organization_id, [attribution], nil)
    [shown] = present_invites(organization_id, [attribution], programs, :staff)
    shown
  end

  # ---------------------------------------------------------------- presenting

  defp programs_of(organization_id, invites, active) do
    context = box(organization_id)

    ids =
      invites
      |> Enum.map(& &1.referral_program_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    known = if active, do: %{active.id => active}, else: %{}

    Enum.reduce(ids, known, fn id, acc ->
      if Map.has_key?(acc, id) do
        acc
      else
        case Finance.get_referral_program(context, id) do
          nil -> acc
          program -> Map.put(acc, id, program)
        end
      end
    end)
  end

  defp present_invites(_organization_id, [], _programs, _audience), do: []

  defp present_invites(organization_id, invites, programs, audience) do
    context = box(organization_id)

    event_ids = invites |> Enum.map(& &1.finance_referral_event_id) |> Enum.reject(&is_nil/1)
    outcomes = Finance.referral_outcomes(context, event_ids)

    people =
      invites
      |> Enum.flat_map(&[&1.referred_user_id, &1.referrer_user_id, &1.previous_referrer_user_id])
      |> CommunityPeople.by_ids()

    Enum.map(invites, fn invite ->
      program = programs[invite.referral_program_id]
      outcome = invite.finance_referral_event_id && outcomes[invite.finance_referral_event_id]

      base = %{
        id: invite.id,
        friend:
          CommunityPeople.person(people, invite.referred_user_id)
          |> Map.take([:id, :nickname, :avatar_url]),
        stage: Referrals.stage(invite),
        stage_at: stage_at(invite),
        status: invite.status,
        channel: invite.channel,
        attributed_at: invite.attributed_at,
        expires_at: invite.expires_at,
        reward: present_reward(invite, program, outcome)
      }

      if audience == :staff do
        Map.merge(base, %{
          referrer:
            invite.referrer_user_id &&
              CommunityPeople.person(people, invite.referrer_user_id)
              |> Map.take([:id, :nickname, :avatar_url]),
          previous_referrer:
            invite.previous_referrer_user_id &&
              CommunityPeople.person(people, invite.previous_referrer_user_id)
              |> Map.take([:id, :nickname, :avatar_url]),
          steps: %{
            event_at: invite.event_at,
            trial_at: invite.trial_at,
            joined_at: invite.joined_at,
            paid_at: invite.paid_at
          },
          new_account: invite.new_account,
          community_event_id: invite.community_event_id,
          void_reason: invite.void_reason,
          notes: invite.notes,
          reassigned_at: invite.reassigned_at,
          referral_event_id: invite.finance_referral_event_id,
          program: program && %{id: program.id, name: program.name},
          friend_gift: program && present_gift(program),
          friend_gift_applied_at: invite.friend_gift_applied_at
        })
      else
        base
      end
    end)
  end

  defp stage_at(invite),
    do:
      invite.paid_at || invite.joined_at || invite.trial_at || invite.event_at ||
        invite.attributed_at

  # The reward as the member and staff read it: what it is and where it stands.
  defp present_reward(_invite, nil, _outcome), do: nil

  defp present_reward(invite, program, outcome) do
    %{
      type: program.reward_type,
      value: program.reward_value,
      note: program.reward_note,
      status: reward_status(invite, outcome),
      applied_at: outcome && outcome.reward && outcome.reward.applied_at
    }
  end

  # `upcoming` (not there yet), `pending` (waiting for the admin), `approved`
  # (to be handed over), `given`, `rejected`, `capped` or `none` (the invite
  # ran out or doesn't earn).
  defp reward_status(%{status: "open"}, _outcome), do: "upcoming"
  defp reward_status(%{status: "capped"}, _outcome), do: "capped"
  defp reward_status(%{status: status}, _outcome) when status in ["expired", "void"], do: "none"
  defp reward_status(_invite, nil), do: "pending"
  defp reward_status(_invite, %{event: %{status: "rejected"}}), do: "rejected"
  defp reward_status(_invite, %{reward: %{status: "applied"}}), do: "given"
  defp reward_status(_invite, %{reward: %{status: "rejected"}}), do: "rejected"
  defp reward_status(_invite, %{reward: %{status: "approved"}}), do: "approved"
  defp reward_status(_invite, %{event: %{status: "approved"}}), do: "approved"
  defp reward_status(_invite, %{event: %{status: "applied"}}), do: "given"
  defp reward_status(_invite, _outcome), do: "pending"

  defp totals(invites) do
    %{
      invited: length(invites),
      trials: Enum.count(invites, &(&1.trial_at || &1.event_at)),
      paid: Enum.count(invites, & &1.paid_at)
    }
  end

  @doc false
  def present_program(program) do
    %{
      id: program.id,
      name: program.name,
      reward: %{type: program.reward_type, value: program.reward_value, note: program.reward_note},
      gift: present_gift(program),
      qualifying_stage: program.qualifying_stage,
      attribution_days: program.attribution_days,
      yearly_cap: program.yearly_cap
    }
  end

  defp present_gift(%{friend_reward_type: "none"}), do: nil

  defp present_gift(program),
    do: %{
      type: program.friend_reward_type,
      value: program.friend_reward_value,
      note: program.friend_reward_note
    }

  # ---------------------------------------------------------------- notices

  defp notify_progress(organization_id, attribution, stage) do
    friend =
      [attribution.referred_user_id]
      |> CommunityPeople.by_ids()
      |> CommunityPeople.person(attribution.referred_user_id)

    if attribution.referrer_user_id do
      Notifications.dispatch_event(:referral_progress, %{
        user_id: attribution.referrer_user_id,
        organization_id: organization_id,
        attribution_id: attribution.id,
        stage: stage,
        person_nickname: friend.nickname,
        box: box_ref(organization_id)
      })
    end

    :ok
  end

  defp notify_reward(organization_id, attribution, reward) do
    if attribution.referrer_user_id do
      Notifications.dispatch_event(:referral_reward, %{
        user_id: attribution.referrer_user_id,
        organization_id: organization_id,
        attribution_id: attribution.id,
        reward_status: if(reward.status == "applied", do: "given", else: reward.status),
        box: box_ref(organization_id)
      })
    end

    :ok
  end

  defp notify_review(organization_id, attribution) do
    people =
      CommunityPeople.by_ids([attribution.referred_user_id, attribution.referrer_user_id])

    organization_id
    |> Organizations.list_staff_user_ids()
    |> Enum.filter(fn staff_id ->
      organization_id
      |> Organizations.member_roles(staff_id)
      |> Enum.any?(&(&1 in @reviewer_roles))
    end)
    |> Enum.each(fn staff_id ->
      Notifications.dispatch_event(:referral_review, %{
        user_id: staff_id,
        organization_id: organization_id,
        attribution_id: attribution.id,
        person_nickname: CommunityPeople.person(people, attribution.referred_user_id).nickname,
        referrer_nickname: CommunityPeople.person(people, attribution.referrer_user_id).nickname,
        box: box_ref(organization_id)
      })
    end)
  end

  # ---------------------------------------------------------------- helpers

  @doc "Whether a member earns rewards at the box: an active member, not staff (Q4)."
  def earns_rewards?(_organization_id, nil), do: false

  def earns_rewards?(organization_id, user_id) do
    roles = Organizations.member_roles(organization_id, user_id)
    Enum.any?(roles, &(&1 in @earning_roles)) and not Enum.any?(roles, &(&1 in @staff_roles))
  end

  @doc "The member app path an invite code opens."
  def invite_path(code), do: "/r/" <> code

  defp box(organization_id), do: %{organization_id: organization_id}

  # The box as notices name it, and its slug so the link opens that box.
  defp box_ref(organization_id) do
    case PublicBox.boxes([organization_id]) do
      [%{name: name, slug: slug}] -> %{box_name: name, box_slug: slug}
      _ -> %{box_name: nil, box_slug: nil}
    end
  end

  defp now, do: DateTime.utc_now()
end
