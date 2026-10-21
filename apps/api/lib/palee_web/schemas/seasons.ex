defmodule PaleeWeb.Schemas.Seasons do
  @moduledoc "OpenAPI schemas for seasons (ADR-167, P3-M5)."

  alias PaleeWeb.Schemas.Community
  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @date %Schema{type: :string, format: :date}
  @datetime %Schema{type: :string, format: :"date-time"}
  @maybe_datetime %Schema{type: :string, format: :"date-time", nullable: true}
  @maybe_string %Schema{type: :string, nullable: true}

  def body(schema), do: Community.body(schema)

  def status,
    do: %Schema{
      type: :string,
      enum: ~w(draft published running completed cancelled),
      description: "Running and completed follow from the dates"
    }

  def enrollment_status,
    do: %Schema{type: :string, enum: ~w(requested waitlisted active declined cancelled completed)}

  defp programme_item do
    %Schema{
      title: "SeasonProgrammeItem",
      type: :object,
      properties: %{
        day: %Schema{type: :integer, minimum: 0, description: "Day 0 is the start date"},
        workout_id: @uuid
      },
      required: [:day, :workout_id]
    }
  end

  defp coach do
    %Schema{
      title: "SeasonCoach",
      type: :object,
      properties: %{id: @uuid, nickname: @maybe_string},
      required: [:id]
    }
  end

  defp common do
    %{
      id: @uuid,
      title: %Schema{type: :string},
      description: @maybe_string,
      starts_on: @date,
      ends_on: @date,
      weeks: %Schema{type: :integer},
      capacity: %Schema{type: :integer},
      places_left: %Schema{type: :integer},
      price_cents: %Schema{type: :integer},
      currency: %Schema{type: :string},
      status: status(),
      workout_count: %Schema{type: :integer},
      coaches: %Schema{type: :array, items: coach()}
    }
  end

  @common_required [
    :id,
    :title,
    :starts_on,
    :ends_on,
    :weeks,
    :capacity,
    :places_left,
    :price_cents,
    :currency,
    :status,
    :workout_count,
    :coaches
  ]

  # Members ------------------------------------------------------------------

  def mine do
    %Schema{
      title: "SeasonMyEnrollment",
      type: :object,
      nullable: true,
      properties: %{
        id: @uuid,
        status: enrollment_status(),
        decline_reason: @maybe_string,
        requested_at: @datetime
      },
      required: [:id, :status]
    }
  end

  def member_season do
    %Schema{
      title: "MemberSeason",
      type: :object,
      properties: Map.put(common(), :mine, mine()),
      required: @common_required ++ [:mine]
    }
  end

  def member_list,
    do: %Schema{
      title: "MemberSeasonList",
      type: :object,
      properties: %{seasons: %Schema{type: :array, items: member_season()}},
      required: [:seasons]
    }

  def member_response,
    do: %Schema{
      title: "MemberSeasonResponse",
      type: :object,
      properties: %{season: member_season()},
      required: [:season]
    }

  # Staff --------------------------------------------------------------------

  defp enrollment do
    %Schema{
      title: "SeasonEnrollment",
      type: :object,
      properties: %{
        id: @uuid,
        user_id: @uuid,
        nickname: @maybe_string,
        status: enrollment_status(),
        requested_at: @datetime,
        decided_at: @maybe_datetime,
        decline_reason: @maybe_string,
        package_subscription_id: %Schema{type: :string, format: :uuid, nullable: true}
      },
      required: [:id, :user_id, :status, :requested_at]
    }
  end

  defp staff_properties do
    Map.merge(common(), %{
      welcome_message: @maybe_string,
      membership_package_id: %Schema{type: :string, format: :uuid, nullable: true},
      programme: %Schema{type: :array, items: programme_item()},
      coach_ids: %Schema{type: :array, items: @uuid},
      channel_id: %Schema{type: :string, format: :uuid, nullable: true},
      counts: %Schema{
        type: :object,
        properties: %{
          requested: %Schema{type: :integer},
          waitlisted: %Schema{type: :integer},
          active: %Schema{type: :integer}
        },
        required: [:requested, :waitlisted, :active]
      }
    })
  end

  @staff_required @common_required ++ [:programme, :coach_ids, :counts]

  def staff_season do
    %Schema{
      title: "StaffSeason",
      type: :object,
      properties: staff_properties(),
      required: @staff_required
    }
  end

  def staff_detail do
    %Schema{
      title: "StaffSeasonDetail",
      type: :object,
      properties:
        Map.put(staff_properties(), :enrollments, %Schema{type: :array, items: enrollment()}),
      required: @staff_required ++ [:enrollments]
    }
  end

  def staff_list,
    do: %Schema{
      title: "StaffSeasonList",
      type: :object,
      properties: %{
        seasons: %Schema{type: :array, items: staff_season()},
        coach_candidates: %Schema{
          type: :array,
          description: "Staff who may be named as a season's coaches",
          items: %Schema{
            type: :object,
            properties: %{
              id: %Schema{type: :string, format: :uuid},
              nickname: %Schema{type: :string, nullable: true},
              avatar_url: %Schema{type: :string, nullable: true}
            },
            required: [:id]
          }
        }
      },
      required: [:seasons, :coach_candidates]
    }

  def staff_response,
    do: %Schema{
      title: "StaffSeasonResponse",
      type: :object,
      properties: %{season: staff_detail()},
      required: [:season]
    }

  def offering_input(required \\ []) do
    %Schema{
      title: if(required == [], do: "SeasonUpdate", else: "SeasonCreate"),
      type: :object,
      properties: %{
        title: %Schema{type: :string, minLength: 2, maxLength: 80},
        description: %Schema{type: :string, maxLength: 2000, nullable: true},
        welcome_message: %Schema{type: :string, maxLength: 1000, nullable: true},
        starts_on: @date,
        weeks: %Schema{type: :integer, minimum: 1, maximum: 52},
        capacity: %Schema{type: :integer, minimum: 1, maximum: 500},
        price_cents: %Schema{type: :integer, minimum: 0},
        currency: %Schema{type: :string, maxLength: 3},
        membership_package_id: %Schema{type: :string, format: :uuid, nullable: true},
        programme: %Schema{type: :array, items: programme_item(), maxItems: 400},
        coach_ids: %Schema{type: :array, items: @uuid, maxItems: 20},
        status: %Schema{
          type: :string,
          enum: ~w(draft published cancelled),
          description: "Publish to open requests; cancel to close the season"
        }
      },
      required: required
    }
  end

  def decline_request,
    do: %Schema{
      title: "SeasonDecline",
      type: :object,
      properties: %{reason: %Schema{type: :string, maxLength: 300, nullable: true}}
    }
end
