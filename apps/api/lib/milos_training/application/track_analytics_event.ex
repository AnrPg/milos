defmodule MilosTraining.Application.TrackAnalyticsEvent do
  @moduledoc """
  One-line, best-effort analytics instrumentation for application services
  (ADR-105).

      TrackAnalyticsEvent.call("workout_published", context, workout, %{metadata: %{...}})

  * `actor` - the acting `TenantContext` (supplies organization, user and
    role), or `nil` for system/job facts (then `extra` or the subject must
    carry `organization_id`).
  * `subject` - the primary operation's result; its id becomes `context_id`
    and the keys registered for the event in
    `MilosTraining.Analytics.Domain.EventCatalog` are copied into metadata.
  * `extra` - see `EventCatalog.build/4`.

  It always returns `:ok`: building or recording the event can never change
  the outcome of the operation being instrumented (`call_unsafe` semantics).
  """

  alias MilosTraining.Analytics
  alias MilosTraining.Application.RecordAnalyticsEvent

  def call(event_name, actor, subject, extra \\ %{}) do
    extra = Map.put_new(extra, :occurred_at, DateTime.utc_now())

    case Analytics.build_event(event_name, map_or_nil(actor), map_or_nil(subject), extra) do
      {:ok, attrs} -> RecordAnalyticsEvent.call_unsafe(event_name, attrs)
      {:error, _reason} -> :ok
    end
  rescue
    _error -> :ok
  end

  defp map_or_nil(value) when is_map(value), do: value
  defp map_or_nil(_value), do: nil
end
