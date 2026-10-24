defmodule Palee.Guides do
  @moduledoc """
  Guides bounded context (ADR-193): in-app walkthroughs that point at the
  real screens (the shop, organising events, offers and partners, your own
  club and event). The web app owns each guide's steps and copy; this
  context keeps each person's progress so a guide is offered once, resumes
  where it was left and shows done on every device. Account data, the
  owner's alone.
  """

  alias Palee.Guides.Domain.Progress
  alias Palee.Guides.GuideProgressStore

  # Domain.
  defdelegate statuses(), to: Progress
  defdelegate max_step(), to: Progress
  defdelegate max_version(), to: Progress
  defdelegate max_guides(), to: Progress
  defdelegate id_pattern(), to: Progress
  defdelegate validate_id(id), to: Progress
  defdelegate parse_change(params), to: Progress
  defdelegate apply_change(existing, change, now), to: Progress
  defdelegate over_limit?(count, existing?), to: Progress

  # Store.
  defdelegate list_progress(context), to: GuideProgressStore, as: :list
  defdelegate update_progress(context, guide_id, now, fun), to: GuideProgressStore, as: :update
  defdelegate delete_progress(context, guide_id), to: GuideProgressStore, as: :delete
end
