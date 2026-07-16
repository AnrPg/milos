defmodule MilosTraining.Infrastructure.Notifications.EctoNotificationStore do
  @behaviour MilosTraining.Notifications.Ports.NotificationStore

  import Ecto.Query

  alias MilosTraining.Notifications.Domain.{InboxCursor, VisibleTypes}
  alias MilosTraining.Notifications.Notification
  alias MilosTraining.Notifications.PushSetting
  alias MilosTraining.Repo

  @impl true
  def create_notification(params) do
    %Notification{}
    |> Notification.changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, %Notification{} = notification} ->
        {:ok, normalize_notification(notification)}

      {:error, %Ecto.Changeset{} = changeset} ->
        if Keyword.has_key?(changeset.errors, :dedupe_key) do
          {:ok, :duplicate}
        else
          {:error, changeset}
        end
    end
  end

  @impl true
  def list_for_user(user_id) do
    Notification
    |> where([notification], notification.user_id == ^user_id)
    |> order_by([notification], desc: notification.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_notification/1)
  end

  @impl true
  def list_inbox_page(user_id, opts) do
    limit = Keyword.fetch!(opts, :limit)
    cursor = Keyword.get(opts, :cursor)

    notifications =
      Notification
      |> where([notification], notification.user_id == ^user_id)
      |> where(
        [notification],
        fragment("? <> ALL(?)", notification.type, ^VisibleTypes.hidden_inbox_types())
      )
      |> maybe_apply_cursor(cursor)
      |> order_by([notification], desc: notification.inserted_at, desc: notification.id)
      |> limit(^limit_plus_one(limit))
      |> Repo.all()
      |> Enum.map(&normalize_notification/1)

    {page_entries, next_cursor} = split_page(notifications, limit)

    %{
      notifications: page_entries,
      next_cursor: next_cursor
    }
  end

  @impl true
  def count_unread_inbox(user_id) do
    from(notification in Notification,
      where:
        notification.user_id == ^user_id and is_nil(notification.read_at) and
          fragment("? <> ALL(?)", notification.type, ^VisibleTypes.hidden_inbox_types())
    )
    |> Repo.aggregate(:count)
  end

  @impl true
  def mark_all_read(user_id) do
    from(notification in Notification,
      where:
        notification.user_id == ^user_id and is_nil(notification.read_at) and
          fragment("? <> ALL(?)", notification.type, ^VisibleTypes.hidden_inbox_types())
    )
    |> Repo.update_all(set: [read_at: current_timestamp()])
    |> elem(0)
  end

  @impl true
  def mark_read(user_id, notification_id) do
    case Repo.get_by(Notification, id: notification_id, user_id: user_id) do
      nil ->
        false

      %Notification{read_at: nil} = notification ->
        notification
        |> Ecto.Changeset.change(read_at: current_timestamp())
        |> Repo.update()
        |> case do
          {:ok, _notification} -> true
          {:error, _changeset} -> false
        end

      %Notification{} ->
        true
    end
  end

  @impl true
  def delete_booking_pending_for_booking(booking_id) do
    Notification
    |> where(
      [n],
      n.type == :booking_pending and
        fragment("(?->>'booking_id')::text = ?", n.payload, ^booking_id)
    )
    |> Repo.delete_all()

    :ok
  end

  @impl true
  def propagate_nickname_change(old_nickname, new_nickname) do
    Repo.query!(
      "UPDATE notifications SET payload = jsonb_set(payload, '{sender_nickname}', to_jsonb($1::text)) WHERE payload->>'sender_nickname' = $2",
      [new_nickname, old_nickname]
    )

    Repo.query!(
      "UPDATE notifications SET payload = jsonb_set(payload, '{athlete_nickname}', to_jsonb($1::text)) WHERE payload->>'athlete_nickname' = $2",
      [new_nickname, old_nickname]
    )

    :ok
  end

  @impl true
  def get_push_settings do
    case Repo.one(from s in PushSetting, limit: 1) do
      nil -> normalize_push_settings(%PushSetting{})
      %PushSetting{} = settings -> normalize_push_settings(settings)
    end
  end

  @impl true
  def get_push_delivery_config do
    case Repo.one(from s in PushSetting, limit: 1) do
      nil ->
        %{}

      %PushSetting{} = settings ->
        %{
          vapid_public_key: settings.vapid_public_key,
          vapid_private_key: settings.vapid_private_key,
          vapid_subject: settings.vapid_subject
        }
    end
  end

  @impl true
  def update_push_settings(params) do
    case Repo.one(from s in PushSetting, limit: 1) do
      nil ->
        %PushSetting{}
        |> PushSetting.changeset(params)
        |> Repo.insert()
        |> normalize_push_settings_result()

      %PushSetting{} = settings ->
        settings
        |> PushSetting.changeset(params)
        |> Repo.update()
        |> normalize_push_settings_result()
    end
  end

  defp maybe_apply_cursor(query, nil), do: query

  defp maybe_apply_cursor(query, %{inserted_at: inserted_at, id: id}) do
    where(
      query,
      [notification],
      notification.inserted_at < ^inserted_at or
        (notification.inserted_at == ^inserted_at and notification.id < ^id)
    )
  end

  defp split_page(notifications, limit) do
    {entries, overflow} = Enum.split(notifications, limit)

    next_cursor =
      case {entries, overflow} do
        {[], _overflow} ->
          nil

        {_entries, []} ->
          nil

        {entries, [_next | _rest]} ->
          last_entry = List.last(entries)
          InboxCursor.encode(%{inserted_at: last_entry.inserted_at, id: last_entry.id})
      end

    {entries, next_cursor}
  end

  defp limit_plus_one(limit), do: limit + 1

  defp current_timestamp do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp normalize_notification(%Notification{} = notification) do
    %{
      id: notification.id,
      user_id: notification.user_id,
      type: to_string(notification.type),
      payload: notification.payload || %{},
      read_at: notification.read_at,
      inserted_at: notification.inserted_at
    }
  end

  defp normalize_push_settings_result({:ok, %PushSetting{} = settings}),
    do: {:ok, normalize_push_settings(settings)}

  defp normalize_push_settings_result({:error, %Ecto.Changeset{} = changeset}),
    do: {:error, changeset}

  defp normalize_push_settings(%PushSetting{} = settings) do
    %{
      id: settings.id,
      enabled: push_settings_enabled?(settings),
      vapid_public_key: settings.vapid_public_key,
      vapid_private_key_configured: present?(settings.vapid_private_key),
      vapid_subject: settings.vapid_subject,
      inserted_at: settings.inserted_at,
      updated_at: settings.updated_at
    }
  end

  defp push_settings_enabled?(%PushSetting{} = settings) do
    present?(settings.vapid_public_key) and present?(settings.vapid_private_key) and
      present?(settings.vapid_subject)
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
