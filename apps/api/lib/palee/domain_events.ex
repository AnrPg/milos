defmodule Palee.DomainEvents do
  @moduledoc """
  In-process domain events (ADR-144): a context announces a fact it owns
  ("a membership became active", "attendance was recorded") and other
  contexts react without the owner knowing them. Handlers are listed in
  config (`:domain_event_handlers`, event name => modules implementing
  `Palee.DomainEvents.Handler`), run after the owner's write
  succeeded, and are isolated from each other: a failing handler is logged
  and never undoes or blocks the owner's change.

  Events are plain maps with atom keys; each event's payload is documented
  where it is published. Names in use:

    * `:membership_activated` - `%{organization_id, user_id, at}`
    * `:attendance_recorded` - `%{organization_id, scheduled_class_id, user_id, booking_id, status, at}`
    * `:booking_made` - `%{organization_id, scheduled_class_id, booking_id, user_id, at}` (ADR-155)
    * `:booking_cancelled` - `%{organization_id, scheduled_class_id, booking_id, user_id, kind, by, at}`
    * `:class_cancelled` - `%{organization_id, scheduled_class_id, at}` (the class is gone)
    * `:event_attendance_recorded` - `%{organization_id, community_event_id, user_id, at}`
      (staff ticked «Ήρθε» at a club event, ADR-156)
    * `:membership_payment_recorded` - `%{organization_id, user_id, membership_id, payment_id,
      amount_cents, at}` (a package payment or receipt, not an event payment, ADR-156)
    * `:workout_result_recorded` - `%{organization_id, workout_id, at}`: a result of a box's
      workout was finished in the app or logged (ADR-253); box screens refresh their
      leaderboards
  """

  require Logger

  @type name :: atom()

  @spec publish(name(), map()) :: :ok
  def publish(name, payload) when is_atom(name) and is_map(payload) do
    for handler <- handlers(name) do
      try do
        handler.handle_event(name, payload)
      rescue
        error ->
          Logger.error(
            "domain_event_handler_failed event=#{name} handler=#{inspect(handler)} " <>
              Exception.format(:error, error, __STACKTRACE__)
          )
      catch
        kind, reason ->
          Logger.error(
            "domain_event_handler_failed event=#{name} handler=#{inspect(handler)} #{inspect({kind, reason})}"
          )
      end
    end

    :ok
  end

  defp handlers(name) do
    :palee
    |> Application.get_env(:domain_event_handlers, %{})
    |> Map.get(name, [])
  end
end
