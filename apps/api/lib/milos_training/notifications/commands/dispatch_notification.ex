defmodule MilosTraining.Notifications.Commands.DispatchNotification do
  alias MilosTraining.Notifications.Commands.CreateNotification
  alias MilosTraining.Notifications.Commands.EnqueuePushDispatch
  alias MilosTraining.Notifications.Domain.{PayloadNormalizer, PushMessageBuilder}
  alias MilosTraining.Notifications.PushConfig
  alias MilosTraining.Localization
  alias MilosTraining.Organizations.OrganizationStore

  def call(user_id, type, payload, locale \\ "en") do
    normalized_payload =
      payload
      |> PayloadNormalizer.normalize()
      |> put_organization_slug(payload)
      |> enrich_payload(type, locale)

    with {:ok, notification} <-
           CreateNotification.call(%{
             user_id: user_id,
             organization_id:
               Map.get(payload, :organization_id) || Map.get(payload, "organization_id"),
             type: type,
             dedupe_key: Map.get(payload, :dedupe_key) || Map.get(payload, "dedupe_key"),
             payload: normalized_payload
           }) do
      case notification do
        :duplicate ->
          :ok

        _notification ->
          case maybe_enqueue_push(notification) do
            :ok -> {:ok, notification}
            {:error, reason} -> {:error, {:push_enqueue_failed, notification, reason}}
          end
      end
    end
  end

  defp maybe_enqueue_push(notification) do
    if PushConfig.enabled?() do
      EnqueuePushDispatch.call(notification)
    else
      :ok
    end
  end

  # Push deep links must land inside /org/:slug/... or a multi-org recipient
  # gets bounced out of the tenant they were notified about (F-09).
  defp put_organization_slug(normalized_payload, source_payload) do
    organization_id =
      Map.get(source_payload, :organization_id) || Map.get(source_payload, "organization_id")

    case organization_id && OrganizationStore.get_organization_by_id(organization_id) do
      %{slug: slug} -> Map.put_new(normalized_payload, "organization_slug", slug)
      _missing -> normalized_payload
    end
  end

  defp enrich_payload(payload, type, locale) do
    localize = fn message, bindings -> Localization.translate(locale, message, bindings) end
    message = PushMessageBuilder.build(type, payload, localize)

    payload
    |> Map.put_new("title", message.title)
    |> Map.put_new("body", message.body)
    |> Map.put_new("url", message.url)
    |> Map.put_new("locale", locale)
  end
end
