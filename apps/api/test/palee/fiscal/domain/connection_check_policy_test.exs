defmodule Palee.Fiscal.Domain.ConnectionCheckPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Fiscal.Domain.ConnectionCheckPolicy, as: Policy

  @now ~U[2027-03-12 10:00:00.000000Z]

  describe "kinds/1" do
    test "only what the country asks for, in screen order" do
      assert Policy.kinds(%{authority: :mydata, till_device: :none, einvoicing: []}) ==
               ["mydata", "registry"]

      assert Policy.kinds(%{authority: :none, till_device: :tse, einvoicing: []}) == ["tse"]
      assert Policy.kinds(%{authority: :none, till_device: :rksv, einvoicing: []}) == ["rksv"]

      assert Policy.kinds(%{authority: :none, till_device: :sign_fr, einvoicing: []}) ==
               ["sign_fr"]

      assert Policy.kinds(%{authority: :none, till_device: :none, einvoicing: [:peppol]}) ==
               ["peppol"]

      assert Policy.kinds(%{authority: :none, till_device: :none, einvoicing: []}) == []
      assert Policy.kinds(nil) == []
    end
  end

  describe "outcome/1" do
    test "refusals are invalid, with a stable code" do
      assert Policy.outcome({:ok, %{}}) == :ok

      assert Policy.outcome({:error, {:unauthorized, {:http, 401}}}) ==
               {:invalid, "credentials_rejected"}

      assert Policy.outcome({:error, {:unauthorized, :credentials_missing}}) ==
               {:invalid, "credentials_missing"}

      assert Policy.outcome({:error, :unit_not_found}) == {:invalid, "unit_not_found"}
      assert Policy.outcome({:error, :unit_not_ready}) == {:invalid, "unit_not_ready"}
      assert Policy.outcome({:error, :siren_missing}) == {:invalid, "siren_missing"}
      assert Policy.outcome({:error, :provider_retired}) == {:invalid, "provider_retired"}

      assert Policy.outcome({:error, {:rejected, [%{code: "system_not_found"}]}}) ==
               {:invalid, "system_not_found"}

      assert Policy.outcome({:error, {:rejected, [%{code: "E_OTHER"}]}}) ==
               {:invalid, "unit_not_found"}
    end

    test "what says nothing about the credentials leaves the connection as it is" do
      assert Policy.outcome({:error, {:network, "timeout"}}) == {:unreachable, "unreachable"}
      assert Policy.outcome({:error, {:http, 503}}) == {:unreachable, "unreachable"}
      assert Policy.outcome({:error, :limit_reached}) == {:unreachable, "limit_reached"}
      assert Policy.outcome({:error, :tax_id_missing}) == {:unreachable, "tax_id_missing"}
      assert Policy.outcome({:error, :not_found}) == {:unreachable, "tax_id_not_found"}
    end

    test "every code is a known one" do
      for reason <- [
            :credentials_rejected,
            :credentials_missing,
            :unit_not_found,
            :unit_not_ready,
            :system_not_found,
            :tax_id_missing,
            :not_found,
            :siren_missing,
            :limit_reached,
            :provisioning_failed,
            :provider_retired,
            :anything_else
          ] do
        {_kind, code} = Policy.outcome({:error, reason})
        assert code in Policy.error_codes()
      end
    end
  end

  describe "changes/3" do
    test "a pass clears the code, brings an invalid connection back and waits about 3 months" do
      changes = Policy.changes(%{status: "invalid", check_failures: 3}, :ok, @now)

      assert %{status: "active", error_code: nil, check_failures: 0, checked_at: @now} = changes
      assert DateTime.diff(changes.next_check_at, @now, :day) == 90
    end

    test "a pass leaves an active or provisioning connection's status alone" do
      refute Map.has_key?(Policy.changes(%{status: "active"}, :ok, @now), :status)
      refute Map.has_key?(Policy.changes(%{status: "provisioning"}, :ok, @now), :status)
    end

    test "a refusal marks it invalid and checks again sooner, then less often" do
      minutes =
        for failures <- 0..6 do
          changes =
            Policy.changes(
              %{status: "active", check_failures: failures},
              {:invalid, "credentials_rejected"},
              @now
            )

          assert %{status: "invalid", error_code: "credentials_rejected"} = changes
          assert changes.check_failures == failures + 1
          DateTime.diff(changes.next_check_at, @now, :minute)
        end

      assert minutes == [60, 360, 1_440, 4_320, 10_080, 10_080, 10_080]
    end

    test "an unreachable provider keeps the status and retries soon" do
      changes =
        Policy.changes(
          %{status: "active", check_failures: 0},
          {:unreachable, "unreachable"},
          @now
        )

      refute Map.has_key?(changes, :status)
      assert changes.error_code == "unreachable"
      assert DateTime.diff(changes.next_check_at, @now, :minute) == 15

      later =
        Policy.changes(
          %{status: "active", check_failures: 9},
          {:unreachable, "unreachable"},
          @now
        )

      assert DateTime.diff(later.next_check_at, @now, :minute) == 1_440
    end
  end

  test "due?/2" do
    assert Policy.due?(%{next_check_at: nil}, @now)
    assert Policy.due?(%{next_check_at: @now}, @now)
    assert Policy.due?(%{next_check_at: DateTime.add(@now, -1)}, @now)
    refute Policy.due?(%{next_check_at: DateTime.add(@now, 1)}, @now)
  end

  test "manual_allowed?/3: 30 seconds apart, 10 minutes for the registry's quota" do
    assert Policy.manual_allowed?("mydata", nil, @now) == :ok

    assert Policy.manual_allowed?("mydata", DateTime.add(@now, -10), @now) ==
             {:error, :check_too_soon}

    assert Policy.manual_allowed?("mydata", DateTime.add(@now, -30), @now) == :ok

    assert Policy.manual_allowed?("registry", DateTime.add(@now, -300), @now) ==
             {:error, :check_too_soon}

    assert Policy.manual_allowed?("registry", DateTime.add(@now, -600), @now) == :ok
  end

  test "newly_invalid?/2" do
    assert Policy.newly_invalid?("active", "invalid")
    assert Policy.newly_invalid?("provisioning", "invalid")
    refute Policy.newly_invalid?("invalid", "invalid")
    refute Policy.newly_invalid?("invalid", "active")
  end
end
