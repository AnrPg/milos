defmodule Palee.Journal.Domain.Visibility do
  @moduledoc """
  The journal visibility ladder (ADR-139, vision §7.7 / §8.2).

  Rungs, lowest first: `private` (Μόνο εγώ), `coach_can_view` (Ο coach μου
  μπορεί να το δει), `coach_reply_requested` (Ζητάω απάντηση), `rated`
  (Αξιολόγηση), `posted` (Ανάρτηση). A rung reaches the coach from
  `coach_can_view` up; the SQL twin is `palee_journal_visibility_reaches_coach`.
  """

  @rungs ~w(private coach_can_view coach_reply_requested rated posted)
  @kinds ~w(execution training_log pr injury review note check_in body wellness craving
            device_activity)
  # What each kind may hold, and which of those the member picks by hand
  # (`posted` comes from attaching the entry to a post, ADR-138).
  @allowed %{
    "execution" => ~w(private coach_can_view coach_reply_requested posted),
    "training_log" => ~w(private coach_can_view coach_reply_requested posted),
    "pr" => ~w(private coach_can_view coach_reply_requested posted),
    "injury" => ~w(coach_can_view coach_reply_requested posted),
    "review" => ~w(rated),
    "note" => ~w(private coach_can_view coach_reply_requested posted),
    "check_in" => ~w(private coach_can_view coach_reply_requested posted),
    # ADR-158: a body snapshot keeps its own visibility (private,
    # coach_numbers, coach_full), set on the snapshot; the feed shows it as
    # `private` or `coach_can_view` and never moves it from here.
    "body" => ~w(private coach_can_view),
    # ADR-159 (board 14, Q8): a «wellness» feed item is a day, which never
    # moves itself; its entries move one by one (`wellness_entry`, not a feed
    # kind). Wellness is never posted from the ladder: a meal photo becomes a
    # post only through its own confirmation.
    "wellness" => ~w(private coach_can_view),
    "wellness_entry" => ~w(private coach_can_view coach_reply_requested),
    "craving" => ~w(private coach_can_view coach_reply_requested),
    # ADR-161 (board 16, Q3): a watch workout starts private whatever the
    # member's default and is never posted from here; one tied to a booked
    # class may be shown to that gym's coach.
    "device_activity" => ~w(private coach_can_view)
  }
  @self_managed ~w(body wellness)
  @manual ~w(private coach_can_view coach_reply_requested)

  # Kinds whose default a member chooses, and the default without a choice:
  # training stays visible to the gym's coaches as before; notes and
  # check-ins are private (vision §4.5).
  @default_kinds %{
    "workout" => "coach_can_view",
    "pr" => "coach_can_view",
    "note" => "private",
    "check_in" => "private"
  }
  @default_rungs ~w(private coach_can_view)

  def rungs, do: @rungs
  def kinds, do: @kinds
  def default_kinds, do: Map.keys(@default_kinds)
  def default_rungs, do: @default_rungs

  @doc "Rungs the member may move an entry of `kind` to by hand."
  def choosable(kind) when kind in @self_managed, do: []

  def choosable(kind) when is_map_key(@allowed, kind),
    do: Enum.filter(@manual, &(&1 in Map.fetch!(@allowed, kind)))

  def choosable(_kind), do: []

  def allowed?(kind, rung), do: rung in Map.get(@allowed, kind, [])

  def reaches_coach?(rung), do: rung in ~w(coach_can_view coach_reply_requested rated posted)

  @doc "Kind whose member default applies to entries of `kind`."
  def default_kind("execution"), do: "workout"
  def default_kind("training_log"), do: "workout"
  def default_kind(kind) when is_map_key(@default_kinds, kind), do: kind
  def default_kind(_kind), do: nil

  @doc """
  The rung a new entry of `kind` starts on, given the member's stored
  defaults (`%{default_kind => rung}`) and whether it was recorded in a gym.
  An entry without a gym has no coach, so it is private.
  """
  def initial(kind, defaults, in_gym?)

  def initial("injury", _defaults, _in_gym?), do: "coach_can_view"
  def initial("review", _defaults, _in_gym?), do: "rated"
  def initial(_kind, _defaults, false), do: "private"

  def initial(kind, defaults, true) do
    default_kind = default_kind(kind)
    Map.get(defaults, default_kind) || Map.fetch!(@default_kinds, default_kind)
  end

  @doc "Every default kind with the member's choice or the built-in default."
  def effective_defaults(stored) when is_map(stored),
    do: Map.new(@default_kinds, fn {kind, rung} -> {kind, Map.get(stored, kind, rung)} end)

  @doc """
  Validates a manual move. `reach` says who a coach rung would reach
  (`CoachAudience.reach/3`): `:gym` (the entry's provider), `:audience`
  (ADR-162: a provider-less entry shared with the member's coaches) or
  `:none`; a boolean stands for `:gym` / `:none`. A reply request needs a
  gym, because the question goes to a coach of that gym.
  """
  def validate_move(kind, rung, reach) when is_boolean(reach),
    do: validate_move(kind, rung, if(reach, do: :gym, else: :none))

  def validate_move(kind, rung, reach) do
    cond do
      not is_map_key(@allowed, kind) -> {:error, :unknown_kind}
      rung not in choosable(kind) -> {:error, :visibility_not_allowed}
      rung == "private" or reach == :gym -> :ok
      reach == :audience and rung == "coach_can_view" -> :ok
      true -> {:error, :no_gym_for_entry}
    end
  end

  @doc "Default-kind changes may also move existing entries between these rungs only."
  def bulk_movable?(rung), do: rung in @default_rungs

  def validate_default(kind, rung) do
    cond do
      not is_map_key(@default_kinds, kind) -> {:error, :unknown_kind}
      rung not in @default_rungs -> {:error, :visibility_not_allowed}
      true -> :ok
    end
  end
end
