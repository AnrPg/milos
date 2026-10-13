defmodule MilosTraining.Application.CommandClassTimer do
  @moduledoc """
  Applies a coach's command (start, pause, resume, next, previous, jump,
  adjust, reset, finish, configure) to a class timer and broadcasts the result
  to every screen following the class.
  """

  alias MilosTraining.Application.ClassTimerView
  alias MilosTraining.Execution
  alias MilosTraining.Execution.Domain.{ClassTimerMachine, TimerPresets}

  @controller_roles [:owner, :admin, :coach]

  def call(%{role: role} = context, actor, slot_id, params) when role in @controller_roles do
    command = to_string(params["command"] || params[:command] || "")
    expected_version = params["expected_version"] || params[:expected_version]
    now = DateTime.utc_now()

    with {:ok, view} <- ClassTimerView.load(context, slot_id),
         {:ok, attrs} <- next_attrs(command, params, view, now),
         {:ok, timer} <-
           Execution.save_class_timer(
             context,
             view.slot.id,
             Map.put(attrs, :controlled_by_id, actor.id),
             expected_version
           ) do
      payload = view |> ClassTimerView.with_timer(timer) |> ClassTimerView.payload(now)
      broadcast(view.slot, payload)
      {:ok, payload}
    end
  end

  def call(_context, _actor, _slot_id, _params), do: {:error, :forbidden}

  # Choosing the class's timer (a preset), or `timer_preset: null` to go back
  # to the class workout's own sequence. Only between runs.
  defp next_attrs("configure", params, view, _now) do
    status = ClassTimerView.state(view.timer).status
    raw = Map.get(params, "timer_preset", Map.get(params, :timer_preset))

    cond do
      status not in ["ready", "finished"] ->
        {:error, :class_timer_running}

      is_nil(raw) ->
        {:ok, Map.put(ClassTimerMachine.initial(), :timer_preset, nil)}

      preset = TimerPresets.parse(raw) ->
        {:ok, Map.put(ClassTimerMachine.initial(), :timer_preset, preset)}

      true ->
        {:error, :invalid_command}
    end
  end

  defp next_attrs(command, params, view, now) do
    view.timer
    |> ClassTimerView.state()
    |> ClassTimerMachine.apply_command(command, params, view.base_segments, now)
  end

  defp broadcast(slot, payload) do
    Phoenix.PubSub.broadcast(
      MilosTraining.PubSub,
      "class_timer:updated",
      {:class_timer_updated,
       %{organization_id: slot.organization_id, scheduled_class_id: slot.id, payload: payload}}
    )
  end
end
