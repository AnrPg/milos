defmodule MilosTraining.Finance.Domain.PackageAssignmentPolicy do
  def can_assign?(%{active: true}), do: :ok
  def can_assign?(%{"active" => true}), do: :ok
  def can_assign?(_package), do: {:error, :package_inactive}
end
