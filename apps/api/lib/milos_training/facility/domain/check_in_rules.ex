defmodule MilosTraining.Facility.Domain.CheckInRules do
  @moduledoc """
  The owner's check-in rules, «Ρυθμίσεις › Check-in» (ADR-155, decision 6),
  as plain data with their defaults and validation:

    * `window_before_minutes` / `window_after_minutes`: a scan checks in to a
      booking from this long before its class starts until this long after
      (default 30′ / 15′, each 0–120);
    * `open_gym_requires_package`: without a booking, a scan checks in to
      open gym only when the member's package covers open gym (default on);
      off lets any active member in;
    * `visitor_trial_offer`: a person who is not a member sees the box's trial
      classes at the door (default on; it still needs the trial policy on);
    * `desk_override`: the desk may check a member in despite a problem with
      their package («Check-in παρ' όλα αυτά», default off);
    * `door_rotation_seconds`: how often the door code changes (15, 30 or 60;
      default 30);
    * `member_code_mode`: the member's personal QR is `rotating` (changes
      every 30 s; no Wallet card) or `static` (one persistent, revocable code
      that can also go on a Wallet card); default `rotating`. See
      `MemberCodePolicy`.
  """

  @defaults %{
    window_before_minutes: 30,
    window_after_minutes: 15,
    open_gym_requires_package: true,
    visitor_trial_offer: true,
    desk_override: false,
    door_rotation_seconds: 30,
    member_code_mode: "rotating"
  }

  @rotations [15, 30, 60]
  @member_code_modes ~w(rotating static)
  @max_window_minutes 120

  def defaults, do: @defaults
  def fields, do: Map.keys(@defaults)
  def rotations, do: @rotations
  def member_code_modes, do: @member_code_modes

  @doc "Settings with every field present, defaults filled in."
  def effective(nil), do: @defaults

  def effective(settings) when is_map(settings),
    do: Map.new(@defaults, fn {key, default} -> {key, value_or(settings, key, default)} end)

  @doc """
  Validates a change (string or atom keys; unknown keys ignored). Returns the
  normalized change or `{:error, [{field, message}]}`.
  """
  def validate(attrs) when is_map(attrs) do
    changes =
      @defaults
      |> Map.keys()
      |> Enum.flat_map(fn key ->
        case fetch(attrs, key) do
          {:ok, value} -> [{key, value}]
          :error -> []
        end
      end)

    errors = Enum.flat_map(changes, fn {key, value} -> check(key, value) end)

    if errors == [], do: {:ok, Map.new(changes)}, else: {:error, errors}
  end

  def validate(_attrs), do: {:error, [settings: "must be an object"]}

  @doc "The booking window around a class start: `{opens_at, closes_at}`."
  def booking_window(settings, %DateTime{} = starts_at) do
    settings = effective(settings)

    {DateTime.add(starts_at, -settings.window_before_minutes * 60, :second),
     DateTime.add(starts_at, settings.window_after_minutes * 60, :second)}
  end

  @doc "Whether `now` falls in the booking window of a class starting at `starts_at`."
  def in_window?(settings, %DateTime{} = starts_at, %DateTime{} = now) do
    {opens_at, closes_at} = booking_window(settings, starts_at)
    DateTime.compare(now, opens_at) != :lt and DateTime.compare(now, closes_at) != :gt
  end

  defp check(key, value) when key in [:window_before_minutes, :window_after_minutes] do
    if is_integer(value) and value >= 0 and value <= @max_window_minutes,
      do: [],
      else: [{key, "must be a whole number of minutes from 0 to #{@max_window_minutes}"}]
  end

  defp check(:door_rotation_seconds, value) do
    if value in @rotations,
      do: [],
      else: [door_rotation_seconds: "must be one of #{Enum.join(@rotations, ", ")}"]
  end

  defp check(:member_code_mode, value) do
    if value in @member_code_modes,
      do: [],
      else: [member_code_mode: "must be one of #{Enum.join(@member_code_modes, ", ")}"]
  end

  defp check(key, value) do
    if is_boolean(value), do: [], else: [{key, "must be true or false"}]
  end

  defp fetch(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(attrs, Atom.to_string(key))
    end
  end

  defp value_or(settings, key, default) do
    case Map.get(settings, key) do
      nil -> default
      value -> value
    end
  end
end
