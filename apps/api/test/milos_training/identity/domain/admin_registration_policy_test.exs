defmodule MilosTraining.Identity.Domain.AdminRegistrationPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Identity.Domain.AdminRegistrationPolicy

  test "accepts only the exact configured registration code" do
    assert :ok = AdminRegistrationPolicy.authorize("DEY48keGE", "DEY48keGE")

    assert {:error, :invalid_admin_registration_code} =
             AdminRegistrationPolicy.authorize("DEY48keGF", "DEY48keGE")

    assert {:error, :invalid_admin_registration_code} =
             AdminRegistrationPolicy.authorize(nil, "DEY48keGE")
  end
end
