defmodule MilosTraining.Referrals.Domain.Attribution do
  @moduledoc """
  The rules of an invite (ADR-156, board 11), free of storage:

    * **Claiming** (Q4): the first member whose link a friend used owns the
      invite for the programme's window; nobody can invite themselves, and
      members or former members of the box are never counted. The same
      member using their own link again changes nothing.
    * **Funnel**: `event → trial → joined → paid`, each stamped once while
      the invite is alive. A step after the window ends the invite
      (`expired`) instead of moving it.
    * **Qualifying**: the programme says whether the trial or the first
      payment counts; a qualified invite opens the Finance referral, unless
      the member's yearly cap is reached (`capped`).
  """

  @channels ~w(link qr event guest_pass staff)
  @statuses ~w(open qualified capped expired void)
  @steps [:event, :trial, :joined, :paid]
  @step_fields %{event: :event_at, trial: :trial_at, joined: :joined_at, paid: :paid_at}
  @default_window_days 60

  def channels, do: @channels
  def statuses, do: @statuses
  def steps, do: @steps
  def default_window_days, do: @default_window_days

  @typedoc "What a claim knows about the people and the box."
  @type claim_facts :: %{
          referrer_id: binary(),
          referred_id: binary(),
          referred_standing: :member | :former | :none,
          existing: map() | nil,
          now: DateTime.t()
        }

  @doc """
  Whether a claim may record a new invite:

    * `:ok` - record it (or replace an invite that ran out);
    * `{:existing, attribution}` - the same member's invite stands, unchanged;
    * `{:error, reason}` - `:self_referral`, `:already_member` or
      `:already_invited` (someone else's invite stands).
  """
  @spec claim(claim_facts()) :: :ok | {:existing, map()} | {:error, atom()}
  def claim(%{referrer_id: same, referred_id: same}), do: {:error, :self_referral}

  def claim(%{referred_standing: standing}) when standing in [:member, :former],
    do: {:error, :already_member}

  def claim(%{existing: nil}), do: :ok

  def claim(%{existing: existing, referrer_id: referrer_id, now: now}) do
    cond do
      replaceable?(existing, now) -> :ok
      existing.referrer_user_id == referrer_id -> {:existing, existing}
      true -> {:error, :already_invited}
    end
  end

  # An invite that ran out without counting leaves room for a new one.
  defp replaceable?(%{status: status}, _now) when status in ["expired", "void"], do: true

  defp replaceable?(%{status: "open", expires_at: expires_at}, now),
    do: DateTime.compare(now, expires_at) == :gt

  defp replaceable?(_existing, _now), do: false

  @doc "When an invite made at `now` stops holding, for a programme's window in days."
  def expires_at(now, days) when is_integer(days) and days > 0,
    do: DateTime.add(now, days, :day)

  def expires_at(now, _days), do: DateTime.add(now, @default_window_days, :day)

  @doc """
  Moves the invite one funnel step:

    * `{:ok, changes}` - stamp the step;
    * `{:expire, changes}` - the window had ended, the invite expires;
    * `:noop` - already stamped, or the invite is no longer alive.

  A qualified invite keeps stamping later steps (the member still sees the
  friend's progress); an expired, capped or void one does not move.
  """
  def advance(attribution, step, at) when step in @steps do
    field = Map.fetch!(@step_fields, step)

    cond do
      Map.get(attribution, field) != nil -> :noop
      attribution.status in ["expired", "void", "capped"] -> :noop
      attribution.status == "qualified" -> {:ok, %{field => at}}
      DateTime.compare(at, attribution.expires_at) == :gt -> {:expire, %{status: "expired"}}
      true -> {:ok, %{field => at}}
    end
  end

  @doc "The furthest step the friend reached, for the member's list."
  def stage(attribution) do
    cond do
      attribution.paid_at -> "paid"
      attribution.joined_at -> "joined"
      attribution.trial_at -> "trial"
      attribution.event_at -> "event"
      true -> "signed_up"
    end
  end

  @doc """
  Whether an open invite has reached the step its programme rewards
  (`qualifying_stage`: `"trial"` or `"paid"`). No programme, nothing to
  reward yet.
  """
  def qualifies?(%{status: "open"} = attribution, %{qualifying_stage: "trial"}),
    do: attribution.trial_at != nil or attribution.paid_at != nil

  def qualifies?(%{status: "open"} = attribution, %{qualifying_stage: "paid"}),
    do: attribution.paid_at != nil

  def qualifies?(_attribution, _program), do: false

  @doc "Whether a member already has as many rewarded friends this year as the cap allows."
  def cap_reached?(_count, nil), do: false
  def cap_reached?(count, cap) when is_integer(cap), do: count >= cap

  @doc "What a staff reassignment changes; the new member can't be the friend."
  def reassign(%{referred_user_id: same}, same, _actor, _note, _at),
    do: {:error, :self_referral}

  def reassign(%{status: "qualified"}, _new, _actor, _note, _at),
    do: {:error, :referral_already_qualified}

  def reassign(attribution, new_referrer_id, actor_id, note, at) do
    {:ok,
     %{
       previous_referrer_user_id: attribution.referrer_user_id,
       referrer_user_id: new_referrer_id,
       reassigned_at: at,
       reassigned_by_id: actor_id,
       code_id: nil,
       notes: note
     }}
  end
end
