defmodule Palee.Application.MyBody do
  @moduledoc """
  The person's own body settings, health consents and the log of coach
  reads (ADR-158). Withdrawing the body-photo consent hides every photo from
  coaches at once (row security checks it on each read); the photos stay
  the person's until they delete them.
  """

  alias Palee.Application.{BodyPhotos, BodyPresenter}
  alias Palee.{Body, Identity, Organizations}

  @access_log_limit 200

  def settings(%{user_id: user_id} = context) do
    settings = Body.settings(context, user_id)
    {:ok, settings_payload(settings)}
  end

  def update_settings(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    current = Body.settings(context, user_id)

    with {:ok, changes} <- Body.settings_changes(current, params, now),
         {:ok, _stored} <- Body.put_settings(context, user_id, changes) do
      settings(context)
    end
  end

  defp settings_payload(settings) do
    %{
      settings: BodyPresenter.settings(settings),
      catalog: Body.metric_catalog(settings.units),
      photos: BodyPhotos.capabilities(),
      ranges: Body.ranges(),
      max_reminder_weeks: Body.max_reminder_weeks()
    }
  end

  def consents(%{user_id: user_id} = context),
    do: {:ok, context |> Body.list_consents(user_id) |> Body.consent_summary()}

  def grant(%{user_id: user_id} = context, scope, now \\ DateTime.utc_now()) do
    with :ok <- Body.validate_consent_scope(scope),
         {:ok, _consent} <- Body.grant_consent(context, user_id, scope, now) do
      consents(context)
    end
  end

  def withdraw(%{user_id: user_id} = context, scope, now \\ DateTime.utc_now()) do
    with :ok <- Body.validate_consent_scope(scope) do
      _count = Body.withdraw_consent(context, user_id, scope, now)
      consents(context)
    end
  end

  @doc "Who of your coaches looked at your shared snapshots, newest first."
  def access_log(%{user_id: user_id} = context) do
    entries = Body.list_access_log(context, user_id, @access_log_limit)

    readers =
      entries
      |> Enum.map(& &1.reader_user_id)
      |> Enum.uniq()
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1.nickname})

    gyms =
      entries
      |> Enum.map(& &1.organization_id)
      |> Enum.uniq()
      |> Map.new(fn id ->
        {id,
         case Organizations.get_by_id(id) do
           %{name: name} -> name
           _missing -> nil
         end}
      end)

    {:ok,
     Enum.map(entries, fn entry ->
       %{
         id: entry.id,
         read_at: entry.read_at,
         subject: entry.subject,
         snapshot_ids: entry.snapshot_ids,
         photos_shown: entry.photos_shown,
         reader: %{id: entry.reader_user_id, nickname: Map.get(readers, entry.reader_user_id)},
         organization: %{id: entry.organization_id, name: Map.get(gyms, entry.organization_id)}
       }
     end)}
  end
end
