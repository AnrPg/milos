defmodule MilosTraining.Feedback.Domain.ReviewEligibility do
  @attended_statuses ["attended"]

  def completed_execution?(%{status: "completed"}), do: true
  def completed_execution?(%{completed_at_utc: %DateTime{}}), do: true
  def completed_execution?(_execution), do: false

  def attended_class?(%{status: status}) when status in @attended_statuses, do: true
  def attended_class?(_attendance), do: false
end
