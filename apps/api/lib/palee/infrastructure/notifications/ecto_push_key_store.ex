defmodule Palee.Infrastructure.Notifications.EctoPushKeyStore do
  @moduledoc """
  Postgres adapter for the installation's Web Push row (ADR-277). The row is a
  singleton (unique `singleton` column); the device figures come from two
  SECURITY DEFINER functions that answer only to an active vendor, because
  browser subscriptions are personal rows under RLS.
  """

  @behaviour Palee.Notifications.Ports.PushKeyStore

  import Ecto.Query

  alias Palee.Notifications.PushSetting
  alias Palee.Repo

  @impl true
  def get do
    case Repo.one(from(s in PushSetting, limit: 1)) do
      nil -> normalize(%PushSetting{})
      %PushSetting{} = settings -> normalize(settings)
    end
  end

  @impl true
  def put_keys_if_missing(keys) do
    {:ok, stored} =
      Repo.transaction(fn ->
        row = locked_row()

        if usable?(row) do
          row
        else
          row |> PushSetting.keys_changeset(keys) |> Repo.update!()
        end
      end)

    normalize(stored)
  end

  @impl true
  def replace_keys(keys) do
    Repo.transaction(fn ->
      locked_row()
      |> PushSetting.keys_changeset(keys)
      |> Repo.update!()
      |> normalize()
    end)
  end

  @impl true
  def put_subject(subject) do
    Repo.transaction(fn ->
      case locked_row() |> PushSetting.subject_changeset(subject) |> Repo.update() do
        {:ok, settings} -> normalize(settings)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @impl true
  def device_stats do
    %{rows: [[count, last_sent_at]]} =
      Repo.query!("SELECT device_count, last_sent_at FROM palee_web_push_device_stats()")

    %{device_count: count, last_sent_at: to_utc(last_sent_at)}
  end

  @impl true
  def forget_all_devices do
    %{rows: [[removed]]} = Repo.query!("SELECT palee_forget_web_push_devices()")
    removed
  end

  # Inserts the one row if it is missing, then locks it, so concurrent
  # starts (two replicas) serialise on it and only one pair is ever kept.
  defp locked_row do
    Repo.insert!(%PushSetting{}, on_conflict: :nothing, conflict_target: :singleton)
    Repo.one!(from(s in PushSetting, lock: "FOR UPDATE"))
  end

  # A private key the current encryption key cannot read loads as nil.
  defp usable?(%PushSetting{vapid_public_key: public, vapid_private_key: private}),
    do: present?(public) and present?(private)

  defp normalize(%PushSetting{} = settings) do
    %{
      vapid_public_key: present_or_nil(settings.vapid_public_key),
      vapid_private_key: present_or_nil(settings.vapid_private_key),
      vapid_subject: present_or_nil(settings.vapid_subject),
      keys_created_at: settings.keys_created_at,
      updated_at: settings.updated_at
    }
  end

  defp to_utc(nil), do: nil
  defp to_utc(%DateTime{} = value), do: value
  defp to_utc(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
  defp present_or_nil(value), do: if(present?(value), do: value)
end
