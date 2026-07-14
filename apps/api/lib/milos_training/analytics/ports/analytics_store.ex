defmodule MilosTraining.Analytics.Ports.AnalyticsStore do
  @callback record_event(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback record_notification_click(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback record_push_attempt(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback record_attendance(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback record_communication_message(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback get_attendance_for_user_class(Ecto.UUID.t(), Ecto.UUID.t()) :: map() | nil
  @callback upsert_exercise_catalog_entry(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback analytics_summary(map()) :: map()
end
