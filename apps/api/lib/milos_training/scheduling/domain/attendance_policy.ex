defmodule MilosTraining.Scheduling.Domain.AttendancePolicy do
  def can_record_admin_attendance?(%{status: :approved}), do: :ok
  def can_record_admin_attendance?(%{status: "approved"}), do: :ok
  def can_record_admin_attendance?(_booking), do: {:error, :attendance_requires_approved_booking}
end
