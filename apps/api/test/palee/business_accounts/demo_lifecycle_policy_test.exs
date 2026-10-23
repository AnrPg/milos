defmodule Palee.BusinessAccounts.Domain.DemoLifecyclePolicyTest do
  use ExUnit.Case, async: true

  alias Palee.BusinessAccounts.Domain.DemoLifecyclePolicy, as: Policy

  @now ~U[2027-03-01 09:00:00.000000Z]
  @thresholds Policy.thresholds()

  defp days_ago(days), do: DateTime.add(@now, -days * 86_400)

  describe "thresholds" do
    test "default to a reminder at 60 days and archiving at 90" do
      assert %{reminder_after_days: 60, archive_after_days: 90, touch_interval_seconds: 3_600} =
               @thresholds

      assert Policy.notice_days(@thresholds) == 30
    end

    test "take valid overrides and ignore the rest" do
      assert %{reminder_after_days: 10, archive_after_days: 20} =
               Policy.thresholds(reminder_after_days: 10, archive_after_days: 20)

      assert %{reminder_after_days: 60, archive_after_days: 90} =
               Policy.thresholds(reminder_after_days: -1, archive_after_days: "x", other: 1)
    end

    test "always leave a notice period after the reminder" do
      assert %{reminder_after_days: 30, archive_after_days: 31} =
               Policy.thresholds(%{reminder_after_days: 30, archive_after_days: 10})
    end
  end

  describe "stage/3" do
    test "keeps a demo used recently" do
      assert :keep ==
               Policy.stage(
                 %{last_active_at: days_ago(59), reminder_sent_at: nil},
                 @now,
                 @thresholds
               )
    end

    test "reminds once after 60 idle days" do
      assert :remind ==
               Policy.stage(
                 %{last_active_at: days_ago(61), reminder_sent_at: nil},
                 @now,
                 @thresholds
               )

      assert :keep ==
               Policy.stage(
                 %{last_active_at: days_ago(75), reminder_sent_at: days_ago(14)},
                 @now,
                 @thresholds
               )
    end

    test "archives after 90 idle days and 30 days of notice" do
      assert :archive ==
               Policy.stage(
                 %{last_active_at: days_ago(91), reminder_sent_at: days_ago(31)},
                 @now,
                 @thresholds
               )
    end

    test "a demo found idle for longer gets its reminder and notice first" do
      assert :remind ==
               Policy.stage(
                 %{last_active_at: days_ago(200), reminder_sent_at: nil},
                 @now,
                 @thresholds
               )

      assert :keep ==
               Policy.stage(
                 %{last_active_at: days_ago(200), reminder_sent_at: days_ago(5)},
                 @now,
                 @thresholds
               )
    end
  end

  test "the dedupe key is one per demo and idle spell" do
    first = Policy.reminder_dedupe_key("org", days_ago(61))
    assert first == Policy.reminder_dedupe_key("org", days_ago(61))
    refute first == Policy.reminder_dedupe_key("org", days_ago(10))
    refute first == Policy.reminder_dedupe_key("other", days_ago(61))
    assert String.starts_with?(first, "business_demo_idle:org:")
  end

  test "the cutoffs and the archive day follow the thresholds" do
    assert Policy.reminder_cutoff(@now, @thresholds) == days_ago(60)
    assert Policy.archive_cutoff(@now, @thresholds) == days_ago(90)
    assert Policy.reminded_cutoff(@now, @thresholds) == days_ago(30)
    assert Policy.archive_on(days_ago(60), @thresholds) == ~D[2027-03-31]
  end
end
