defmodule MilosTraining.DomainEvents do
  @moduledoc """
  In-process domain events (ADR-144): a context announces a fact it owns
  ("a membership became active", "attendance was recorded") and other
  contexts react without the owner knowing them. Handlers are listed in
  config (`:domain_event_handlers`, event name => modules implementing
  `MilosTraining.DomainEvents.Handler`), run after the owner's write
  succeeded, and are isolated from each other: a failing handler is logged
  and never undoes or blocks the owner's change.

  Events are plain maps with atom keys; each event's payload is documented
  where it is published. Names in use:

    * `:membership_activated` - `%{organization_id, user_id, at}`
    * `:attendance_recorded` - `%{organization_id, scheduled_class_id, user_id, booking_id, status, at}`
    * `:booking_cancelled` - `%{organization_id, booking_id, kind, by, at}`
    * `:class_cancelled` - `%{organization_id, scheduled_class_id, at}` (the class is gone)
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
    :milos_training
    |> Application.get_env(:domain_event_handlers, %{})
    |> Map.get(name, [])
  end
end
