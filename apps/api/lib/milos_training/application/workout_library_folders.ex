defmodule MilosTraining.Application.WorkoutLibraryFolders do
  @moduledoc """
  Keeps the workout library organised for coaches who are not.

  Every organization gets two system folders:

    * `Athletes/<nickname>` — one folder per athlete; workouts programmed for an
      athlete are filed (copied) here.
    * `Classes/<year>/<month>/<date>` — workouts attached to a dated class are
      filed (copied) here, using the gym's local date.
    * `Variations for member/<nickname>` — a member's personal workouts and
      own versions of classes (ADR-125) are filed here. Member folders are
      created on first use; the copies stay hidden from the shared library.

  System folders are found by a stable `system_key`, so coaches may rename,
  move or nest them however they like; deleted ones are recreated on demand.
  """

  alias MilosTraining.Application.ListAthletes
  alias MilosTraining.{Organizations, Workouts}

  @athletes {"athletes", "Athletes"}
  @classes {"classes", "Classes"}
  @member_variations {"member_variations", "Variations for member"}

  @doc "Lists the library folders after making sure every system folder exists."
  def list(context) do
    folders = Workouts.list_folders(context)
    existing = MapSet.new(folders, & &1[:system_key])

    case sync_missing(context, existing) do
      :unchanged -> {:ok, folders}
      :ok -> {:ok, Workouts.list_folders(context)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "The athlete's own folder (`Athletes/<nickname>`)."
  def athlete_folder(context, %{id: athlete_id, nickname: nickname}) do
    with {:ok, root} <- ensure(context, @athletes, nil) do
      ensure(context, {athlete_key(athlete_id), nickname || athlete_id}, root.id)
    end
  end

  @doc "The member's own variations folder (`Variations for member/<nickname>`)."
  def member_variation_folder(context, %{id: member_id, nickname: nickname}) do
    with {:ok, root} <- ensure(context, @member_variations, nil) do
      ensure(context, {"member_variations:#{member_id}", nickname || member_id}, root.id)
    end
  end

  @doc "The folder for classes held on the gym-local date of `scheduled_at`."
  def class_day_folder(context, %DateTime{} = scheduled_at) do
    date = local_date(context, scheduled_at)
    year = Integer.to_string(date.year)
    month = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
    day = Date.to_iso8601(date)

    with {:ok, root} <- ensure(context, @classes, nil),
         {:ok, year_folder} <- ensure(context, {"classes:#{year}", year}, root.id),
         {:ok, month_folder} <-
           ensure(context, {"classes:#{year}-#{month}", month}, year_folder.id) do
      ensure(context, {"classes:#{day}", day}, month_folder.id)
    end
  end

  def class_day_folder(context, scheduled_at) when is_binary(scheduled_at) do
    case DateTime.from_iso8601(scheduled_at) do
      {:ok, datetime, _offset} -> class_day_folder(context, datetime)
      _invalid -> {:error, :invalid_scheduled_at}
    end
  end

  def class_day_folder(_context, _scheduled_at), do: {:error, :invalid_scheduled_at}

  defp sync_missing(context, existing) do
    missing_athletes =
      context
      |> athletes()
      |> Enum.reject(&MapSet.member?(existing, athlete_key(&1.id)))

    roots_missing? =
      not MapSet.member?(existing, elem(@athletes, 0)) or
        not MapSet.member?(existing, elem(@classes, 0)) or
        not MapSet.member?(existing, elem(@member_variations, 0))

    if missing_athletes == [] and not roots_missing? do
      :unchanged
    else
      with {:ok, _classes} <- ensure(context, @classes, nil),
           {:ok, _variations} <- ensure(context, @member_variations, nil) do
        Enum.reduce_while(missing_athletes, :ok, fn athlete, :ok ->
          case athlete_folder(context, athlete) do
            {:ok, _folder} -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)
        |> then(fn
          :ok -> ensure_athletes_root(context)
          error -> error
        end)
      end
    end
  end

  defp ensure_athletes_root(context) do
    case ensure(context, @athletes, nil) do
      {:ok, _root} -> :ok
      error -> error
    end
  end

  defp athletes(context) do
    case ListAthletes.call(context, nil) do
      athletes when is_list(athletes) -> athletes
      _error -> []
    end
  end

  defp ensure(context, {system_key, name}, parent_id),
    do: Workouts.ensure_system_folder(context, system_key, name, parent_id)

  defp athlete_key(athlete_id), do: "athlete:#{athlete_id}"

  defp local_date(%{organization_id: organization_id}, scheduled_at) do
    timezone = Organizations.organization_timezone(organization_id)

    case DateTime.shift_zone(scheduled_at, timezone) do
      {:ok, local} -> DateTime.to_date(local)
      {:error, _reason} -> DateTime.to_date(scheduled_at)
    end
  end
end
