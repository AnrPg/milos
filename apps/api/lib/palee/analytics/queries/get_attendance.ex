defmodule Palee.Analytics.Queries.GetAttendance do
  alias Palee.Analytics.AnalyticsStore
  alias Palee.Scheduling

  def for_user_class(%{organization_id: _} = context, user_id, scheduled_class_id) do
    Scheduling.get_attendance_for_user_class(context, user_id, scheduled_class_id) ||
      AnalyticsStore.with_tenant_context(context, fn ->
        AnalyticsStore.get_attendance_for_user_class(user_id, scheduled_class_id)
      end)
  end

  def for_user_class(_user_id, _scheduled_class_id) do
    {:error, :organization_context_required}
  end
end
