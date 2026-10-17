defmodule MilosTraining.AiUsage.RecordAiUsageTest do
  @moduledoc """
  ADR-141: billed model calls become the gym's usage records, priced on the
  day of the call, grouped per operation and summarised per feature, and are
  isolated per tenant - under the RLS-enforcing runtime role.
  """

  use MilosTraining.DataCase, async: false

  @moduletag :rls_enforced

  alias MilosTraining.AiUsage
  alias MilosTraining.AiUsage.Domain.TokenUsage
  alias MilosTraining.Application.{AnalyzeFreeTextWorkout, RecordAiUsage}
  alias MilosTraining.Organizations
  alias MilosTraining.TestFixtures

  defp tenant(name) do
    bypass_rls(fn ->
      owner = TestFixtures.admin_fixture()

      {:ok, organization} =
        Organizations.create_organization(%{
          name: "#{name} #{System.unique_integer([:positive])}"
        })

      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: owner.id,
          role: :owner,
          status: :active,
          joined_at: DateTime.utc_now()
        })

      {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
      context
    end)
  end

  defp usage(input, cached, output, thinking),
    do: %TokenUsage{
      input_tokens: input,
      cached_input_tokens: cached,
      output_tokens: output,
      thinking_tokens: thinking
    }

  defp report(context, operation_id, usage, overrides \\ %{}) do
    AiUsage.report_generation(
      usage,
      1_200,
      Map.merge(
        %{
          organization_id: context.organization_id,
          user_id: context.user_id,
          operation_id: operation_id,
          feature: "workout_free_text",
          agent: "parser",
          provider: "gemini",
          model: "gemini-3.8-flash",
          model_version: "gemini-3.8-flash-001",
          occurred_at: ~U[2026-10-17 10:00:00Z]
        },
        overrides
      )
    )
  end

  setup do
    RecordAiUsage.attach()
    :ok
  end

  test "records each call priced on its day and totals the operation" do
    gym = tenant("Gym")
    operation_id = Ecto.UUID.generate()

    report(gym, operation_id, usage(1_000, 2_000, 300, 700), %{agent: "structure"})

    report(gym, operation_id, usage(2_000, 0, 500, 1_500), %{
      occurred_at: ~U[2026-10-17 10:00:05Z]
    })

    report(gym, operation_id, usage(1_000, 0, 0, 0), %{
      agent: "proofreader",
      occurred_at: ~U[2027-01-02 10:00:00Z]
    })

    result = AiUsage.operation_usage(gym, operation_id)

    assert Enum.map(result.calls, & &1.agent) == ["structure", "parser", "proofreader"]
    # 1000×750 + 2000×75 + 1000×3750 | 2000×750 + 2000×3750 | 1000×1500 (2027 rate)
    assert Enum.map(result.calls, & &1.cost_nano_usd) == [4_650_000, 9_000_000, 1_500_000]
    assert result.cost_nano_usd == 15_150_000
    assert_in_delta result.cost_usd, 0.01515, 1.0e-12
    assert result.total_tokens == 9_000
    assert result.unpriced_calls == 0
    assert hd(result.calls).user_id == gym.user_id
  end

  test "keeps unpriced models visible and summarises per feature and model" do
    gym = tenant("Gym")
    first = Ecto.UUID.generate()
    second = Ecto.UUID.generate()

    report(gym, first, usage(1_000, 0, 1_000, 0))
    report(gym, second, usage(3_000, 0, 1_000, 0))
    report(gym, second, usage(10, 0, 1, 0), %{model: "gemini-unknown"})

    report(gym, Ecto.UUID.generate(), usage(100, 0, 1, 0), %{
      feature: "workout_icon",
      model: "gemini-2.5-flash-lite"
    })

    summary =
      AiUsage.usage_summary(gym, %{
        from: ~U[2026-10-01 00:00:00Z],
        to: ~U[2026-11-01 00:00:00Z]
      })

    assert [icon, free_text, unknown] =
             Enum.sort_by(summary.rows, &{&1.feature != "workout_icon", &1.model})

    assert %{feature: "workout_icon", operations: 1, calls: 1, cost_nano_usd: 10_400} = icon

    assert %{operations: 2, calls: 2, input_tokens: 4_000, output_tokens: 2_000} = free_text
    assert free_text.cost_nano_usd == 4_000 * 750 + 2_000 * 3_750
    assert_in_delta free_text.mean_cost_per_operation_usd, 0.00525, 1.0e-12

    assert %{model: "gemini-unknown", unpriced_calls: 1, cost_nano_usd: 0} = unknown
    assert summary.cost_nano_usd == icon.cost_nano_usd + free_text.cost_nano_usd
  end

  test "a gym never sees another gym's usage, and untenanted calls are not stored" do
    gym = tenant("Gym")
    other = tenant("Other")
    operation_id = Ecto.UUID.generate()

    report(gym, operation_id, usage(1_000, 0, 10, 0))
    report(%{organization_id: nil, user_id: nil}, operation_id, usage(5_000, 0, 10, 0))

    assert [%{input_tokens: 1_000}] = AiUsage.operation_usage(gym, operation_id).calls
    assert AiUsage.operation_usage(other, operation_id).calls == []
    assert AiUsage.usage_summary(other).rows == []
  end

  test "the coach's analysis is metered for their gym under one operation" do
    gym = tenant("Gym")
    parent = self()

    Process.put(:fake_workout_text_analyzer, fn _text, options ->
      send(parent, {:metering, options.metering})
      {:ok, %{"workout" => %{"title" => "AMRAP"}, "sections" => [], "issues" => []}}
    end)

    assert {:ok, %{"operation_id" => operation_id}} =
             AnalyzeFreeTextWorkout.call(gym, %{"text" => "AMRAP 10\n10 burpees"})

    assert_received {:metering, metering}

    assert metering == %{
             organization_id: gym.organization_id,
             user_id: gym.user_id,
             operation_id: operation_id,
             feature: "workout_free_text"
           }
  end
end
