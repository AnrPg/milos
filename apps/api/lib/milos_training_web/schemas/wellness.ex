defmodule MilosTrainingWeb.Schemas.Wellness do
  @moduledoc "OpenAPI shapes of Ημερολόγιο › Ευεξία (ADR-159)."

  alias OpenApiSpex.Schema

  @rungs ["private", "coach_can_view", "coach_reply_requested", "posted"]
  @status %Schema{type: :string, enum: ["none", "partial", "full"]}
  @date %Schema{type: :string, format: :date}
  @datetime %Schema{type: :string, format: :"date-time"}
  @uuid %Schema{type: :string, format: :uuid}

  @value %Schema{
    type: :object,
    description: """
    The kind's value. water: {ml}. sleep: {bed_at?, wake_at?, minutes?, quality? 1-5, nap}
    (minutes or quality required; both ends give minutes). meal: {slot?
    breakfast|lunch|dinner|snack, plan_fit? in_plan|off_plan, note?, media_id?,
    portions? {protein, carbs, veg, fat in halves}, hunger_before? 1-5, fullness_after? 1-5}.
    """,
    additionalProperties: true
  }

  @entry %Schema{
    type: :object,
    properties: %{
      id: @uuid,
      kind: %Schema{type: :string, enum: ["water", "sleep", "meal"]},
      occurred_at: @datetime,
      occurred_tz: %Schema{type: :string},
      occurred_on: @date,
      value: @value,
      source: %Schema{type: :string, enum: ["manual", "garmin", "apple_health", "health_connect"]},
      corrected: %Schema{type: :boolean},
      organization_id: %Schema{type: :string, format: :uuid, nullable: true},
      journal_visibility: %Schema{type: :string, enum: @rungs},
      inserted_at: @datetime,
      updated_at: @datetime
    },
    required: [
      :id,
      :kind,
      :occurred_at,
      :occurred_tz,
      :occurred_on,
      :value,
      :source,
      :corrected,
      :journal_visibility
    ],
    additionalProperties: false
  }

  @craving %Schema{
    type: :object,
    properties: %{
      id: @uuid,
      occurred_at: @datetime,
      occurred_tz: %Schema{type: :string},
      occurred_on: @date,
      intensity: %Schema{type: :integer, minimum: 1, maximum: 10},
      triggers: %Schema{
        type: :array,
        items: %Schema{
          type: :string,
          enum: ["stress", "fatigue", "boredom", "social", "hunger", "other"]
        }
      },
      outcome: %Schema{
        type: :string,
        enum: ["ongoing", "resisted", "ate_off_plan"],
        nullable: true
      },
      outcome_at: %Schema{type: :string, format: :"date-time", nullable: true},
      note: %Schema{type: :string, nullable: true},
      support_requested_at: %Schema{type: :string, format: :"date-time", nullable: true},
      follow_up_at: %Schema{type: :string, format: :"date-time", nullable: true},
      organization_id: %Schema{type: :string, format: :uuid, nullable: true},
      journal_visibility: %Schema{type: :string, enum: @rungs},
      inserted_at: @datetime,
      updated_at: @datetime
    },
    required: [
      :id,
      :occurred_at,
      :occurred_tz,
      :occurred_on,
      :intensity,
      :triggers,
      :journal_visibility
    ],
    additionalProperties: false
  }

  @preferences %Schema{
    type: :object,
    properties: %{
      water_goal_ml: %Schema{type: :integer, minimum: 250, maximum: 8000},
      glass_ml: %Schema{type: :integer, minimum: 50, maximum: 2000},
      sleep_goal_minutes: %Schema{type: :integer, minimum: 240, maximum: 720},
      hidden_items: %Schema{
        type: :array,
        items: %Schema{type: :string, enum: ["water", "sleep", "meals", "plan", "mood"]}
      }
    },
    required: [:water_goal_ml, :glass_ml, :sleep_goal_minutes, :hidden_items],
    additionalProperties: false
  }

  @day %Schema{
    type: :object,
    properties: %{
      date: @date,
      water: %Schema{
        type: :object,
        properties: %{
          ml: %Schema{type: :integer},
          goal_ml: %Schema{type: :integer},
          glass_ml: %Schema{type: :integer},
          count: %Schema{type: :integer},
          status: @status
        },
        required: [:ml, :goal_ml, :glass_ml, :count, :status]
      },
      sleep: %Schema{
        type: :object,
        properties: %{
          entry_id: %Schema{type: :string, format: :uuid, nullable: true},
          minutes: %Schema{type: :integer, nullable: true},
          quality: %Schema{type: :integer, nullable: true},
          source: %Schema{type: :string, nullable: true},
          nap_minutes: %Schema{type: :integer},
          goal_minutes: %Schema{type: :integer},
          status: @status
        },
        required: [:nap_minutes, :goal_minutes, :status]
      },
      meals: %Schema{
        type: :object,
        properties: %{count: %Schema{type: :integer}, status: @status},
        required: [:count, :status]
      },
      cravings: %Schema{
        type: :object,
        properties: %{
          count: %Schema{type: :integer},
          status: %Schema{type: :string, enum: ["none", "logged"]}
        },
        required: [:count, :status]
      },
      mood: %Schema{
        type: :object,
        nullable: true,
        description: "Latest Πώς νιώθω of the day (1-4 scale)",
        properties: %{
          check_in_id: @uuid,
          recorded_at: @datetime,
          mood: %Schema{type: :integer, nullable: true},
          stress: %Schema{type: :integer, nullable: true},
          energy: %Schema{type: :integer, nullable: true}
        }
      }
    },
    required: [:date, :water, :sleep, :meals, :cravings]
  }

  @week %Schema{
    type: :object,
    properties: %{
      nights_logged: %Schema{type: :integer},
      nights_on_goal: %Schema{type: :integer},
      water_days_logged: %Schema{type: :integer},
      water_days_on_goal: %Schema{type: :integer},
      meal_days_logged: %Schema{type: :integer},
      cravings: %Schema{type: :integer}
    },
    required: [
      :nights_logged,
      :nights_on_goal,
      :water_days_logged,
      :water_days_on_goal,
      :meal_days_logged,
      :cravings
    ]
  }

  def overview do
    %Schema{
      title: "WellnessOverview",
      type: :object,
      properties: %{
        from: @date,
        to: @date,
        preferences: @preferences,
        days: %Schema{type: :array, items: @day},
        week: @week,
        entries: %Schema{type: :array, items: @entry},
        cravings: %Schema{type: :array, items: @craving}
      },
      required: [:from, :to, :preferences, :days, :week, :entries, :cravings]
    }
  end

  def entry_response, do: wrap("WellnessEntryResponse", :entry, @entry)
  def craving_response, do: wrap("CravingResponse", :craving, @craving)
  def preferences_response, do: wrap("WellnessPreferencesResponse", :preferences, @preferences)

  @occurrence %{
    occurred_at: %Schema{type: :string, format: :"date-time", description: "Default: now"},
    occurred_tz: %Schema{
      type: :string,
      description: "IANA zone of the member, e.g. Europe/Athens"
    },
    organization_slug: %Schema{type: :string, description: "Gym it was logged in (provenance)"}
  }

  def entry_request do
    %Schema{
      title: "WellnessEntryRequest",
      type: :object,
      properties:
        Map.merge(@occurrence, %{
          kind: %Schema{type: :string, enum: ["water", "sleep", "meal"]},
          value: @value
        }),
      required: [:kind, :value]
    }
  end

  def entry_change_request do
    %Schema{
      title: "WellnessEntryChangeRequest",
      type: :object,
      properties: Map.merge(Map.delete(@occurrence, :organization_slug), %{value: @value})
    }
  end

  def craving_request do
    %Schema{
      title: "CravingRequest",
      type: :object,
      properties:
        Map.merge(@occurrence, %{
          intensity: %Schema{type: :integer, minimum: 1, maximum: 10},
          triggers: @craving.properties.triggers,
          outcome: @craving.properties.outcome,
          note: %Schema{type: :string, maxLength: 500, nullable: true},
          support_requested: %Schema{type: :boolean}
        })
    }
  end

  def preferences_request do
    %Schema{
      title: "WellnessPreferencesRequest",
      type: :object,
      properties: @preferences.properties,
      additionalProperties: false
    }
  end

  def erase_response do
    %Schema{
      title: "WellnessEraseResponse",
      type: :object,
      properties: %{
        erased: %Schema{type: :object, additionalProperties: %Schema{type: :integer}}
      },
      required: [:erased]
    }
  end

  def body(schema) do
    %OpenApiSpex.RequestBody{
      required: true,
      content: %{"application/json" => %OpenApiSpex.MediaType{schema: schema}}
    }
  end

  defp wrap(title, key, schema),
    do: %Schema{title: title, type: :object, properties: %{key => schema}, required: [key]}
end
