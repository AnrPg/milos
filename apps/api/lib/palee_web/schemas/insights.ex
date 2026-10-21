defmodule PaleeWeb.Schemas.Insights do
  @moduledoc """
  OpenAPI schemas for the Πρόοδος insights slot (ADR-166). The copy key is
  `insights.<rule>.<variant>`; the client formats `params`. Every insight
  is an indicator, never medical advice.
  """

  alias OpenApiSpex.Schema

  @rules ["sleep_prs", "sleep_effort", "time_of_day", "cravings", "hydration"]
  @parts ["morning", "afternoon", "evening", "night"]
  @triggers ["stress", "fatigue", "boredom", "social", "hunger"]

  defp integer(description), do: %Schema{type: :integer, description: description}

  @params %Schema{
    title: "InsightParams",
    type: :object,
    description: "The numbers of the finding; which keys appear depends on the rule and variant",
    properties: %{
      hours: %Schema{
        type: :number,
        nullable: true,
        description: "The member's sleep goal in hours"
      },
      ratio: %Schema{type: :number, nullable: true, description: "How many times as often"},
      delta: %Schema{type: :number, nullable: true, description: "RPE points harder on average"},
      pr_days: %Schema{type: :integer, nullable: true},
      part: %Schema{type: :string, nullable: true, enum: @parts ++ [nil]},
      part_count: %Schema{type: :integer, nullable: true},
      trigger: %Schema{type: :string, nullable: true, enum: @triggers ++ [nil]},
      trigger_count: %Schema{type: :integer, nullable: true},
      with_trigger: %Schema{type: :integer, nullable: true},
      total: %Schema{type: :integer, nullable: true},
      logged_days: %Schema{type: :integer, nullable: true},
      on_goal_days: %Schema{type: :integer, nullable: true},
      percent: %Schema{type: :integer, nullable: true},
      training_percent: %Schema{type: :integer, nullable: true},
      rest_percent: %Schema{type: :integer, nullable: true}
    }
  }

  @insight %Schema{
    title: "Insight",
    type: :object,
    properties: %{
      rule: %Schema{type: :string, enum: @rules},
      variant: %Schema{type: :string, description: "Copy key: insights.<rule>.<variant>"},
      params: @params,
      weeks: %Schema{type: :integer, description: "Weeks of data behind the finding"},
      period_start: %Schema{type: :string, format: :date},
      period_end: %Schema{type: :string, format: :date}
    },
    required: [:rule, :variant, :params, :weeks, :period_start, :period_end]
  }

  def response do
    %Schema{
      title: "MyInsights",
      type: :object,
      properties: %{
        state: %Schema{
          type: :string,
          enum: ["insights", "all_hidden", "no_pattern", "collecting"],
          description:
            "insights: findings to show; all_hidden: every finding dismissed; no_pattern: enough data, nothing clear; collecting: not enough data yet"
        },
        insights: %Schema{
          type: :array,
          items: @insight,
          description: "At most max_shown findings, in the rules' fixed order"
        },
        hidden_count: integer("Findings the member dismissed"),
        data_weeks: integer("Weeks of data so far (at most window_weeks)"),
        min_weeks: integer("Weeks of data before any insight"),
        window_weeks: integer("Weeks the rules look back"),
        max_shown: integer("Findings shown at a time"),
        computed_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [
        :state,
        :insights,
        :hidden_count,
        :data_weeks,
        :min_weeks,
        :window_weeks,
        :max_shown,
        :computed_at
      ]
    }
  end
end
