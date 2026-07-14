defmodule MilosTraining.Finance.Domain.MembershipLinks do
  def validate_optional_link(_field, _membership_id, nil), do: :ok

  def validate_optional_link(field, membership_id, linked_membership_id) do
    if linked_membership_id == membership_id do
      :ok
    else
      {:error, {:membership_mismatch, field}}
    end
  end
end
