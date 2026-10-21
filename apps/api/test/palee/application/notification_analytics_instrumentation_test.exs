defmodule Palee.Application.NotificationAnalyticsInstrumentationTest do
  @moduledoc "ADR-123: in-app delivery and push delivery outcome analytics."
  use Palee.DataCase, async: false

  import Ecto.Query
  import Palee.AnalyticsHelpers

  alias Palee.Analytics.PushDispatchAttempt
  alias Palee.Notifications
  alias Palee.Notifications.Domain.PushDeliveryOutcome
  alias Palee.Workers.PushDispatchJob

  defmodule FakeDispatcher do
    @behaviour Palee.Notifications.Ports.PushDispatcher

    @impl true
    def send_push(%{endpoint: "https://push.example.test/gone"}, _message), do: {:error, :expired}

    def send_push(%{endpoint: "https://push.example.test/down"}, _message),
      do: {:error, {:http_error, 503, "upstream body with https://push.example.test/down"}}

    def send_push(_subscription, _message), do: :ok
  end

  setup do
    previous = Application.get_env(:palee, :push_dispatcher)
    Application.put_env(:palee, :push_dispatcher, FakeDispatcher)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:palee, :push_dispatcher, previous),
        else: Application.delete_env(:palee, :push_dispatcher)
    end)
  end

  defp notification!(organization, user) do
    {:ok, notification} =
      Notifications.create_notification(%{
        user_id: user.id,
        organization_id: organization.id,
        type: "booking_approved",
        payload: %{"title" => "Approved", "body" => "See you there", "url" => "/schedule"}
      })

    notification
  end

  test "a new in-app notification records notification_in_app_delivered in its tenant" do
    {organization, _owner, _context} = organization_fixture()
    {member, _member_context} = member_context(organization)

    notification = notification!(organization, member)

    event = analytics_event!(organization.id, "notification_in_app_delivered")
    assert event.context_type == "notification"
    assert event.context_id == notification.id
    assert event.user_id == member.id
    assert event.metadata == %{"type" => "booking_approved"}
  end

  test "push dispatch records sent, expired and failed outcomes with a reason class" do
    {organization, _owner, _context} = organization_fixture()
    {member, _member_context} = member_context(organization)
    notification = notification!(organization, member)

    for {name, key} <- [{"ok", "k1"}, {"gone", "k2"}, {"down", "k3"}] do
      {:ok, _subscription, _} =
        Notifications.save_push_subscription(member.id, %{
          endpoint: "https://push.example.test/#{name}",
          expiration_time: nil,
          keys: %{"p256dh" => key, "auth" => key}
        })
    end

    results =
      for name <- ["ok", "gone", "down"] do
        PushDispatchJob.perform(%Oban.Job{
          attempt: 3,
          max_attempts: 3,
          args: %{
            "user_id" => member.id,
            "endpoint" => "https://push.example.test/#{name}",
            "type" => "booking_approved",
            "payload" => %{"title" => "Approved", "body" => "See you there"},
            "organization_id" => organization.id,
            "notification_id" => notification.id
          }
        })
      end

    assert [:ok, :ok, {:error, {:http_error, 503, _}}] = results

    outcomes =
      organization.id
      |> analytics_events("notification_push_outcome")
      |> Map.new(&{&1.metadata["outcome"], &1})

    assert outcomes["sent"].metadata["reason_class"] == nil
    assert outcomes["expired"].metadata["reason_class"] == "subscription_expired"
    assert outcomes["failed"].metadata["reason_class"] == "server_error"
    assert outcomes["failed"].metadata["final_attempt"] == true
    assert outcomes["failed"].metadata["notification_type"] == "booking_approved"
    assert outcomes["failed"].context_id == notification.id
    assert outcomes["failed"].user_id == member.id

    attempts =
      PushDispatchAttempt
      |> where([a], a.organization_id == ^organization.id)
      |> Repo.all()

    assert attempts |> Enum.map(& &1.status) |> Enum.sort() == ["expired", "failed", "sent"]
    assert Enum.all?(attempts, &(String.length(&1.endpoint_hash) == 64))
    refute Enum.any?(attempts, &(&1.error && String.contains?(&1.error, "https://")))
  end

  test "outcome classification never keeps provider payloads" do
    assert PushDeliveryOutcome.classify(:ok) == {"sent", nil}
    assert PushDeliveryOutcome.classify({:error, :expired}) == {"expired", "subscription_expired"}

    assert PushDeliveryOutcome.classify({:error, {:http_error, 429, "x"}}) ==
             {"failed", "rate_limited"}

    assert PushDeliveryOutcome.classify({:error, {:http_error, 400, "x"}}) ==
             {"failed", "client_error"}

    assert PushDeliveryOutcome.classify({:error, :push_not_configured}) ==
             {"failed", "not_configured"}

    assert PushDeliveryOutcome.classify({:error, %RuntimeError{}}) == {"failed", "unknown"}
  end
end
