defmodule MilosTraining.Analytics.Commands.RecordAttendance do
  alias MilosTraining.Analytics.AnalyticsStore
  alias MilosTraining.Scheduling

  def call(%{organization_id: _} = context, params) do
    with :ok <- validate_booking_link(context, params),
         {:ok, _source_fact} <- Scheduling.record_attendance(context, params) do
      AnalyticsStore.with_tenant_context(context, fn ->
        AnalyticsStore.record_attendance(params)
      end)
    end
  end

  def call(_params) do
    {:error, :organization_context_required}
  end

  defp validate_booking_link(context, params) do
    booking_id = params[:booking_id] || params["booking_id"]
    scheduled_class_id = params[:scheduled_class_id] || params["scheduled_class_id"]
    user_id = params[:user_id] || params["user_id"]

    case booking_id do
      nil ->
        :ok

      "" ->
        :ok

      id ->
        case Scheduling.get_booking(context, id) do
          %{scheduled_class_id: ^scheduled_class_id, user_id: ^user_id} -> :ok
          nil -> {:error, :booking_not_found}
          _booking -> {:error, :attendance_booking_mismatch}
        end
    end
  end
end
