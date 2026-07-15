defmodule MilosTraining.Finance.Domain.PackageAssignmentPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.PackageAssignmentPolicy

  test "allows active packages" do
    assert :ok = PackageAssignmentPolicy.can_assign?(%{active: true})
  end

  test "rejects inactive packages" do
    assert {:error, :package_inactive} =
             PackageAssignmentPolicy.can_assign?(%{active: false})
  end
end
