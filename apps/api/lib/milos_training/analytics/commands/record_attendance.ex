defmodule MilosTraining.Analytics.Commands.RecordAttendance do
  alias MilosTraining.Analytics.AnalyticsStore
  alias MilosTraining.Scheduling

  def call(params) do
    with :ok <- validate_booking_link(params),
         {:ok, _source_fact} <- Scheduling.record_attendance(params) do
      AnalyticsStore.record_attendance(params)
    end
  end

  defp validate_booking_link(params) do
    booking_id = params[:booking_id] || params["booking_id"]
    scheduled_class_id = params[:scheduled_class_id] || params["scheduled_class_id"]
    user_id = params[:user_id] || params["user_id"]

    case booking_id do
      nil ->
        :ok

      "" ->
        :ok

      id ->
        case Scheduling.get_booking(id) do
          %{scheduled_class_id: ^scheduled_class_id, user_id: ^user_id} -> :ok
          nil -> {:error, :booking_not_found}
          _booking -> {:error, :attendance_booking_mismatch}
        end
    end
  end
end
