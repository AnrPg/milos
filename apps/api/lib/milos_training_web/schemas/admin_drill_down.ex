defmodule MilosTrainingWeb.Schemas.AdminDrillDown do
  @moduledoc false

  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid, nullable: true}
  @string %Schema{type: :string, nullable: true}
  @date %Schema{type: :string, format: :date, nullable: true}
  @date_time %Schema{type: :string, format: :"date-time", nullable: true}
  @open_object %Schema{type: :object, additionalProperties: true}
  @severity %Schema{type: :string, enum: ["high", "medium", "low"]}
  @urgency %Schema{type: :string, enum: ["urgent", "attention", "normal"]}

  def identity_schema do
    %Schema{
      type: :object,
      properties: %{
        user_id: @uuid,
        nickname: @string,
        role: @string,
        user_type: @string
      },
      required: [:user_id, :nickname, :role],
      additionalProperties: false
    }
  end

  def action_schema do
    %Schema{
      type: :object,
      properties: %{
        key: %Schema{type: :string},
        available: %Schema{type: :boolean},
        reason: @string
      },
      required: [:key, :available, :reason],
      additionalProperties: false
    }
  end

  def action_array_schema, do: %Schema{type: :array, items: action_schema()}

  def attention_item_schema do
    %Schema{
      type: :object,
      properties: %{
        type: %Schema{type: :string},
        severity: @severity,
        reason: %Schema{type: :string},
        title: %Schema{type: :string}
      },
      required: [:type, :severity, :reason, :title],
      additionalProperties: true
    }
  end

  def attention_array_schema, do: %Schema{type: :array, items: attention_item_schema()}

  def finance_drill_down_schema do
    %Schema{
      type: :object,
      properties: %{
        identity: identity_schema(),
        current_status: finance_current_status_schema(),
        package_relationship: finance_package_relationship_schema(),
        financial_timeline: %Schema{type: :array, items: finance_timeline_event_schema()},
        outstanding_items: attention_array_schema(),
        operational_context: finance_operational_context_schema(),
        actions: action_array_schema()
      },
      required: [
        :identity,
        :current_status,
        :package_relationship,
        :financial_timeline,
        :outstanding_items,
        :operational_context,
        :actions
      ],
      additionalProperties: false
    }
  end

  def coaching_drill_down_schema do
    %Schema{
      type: :object,
      properties: %{
        identity: identity_schema(),
        recent_activity: coaching_recent_activity_schema(),
        assigned_workouts: %Schema{type: :array, items: coaching_assignment_schema()},
        execution_history: %Schema{type: :array, items: coaching_execution_schema()},
        score_trends: %Schema{type: :array, items: coaching_score_trend_schema()},
        notes_context: %Schema{type: :array, items: coaching_note_context_schema()},
        attention_cues: attention_array_schema(),
        actions: action_array_schema()
      },
      required: [
        :identity,
        :recent_activity,
        :assigned_workouts,
        :execution_history,
        :score_trends,
        :notes_context,
        :attention_cues,
        :actions
      ],
      additionalProperties: false
    }
  end

  defp finance_current_status_schema do
    %Schema{
      type: :object,
      properties: %{
        state: %Schema{type: :string},
        reason: %Schema{type: :string},
        membership_status: @string,
        entitlement_status: @string,
        entitlement_source: @string,
        starts_on: @date,
        expires_on: @date,
        days_until_expiry: %Schema{type: :integer, nullable: true},
        urgency: @urgency
      },
      required: [:state, :reason, :urgency],
      additionalProperties: false
    }
  end

  defp finance_package_relationship_schema do
    %Schema{
      type: :object,
      properties: %{
        status: %Schema{type: :string},
        reason: %Schema{type: :string},
        current_package: %Schema{allOf: [@open_object], nullable: true},
        subscriptions: %Schema{type: :array, items: @open_object}
      },
      required: [:status, :reason, :current_package, :subscriptions],
      additionalProperties: false
    }
  end

  defp finance_timeline_event_schema do
    %Schema{
      type: :object,
      properties: %{
        type: %Schema{type: :string},
        id: @uuid,
        occurred_at: @date_time,
        label: %Schema{type: :string},
        status: @string,
        amount_cents: %Schema{type: :integer},
        balance_due_cents: %Schema{type: :integer, nullable: true}
      },
      required: [:type, :id, :occurred_at, :label, :amount_cents],
      additionalProperties: true
    }
  end

  defp finance_operational_context_schema do
    %Schema{
      type: :object,
      properties: %{
        notes: @string,
        signup_source: @string,
        credit_balance_cents: %Schema{type: :integer},
        open_invoice_count: %Schema{type: :integer},
        overdue_invoice_count: %Schema{type: :integer},
        last_payment: %Schema{allOf: [@open_object], nullable: true}
      },
      required: [:credit_balance_cents, :open_invoice_count, :overdue_invoice_count],
      additionalProperties: false
    }
  end

  defp coaching_recent_activity_schema do
    %Schema{
      type: :object,
      properties: %{
        state: %Schema{type: :string, enum: ["active", "drifting", "inactive"]},
        reason: %Schema{type: :string},
        urgency: @urgency,
        completed_workouts_last_14_days: %Schema{type: :integer},
        completed_workouts_last_30_days: %Schema{type: :integer},
        last_completed_at: @date_time,
        last_started_at: @date_time
      },
      required: [
        :state,
        :reason,
        :urgency,
        :completed_workouts_last_14_days,
        :completed_workouts_last_30_days,
        :last_completed_at,
        :last_started_at
      ],
      additionalProperties: false
    }
  end

  defp coaching_assignment_schema do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        master_workout_id: @uuid,
        scheduled_for: @date,
        status: %Schema{type: :string, enum: ["completed", "upcoming", "overdue", "rejected"]},
        admin_notes: @string,
        workout: @open_object,
        execution_scores: %Schema{type: :array, items: @open_object}
      },
      required: [:id, :scheduled_for, :status, :workout, :execution_scores],
      additionalProperties: false
    }
  end

  defp coaching_execution_schema do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        master_workout_id: @uuid,
        workout_title: @string,
        workout_type: @string,
        source: @string,
        status: @string,
        started_at_utc: @date_time,
        completed_at_utc: @date_time,
        section_scores: %Schema{type: :array, items: @open_object},
        exercise_note_count: %Schema{type: :integer}
      },
      required: [:id, :status, :section_scores, :exercise_note_count],
      additionalProperties: false
    }
  end

  defp coaching_score_trend_schema do
    %Schema{
      type: :object,
      properties: %{
        workout_type: %Schema{type: :string},
        entries: %Schema{type: :array, items: @open_object}
      },
      required: [:workout_type, :entries],
      additionalProperties: false
    }
  end

  defp coaching_note_context_schema do
    %Schema{
      type: :object,
      properties: %{
        type: %Schema{type: :string},
        id: @uuid,
        body: @string,
        inserted_at: @date_time
      },
      required: [:type, :body, :inserted_at],
      additionalProperties: true
    }
  end
end
