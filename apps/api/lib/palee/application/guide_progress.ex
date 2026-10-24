defmodule Palee.Application.GuideProgress do
  @moduledoc """
  ADR-193: a person's progress through the in-app walkthroughs. `list/1`
  answers every guide they have touched; `put/3` records a step reached, a
  finish or a «not now», and `reset/2` forgets one guide so it is offered
  again. Each change emits `[:palee, :guides, :progress]` telemetry (guide,
  status, step, version and run), which is how completion and drop-off are
  observed.
  """

  alias Palee.Guides

  def list(context), do: {:ok, %{guides: Guides.list_progress(context)}}

  def put(context, guide_id, params, now \\ DateTime.utc_now()) do
    with :ok <- Guides.validate_id(guide_id),
         {:ok, change} <- Guides.parse_change(params),
         {:ok, progress} <-
           Guides.update_progress(context, guide_id, now, &decide(&1, &2, change, now)) do
      emit(progress)
      {:ok, progress}
    end
  end

  def reset(context, guide_id) do
    with :ok <- Guides.validate_id(guide_id),
         :ok <- Guides.delete_progress(context, guide_id),
         do: list(context)
  end

  defp decide(existing, count, change, now) do
    if Guides.over_limit?(count, existing != nil),
      do: {:error, :too_many_guides},
      else: {:ok, Guides.apply_change(existing, change, now)}
  end

  defp emit(progress) do
    :telemetry.execute([:palee, :guides, :progress], %{count: 1, step: progress.step}, %{
      guide_id: progress.guide_id,
      status: progress.status,
      version: progress.version,
      runs: progress.runs
    })
  end
end
