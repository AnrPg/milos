defmodule PaleeWeb.Schemas.Trials do
  @moduledoc "OpenAPI schemas for trials and talking to a box (ADR-144, P2-M3)."

  alias PaleeWeb.Schemas.Social
  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @datetime %Schema{type: :string, format: :"date-time"}
  @maybe_datetime %Schema{type: :string, format: :"date-time", nullable: true}
  @maybe_string %Schema{type: :string, nullable: true}

  def body(schema), do: Social.body(schema)

  def status,
    do: %Schema{
      type: :string,
      enum: ~w(requested booked declined cancelled expired attended no_show converted)
    }

  def blocked_reason,
    do: %Schema{
      type: :string,
      nullable: true,
      enum: [nil | ~w(already_member trial_for_first_timers_only trial_already_used)],
      description: "Why this person can't ask for a trial here; null when they can"
    }

  # Box page -----------------------------------------------------------------

  def offer do
    %Schema{
      title: "TrialOffer",
      type: :object,
      nullable: true,
      description: "What the box offers a visitor; null for members and when trials are off",
      properties: %{
        enabled: %Schema{type: :boolean},
        approval: %Schema{type: :string, enum: ~w(auto manual)},
        bring_note: @maybe_string,
        horizon_days: %Schema{type: :integer, nullable: true},
        blocked_reason: blocked_reason(),
        mine: %Schema{
          type: :object,
          nullable: true,
          properties: %{id: @uuid, status: status(), scheduled_class_id: @uuid},
          required: [:id, :status]
        }
      },
      required: [:enabled, :approval]
    }
  end

  def request do
    %Schema{
      title: "TrialAsk",
      type: :object,
      properties: %{
        scheduled_class_id: @uuid,
        note: %Schema{type: :string, maxLength: 500, nullable: true},
        phone: %Schema{type: :string, maxLength: 24, nullable: true},
        source: %Schema{type: :string, enum: ~w(box_page schedule qr_door referral event)},
        referral_event_id: %Schema{
          type: :string,
          format: :uuid,
          description:
            "The club event whose trial offer led here (ADR-153); the source becomes event"
        },
        client_operation_id: @uuid
      },
      required: [:scheduled_class_id]
    }
  end

  # The person's trial -------------------------------------------------------

  defp class do
    %Schema{
      title: "TrialClass",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, nullable: true},
        name: @maybe_string,
        scheduled_at: @datetime,
        duration_minutes: %Schema{type: :integer, nullable: true},
        location_id: %Schema{type: :string, format: :uuid, nullable: true},
        class_type: %Schema{
          type: :object,
          nullable: true,
          properties: %{id: @uuid, name: %Schema{type: :string}},
          required: [:id, :name]
        }
      },
      required: [:scheduled_at]
    }
  end

  defp location do
    %Schema{
      title: "TrialLocation",
      type: :object,
      nullable: true,
      properties: %{
        id: @uuid,
        name: %Schema{type: :string},
        address: @maybe_string,
        city: @maybe_string,
        neighbourhood: @maybe_string,
        latitude: %Schema{type: :number, nullable: true},
        longitude: %Schema{type: :number, nullable: true}
      },
      required: [:id, :name]
    }
  end

  defp common do
    %{
      id: @uuid,
      organization_id: @uuid,
      user_id: @uuid,
      scheduled_class_id: %Schema{type: :string, format: :uuid, nullable: true},
      booking_id: %Schema{type: :string, format: :uuid, nullable: true},
      status: status(),
      note: @maybe_string,
      class_starts_at: @datetime,
      decided_at: @maybe_datetime,
      decline_reason: @maybe_string,
      attended_at: @maybe_datetime,
      converted_at: @maybe_datetime,
      cancelled_at: @maybe_datetime,
      inserted_at: @datetime,
      referral_event_id: %Schema{type: :string, format: :uuid, nullable: true},
      class: class()
    }
  end

  def mine do
    %Schema{
      title: "MyTrial",
      type: :object,
      properties:
        Map.merge(common(), %{
          box: %Schema{allOf: [Social.box()], nullable: true},
          location: location(),
          bring_note: @maybe_string,
          time_zone: %Schema{
            type: :string,
            description: "ADR-179: the gym's IANA zone; the class shows on this clock"
          },
          follow_up: %Schema{
            type: :boolean,
            description: "Show «Πώς σου φάνηκε;» with «Θέλω να γραφτώ»"
          }
        }),
      required: [:id, :status, :class_starts_at, :class, :follow_up]
    }
  end

  def mine_response,
    do: %Schema{
      title: "MyTrialResponse",
      type: :object,
      properties: %{trial: mine()},
      required: [:trial]
    }

  def mine_list,
    do: %Schema{
      title: "MyTrialsResponse",
      type: :object,
      properties: %{trials: %Schema{type: :array, items: mine()}},
      required: [:trials]
    }

  def follow_up_request,
    do: %Schema{
      title: "TrialFollowUp",
      type: :object,
      properties: %{action: %Schema{type: :string, enum: ~w(join dismiss)}},
      required: [:action]
    }

  def follow_up_response,
    do: %Schema{
      title: "TrialFollowUpResponse",
      type: :object,
      properties: %{trial: mine(), conversation: %Schema{allOf: [conversation()], nullable: true}},
      required: [:trial]
    }

  # Staff --------------------------------------------------------------------

  def policy do
    %Schema{
      title: "TrialPolicy",
      type: :object,
      properties: %{
        enabled: %Schema{type: :boolean},
        approval: %Schema{type: :string, enum: ~w(auto manual)},
        weekly_limit: %Schema{type: :integer, minimum: 1, maximum: 500, nullable: true},
        per_person_limit: %Schema{type: :integer, minimum: 1, maximum: 10},
        seats_per_class: %Schema{type: :integer, minimum: 1, maximum: 50},
        class_type_ids: %Schema{type: :array, items: @uuid, maxItems: 100},
        horizon_days: %Schema{type: :integer, minimum: 1, maximum: 90, nullable: true},
        first_timers_only: %Schema{type: :boolean},
        no_show_consumes: %Schema{type: :boolean},
        bring_note: %Schema{type: :string, maxLength: 600, nullable: true},
        conversion_package_id: %Schema{type: :string, format: :uuid, nullable: true}
      }
    }
  end

  def policy_response,
    do: %Schema{
      title: "TrialPolicyResponse",
      type: :object,
      properties: %{policy: policy(), this_week: %Schema{type: :integer}},
      required: [:policy, :this_week]
    }

  def staff_trial do
    %Schema{
      title: "StaffTrial",
      type: :object,
      properties:
        Map.merge(common(), %{
          person: %Schema{
            type: :object,
            nullable: true,
            properties: %{
              id: @uuid,
              nickname: @maybe_string,
              avatar_url: @maybe_string
            },
            required: [:id]
          },
          phone: @maybe_string,
          source: %Schema{type: :string},
          decided_by_id: %Schema{type: :string, format: :uuid, nullable: true},
          join_interest_at: @maybe_datetime
        }),
      required: [:id, :status, :class_starts_at, :class]
    }
  end

  def staff_trial_response,
    do: %Schema{
      title: "StaffTrialResponse",
      type: :object,
      properties: %{trial: staff_trial()},
      required: [:trial]
    }

  def stage, do: %Schema{type: :string, enum: ~w(requests upcoming visited joined)}

  def queue_response do
    count = %Schema{type: :integer}

    %Schema{
      title: "TrialQueueResponse",
      type: :object,
      properties: %{
        stage: stage(),
        counts: %Schema{
          type: :object,
          properties: %{requests: count, upcoming: count, visited: count, joined: count},
          required: [:requests, :upcoming, :visited, :joined]
        },
        trials: %Schema{type: :array, items: staff_trial()},
        stats: %Schema{
          type: :object,
          properties: %{
            days: count,
            requested: count,
            booked: count,
            attended: count,
            no_show: count,
            converted: count,
            declined: count,
            cancelled: count
          },
          required: [:days, :requested, :booked, :attended, :no_show, :converted]
        }
      },
      required: [:stage, :counts, :trials, :stats]
    }
  end

  def decline_request,
    do: %Schema{
      title: "TrialDecline",
      type: :object,
      properties: %{reason: %Schema{type: :string, maxLength: 300, nullable: true}}
    }

  def attendance_request,
    do: %Schema{
      title: "TrialAttendance",
      type: :object,
      properties: %{status: %Schema{type: :string, enum: ~w(attended no_show)}},
      required: [:status]
    }

  # Talking to a box -----------------------------------------------------------

  @box_topics ~w(booking payment membership facility training)

  defp message do
    %Schema{
      title: "BoxConversationMessage",
      type: :object,
      properties: %{
        id: @uuid,
        thread_id: @uuid,
        sender_id: @uuid,
        body: %Schema{type: :string},
        message_type: %Schema{type: :string},
        topic: %Schema{type: :string, enum: @box_topics, nullable: true},
        client_operation_id: %Schema{type: :string, format: :uuid, nullable: true},
        inserted_at: @datetime
      },
      required: [:id, :sender_id, :body, :inserted_at]
    }
  end

  def conversation do
    %Schema{
      title: "BoxConversation",
      type: :object,
      properties: %{
        thread_id: @uuid,
        box: Social.box(),
        member: %Schema{type: :boolean},
        blocked: %Schema{
          type: :boolean,
          description: "ADR-282: the box no longer receives your messages"
        },
        staff: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{id: @uuid, nickname: @maybe_string, avatar_url: @maybe_string},
            required: [:id]
          }
        },
        last_read_message_id: %Schema{type: :string, format: :uuid, nullable: true},
        conversion_package: %Schema{
          type: :object,
          nullable: true,
          description: "Board 6 Q6: the package the box offers people who join after a trial",
          properties: %{
            id: @uuid,
            name: %Schema{type: :string},
            description: @maybe_string,
            base_price_cents: %Schema{type: :integer},
            currency: %Schema{type: :string},
            billing_period: @maybe_string
          },
          required: [:id, :name, :base_price_cents, :currency]
        },
        messages: %Schema{type: :array, items: message()}
      },
      required: [:thread_id, :box, :member, :staff]
    }
  end

  def conversation_response,
    do: %Schema{
      title: "BoxConversationResponse",
      type: :object,
      properties: %{conversation: conversation()},
      required: [:conversation]
    }

  def message_request,
    do: %Schema{
      title: "BoxConversationSend",
      type: :object,
      properties: %{
        body: %Schema{type: :string, minLength: 1, maxLength: 4000},
        topic: %Schema{
          type: :string,
          enum: @box_topics,
          nullable: true,
          description: "ADR-282: what it is about; training also reaches your coach"
        },
        client_operation_id: @uuid
      },
      required: [:body]
    }

  def message_response,
    do: %Schema{
      title: "BoxConversationMessageResponse",
      type: :object,
      properties: %{message: message()},
      required: [:message]
    }

  def read_request,
    do: %Schema{
      title: "BoxConversationRead",
      type: :object,
      properties: %{message_id: @uuid},
      required: [:message_id]
    }

  def conversations_response do
    %Schema{
      title: "BoxConversationsResponse",
      type: :object,
      properties: %{
        conversations: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              thread_id: @uuid,
              box: Social.box(),
              last_message: %Schema{allOf: [message()], nullable: true},
              unread: %Schema{type: :boolean}
            },
            required: [:thread_id, :box, :unread]
          }
        }
      },
      required: [:conversations]
    }
  end
end
