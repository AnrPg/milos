defmodule Palee.Application.GetMyWellness do
  @moduledoc """
  Ημερολόγιο › Ευεξία (ADR-159 §2): the member's days from `from` to `to`
  (local dates, inclusive, at most a quarter): a summary per day for the
  «Σήμερα» card and the week strip, the plain week line, the entries and
  cravings themselves, and the member's targets. Mood and stress come from
  the latest Πώς νιώθω of each day (Wellbeing); nothing here is compared
  with anyone else.
  """

  alias Palee.Application.{MealPhotos, WellnessConsent, WellnessInput}
  alias Palee.{Nutrition, Wellbeing, Wellness}

  def call(%{user_id: user_id} = context, params) do
    with {:ok, from, to} <-
           Wellness.parse_window(
             WellnessInput.param(params, "from"),
             WellnessInput.param(params, "to")
           ) do
      context
      |> Wellness.with_context(fn ->
        prefs = Wellness.preferences(user_id)
        entries = Wellness.list_entries(user_id, from, to)
        cravings = Wellness.list_cravings(user_id, from, to)
        moods = moods(user_id, from, to)

        days =
          Wellness.summarize_days(
            Wellness.days_between(from, to),
            entries,
            cravings,
            moods,
            prefs
          )

        {:ok,
         %{
           from: from,
           to: to,
           preferences: prefs,
           days: days,
           week: Wellness.week_line(days),
           entries: entries,
           cravings: cravings
         }}
      end)
      |> with_photos(context)
      |> with_consent(context)
      |> with_plans(context)
    end
  end

  defp with_photos({:ok, payload}, context) do
    ids = payload.entries |> Enum.map(&Wellness.meal_media_id(&1.value)) |> Enum.reject(&is_nil/1)

    {:ok,
     Map.merge(payload, %{
       photos: MealPhotos.present(context, ids),
       photo_capabilities: MealPhotos.capabilities()
     })}
  end

  # The coaches' plans, as the member may see them (board 14, Q5): daily
  # portions and meal slots, never calories. Hidden with the «plan» item.
  defp with_plans({:ok, payload}, context) do
    plans =
      if "plan" in (payload.preferences.hidden_items || []),
        do: [],
        else: context |> Nutrition.list_own_plans() |> Enum.map(&plan/1)

    {:ok, Map.put(payload, :plans, plans)}
  end

  defp plan(plan) do
    %{
      id: plan.id,
      organization_id: plan.organization_id,
      title: plan.title,
      portions: Nutrition.effective_portions(plan),
      meal_slots:
        if(plan.meal_slots == [], do: Nutrition.default_meal_slots(), else: plan.meal_slots),
      updated_at: plan.updated_at
    }
  end

  defp with_consent({:ok, payload}, %{user_id: user_id} = context),
    do: {:ok, Map.put(payload, :consented, WellnessConsent.active?(context, user_id))}

  # Check-ins are kept by instant; the day is where the member was. The UTC
  # window is padded by the widest zone offsets and narrowed per row.
  defp moods(user_id, from, to) do
    lower = DateTime.new!(Date.add(from, -1), ~T[00:00:00], "Etc/UTC")
    upper = DateTime.new!(Date.add(to, 2), ~T[00:00:00], "Etc/UTC")

    user_id
    |> Wellbeing.list_check_ins_between(lower, upper)
    |> Enum.reduce(%{}, fn check_in, acc ->
      case Wellness.local_day(check_in.recorded_at, check_in.recorded_tz) do
        {:ok, day} when day >= from and day <= to ->
          latest = mood(check_in)
          Map.update(acc, day, latest, &merge_mood(&1, latest))

        _outside ->
          acc
      end
    end)
  end

  # Oldest first, so the latest answer to each question of a day wins: a
  # one-tap stress answer (ADR-194) keeps the mood answered earlier that day.
  defp merge_mood(earlier, latest),
    do:
      Map.merge(earlier, latest, fn _key, before, now -> if is_nil(now), do: before, else: now end)

  defp mood(check_in) do
    answers = Map.new(check_in.answers, &{&1.question_key, &1.value})

    %{
      check_in_id: check_in.id,
      recorded_at: check_in.recorded_at,
      mood: answers["mood"],
      stress: answers["stress"],
      energy: answers["energy"]
    }
  end
end
