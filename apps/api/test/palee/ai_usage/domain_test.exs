defmodule Palee.AiUsage.DomainTest do
  use ExUnit.Case, async: true

  alias Palee.AiUsage.Domain.{GenerationEvent, PriceList, SampleStatistics, TokenUsage}

  describe "TokenUsage.from_gemini/1" do
    test "bills cached prompt tokens once, at the cache rate, and thinking as output" do
      usage =
        TokenUsage.from_gemini(%{
          "promptTokenCount" => 5_000,
          "cachedContentTokenCount" => 4_000,
          "toolUsePromptTokenCount" => 100,
          "candidatesTokenCount" => 800,
          "thoughtsTokenCount" => 1_200,
          "totalTokenCount" => 7_100
        })

      assert usage == %TokenUsage{
               input_tokens: 1_100,
               cached_input_tokens: 4_000,
               output_tokens: 800,
               thinking_tokens: 1_200
             }

      assert TokenUsage.total(usage) == 7_100
    end

    test "missing counts are zero and a missing report is nil" do
      assert TokenUsage.from_gemini(%{"promptTokenCount" => 10}) ==
               %TokenUsage{
                 input_tokens: 10,
                 cached_input_tokens: 0,
                 output_tokens: 0,
                 thinking_tokens: 0
               }

      assert TokenUsage.from_gemini(nil) == nil
    end

    test "sums usages field by field" do
      one = %TokenUsage{
        input_tokens: 1,
        cached_input_tokens: 2,
        output_tokens: 3,
        thinking_tokens: 4
      }

      assert TokenUsage.sum([one, one]) == %TokenUsage{
               input_tokens: 2,
               cached_input_tokens: 4,
               output_tokens: 6,
               thinking_tokens: 8
             }

      assert TokenUsage.sum([]) == TokenUsage.zero()
    end
  end

  describe "PriceList.cost/3" do
    @usage %TokenUsage{
      input_tokens: 1_000_000,
      cached_input_tokens: 1_000_000,
      output_tokens: 500_000,
      thinking_tokens: 500_000
    }

    test "prices at the rate in force on the day, in exact nano-USD" do
      # $0.75 + $0.075 + $3.75 per 1M
      assert PriceList.cost(@usage, "gemini-3.8-flash", ~D[2026-10-17]) ==
               {:ok, 4_575_000_000}

      assert PriceList.cost(@usage, "gemini-3.8-flash", ~D[2027-01-01]) ==
               {:ok, 9_150_000_000}
    end

    test "prices a reported model version by its model" do
      assert {:ok, 510_000_000} =
               PriceList.cost(@usage, "gemini-2.5-flash-lite-001", ~D[2026-10-17])

      assert PriceList.cost(@usage, "gemini-9-ultra", ~D[2026-10-17]) == {:error, :unpriced_model}
    end

    test "a cheaper sibling is never matched by prefix" do
      assert {:ok, rates} = PriceList.rates("gemini-2.5-flash-lite", ~D[2026-10-17])
      assert rates.input == 100
    end
  end

  describe "SampleStatistics.describe/1" do
    test "reports the mean, sample sd and standard error" do
      stats = SampleStatistics.describe([2, 4, 4, 4, 5, 5, 7, 9])
      assert stats.n == 8
      assert stats.mean == 5.0
      assert_in_delta stats.sd, 2.138, 0.001
      assert_in_delta stats.se, 2.138 / :math.sqrt(8), 0.001
      assert {stats.min, stats.max} == {2, 9}
    end

    test "leaves the spread unknown for fewer than two measurements" do
      assert %{n: 1, mean: 3.0, sd: nil, se: nil} = SampleStatistics.describe([3])
      assert %{n: 0, mean: nil} = SampleStatistics.describe([])
    end
  end

  test "metering keeps only the keys adapters may forward" do
    assert GenerationEvent.metering(%{
             locale: "el",
             metering: %{operation_id: "op", feature: "f", organization_id: "o", secret: "x"}
           }) == %{operation_id: "op", feature: "f", organization_id: "o"}

    assert GenerationEvent.metering(%{locale: "el"}) == %{}
  end
end
