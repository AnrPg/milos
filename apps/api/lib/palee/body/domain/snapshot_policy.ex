defmodule Palee.Body.Domain.SnapshotPolicy do
  @moduledoc """
  What a body snapshot is (ADR-158): at least one metric or one photo, a
  visibility (`private`, `coach_numbers`, `coach_full`), optional notes, and
  up to four photos, one per pose except `other`.

  Photos are always private unless the snapshot is `coach_full`, and even
  then a coach sees them only while the body-photo consent is active
  (`ConsentPolicy`).
  """

  @visibilities ~w(private coach_numbers coach_full)
  @coach_visibilities ~w(coach_numbers coach_full)
  @poses ~w(front side back other)
  @single_poses ~w(front side back)
  @max_photos 4
  @max_notes 2_000
  @photo_statuses ~w(processing ready failed)
  # A weight sent by a connected device: Garmin (P2-M13), or the phone's
  # Apple Health / Health Connect (ADR-172).
  @sources ~w(manual garmin apple_health health_connect)

  def visibilities, do: @visibilities
  def poses, do: @poses
  def max_photos, do: @max_photos
  def max_notes, do: @max_notes
  def photo_statuses, do: @photo_statuses
  def sources, do: @sources

  def validate_visibility(visibility) when visibility in @visibilities, do: :ok
  def validate_visibility(_visibility), do: {:error, :invalid_body_visibility}

  @doc "Whether a coach may read a snapshot at all."
  def shared?(visibility), do: visibility in @coach_visibilities

  @doc "Whether a snapshot's photos may reach a coach (before consent)."
  def photos_shared?(visibility), do: visibility == "coach_full"

  @doc "A snapshot must say something: one metric or one photo."
  def validate_content(metrics, photo_count) when is_map(metrics) and is_integer(photo_count) do
    if map_size(metrics) > 0 or photo_count > 0,
      do: :ok,
      else: {:error, :snapshot_empty}
  end

  def normalize_notes(nil), do: {:ok, nil}

  def normalize_notes(notes) when is_binary(notes) do
    case String.trim(notes) do
      "" ->
        {:ok, nil}

      trimmed ->
        if String.length(trimmed) <= @max_notes,
          do: {:ok, trimmed},
          else: {:error, :body_notes_too_long}
    end
  end

  def normalize_notes(_notes), do: {:error, :body_notes_too_long}

  @doc """
  Whether `new_poses` may join a snapshot that has `existing_poses`: at most
  four photos, front/side/back once each.
  """
  def validate_photos(existing_poses, new_poses)
      when is_list(existing_poses) and is_list(new_poses) do
    all = existing_poses ++ new_poses

    cond do
      Enum.any?(new_poses, &(&1 not in @poses)) ->
        {:error, :invalid_pose}

      length(all) > @max_photos ->
        {:error, :too_many_body_photos}

      Enum.any?(@single_poses, fn pose -> Enum.count(all, &(&1 == pose)) > 1 end) ->
        {:error, :pose_taken}

      true ->
        :ok
    end
  end

  @doc "A photo row's status from its upload's status."
  def photo_status("ready"), do: "ready"
  def photo_status("rejected"), do: "failed"
  def photo_status(_pending_or_processing), do: "processing"
end
