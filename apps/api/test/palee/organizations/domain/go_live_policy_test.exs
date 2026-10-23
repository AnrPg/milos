defmodule Palee.Organizations.Domain.GoLivePolicyTest do
  @moduledoc "ADR-184: the one policy that says what a demo business may not do."
  use ExUnit.Case, async: true

  alias Palee.Organizations.Domain.GoLivePolicy

  @demo_gym %{provider_kind: "gym", activation: "demo"}
  @demo_coach %{provider_kind: "coach", activation: "demo"}
  @active_gym %{provider_kind: "gym", activation: "active"}
  @organiser %{provider_kind: "organiser", activation: "demo"}

  test "only gyms and coaches in demo mode are gated" do
    assert GoLivePolicy.gated?(@demo_gym)
    assert GoLivePolicy.gated?(@demo_coach)
    assert GoLivePolicy.gated?(%{activation: "demo"})
    refute GoLivePolicy.gated?(@active_gym)
    refute GoLivePolicy.gated?(@organiser)
    refute GoLivePolicy.gated?(%{provider_kind: "gym"})
    refute GoLivePolicy.gated?(nil)
  end

  test "every action is refused with the one stable error while gated" do
    for action <- GoLivePolicy.actions() do
      assert {:error, :business_not_activated} == GoLivePolicy.check(@demo_gym, action)
      assert :ok == GoLivePolicy.check(@active_gym, action)
      assert :ok == GoLivePolicy.check(@organiser, action)
    end
  end

  test "inside its own account a demo business keeps working" do
    assert :ok == GoLivePolicy.check(@demo_coach, :take_booking, %{actor_staff?: true})
    assert :ok == GoLivePolicy.check(@demo_gym, :take_booking, %{actor_demo_person?: true})
    assert :ok == GoLivePolicy.check(@demo_gym, :grant_staff_role, %{target_self?: true})
    assert :ok == GoLivePolicy.check(@demo_gym, :grant_staff_role, %{target_demo_person?: true})
    assert :ok == GoLivePolicy.check(@demo_gym, :take_payment, %{payer_demo_person?: true})

    # A fact only opens the action it belongs to.
    assert {:error, :business_not_activated} ==
             GoLivePolicy.check(@demo_gym, :invite_people, %{actor_staff?: true})

    assert {:error, :business_not_activated} ==
             GoLivePolicy.check(@demo_gym, :take_payment, %{actor_staff?: true})

    assert {:error, :business_not_activated} ==
             GoLivePolicy.check(@demo_gym, :take_booking, %{actor_staff?: "yes"})
  end

  test "status for the web" do
    assert %{activation: "demo", gated: true} == GoLivePolicy.status(@demo_gym)
    assert %{activation: "active", gated: false} == GoLivePolicy.status(nil)
    assert ~w(gym coach) == GoLivePolicy.gated_kinds()
  end
end
