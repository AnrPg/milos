defmodule PaleeWeb.AdminSettingsController do
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{GetAdminSettings, UpdateAdminSettings}
  alias Palee.Finance
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Settings"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:update]

  # ADR-226: the box sets only the streak shields; the weekly goal is personal.
  @streak_shields_schema %Schema{
    type: :integer,
    minimum: 0,
    maximum: 5,
    description: "Streak shields each member gets at every renewal (0 turns shields off)"
  }

  @streak_shield_reset_day_schema %Schema{
    type: :integer,
    minimum: 1,
    maximum: 28,
    nullable: true,
    description:
      "Day of the month the shields renew; null renews each member's on their sign-up day"
  }

  @gamification_settings_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, nullable: true},
      streak_shields: @streak_shields_schema,
      streak_shield_reset_day: @streak_shield_reset_day_schema,
      leaderboard_enabled: %Schema{type: :boolean},
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:leaderboard_enabled, :streak_shields]
  }

  @expiry_reminder_days_schema %Schema{
    type: :integer,
    minimum: 0,
    maximum: 60,
    description: "Days before a subscription ends to remind the member (0 = no reminder)"
  }

  @grace_days_schema %Schema{
    type: :integer,
    minimum: 0,
    maximum: 60,
    description:
      "Slack days after a subscription ends or an invoice falls overdue before the member loses access"
  }

  @finance_settings_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, nullable: true},
      payment_reminder_interval_days: %Schema{type: :integer, minimum: 1},
      subscription_expiry_reminder_days: @expiry_reminder_days_schema,
      subscription_grace_days: @grace_days_schema,
      document_mode: %Schema{type: :string, enum: ["invoice", "receipt"]},
      package_modules: %Schema{type: :array, items: %Schema{type: :string}},
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [
      :payment_reminder_interval_days,
      :subscription_expiry_reminder_days,
      :subscription_grace_days,
      :document_mode
    ]
  }

  @scheduling_settings_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, nullable: true},
      default_capacity: %Schema{type: :integer, minimum: 1, maximum: 500},
      default_auto_approve: %Schema{type: :boolean},
      default_booking_timeout_minutes: %Schema{type: :integer, minimum: 1, maximum: 10_080},
      default_booking_window_days: %Schema{
        type: :integer,
        minimum: 1,
        maximum: 365,
        nullable: true
      },
      default_cancellation_cutoff_hours: %Schema{
        type: :integer,
        minimum: 0,
        maximum: 168,
        nullable: true
      },
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:default_capacity, :default_auto_approve, :default_booking_timeout_minutes]
  }

  @provider_settings_schema %Schema{
    type: :object,
    description:
      "ADR-162: how members see this organization: a gym or an independent coach. Only the owner may change it.",
    properties: %{
      kind: %Schema{type: :string, enum: ["gym", "coach", "organiser"]},
      editable: %Schema{type: :boolean}
    },
    required: [:kind, :editable]
  }

  @wod_goals_visible_by_default_schema %Schema{
    type: :boolean,
    description:
      "ADR-163: starting value of «Εμφάνιση στόχων στα μέλη» for a workout without goals of its own"
  }

  @wod_assistant_enabled_schema %Schema{
    type: :boolean,
    description:
      "ADR-180: whether coaches may use the WOD assistant; off, workouts are written in text sections with a timer each"
  }

  @workout_settings_schema %Schema{
    type: :object,
    description: "ADR-163: workout-authoring defaults",
    properties: %{
      wod_goals_visible_by_default: @wod_goals_visible_by_default_schema,
      wod_assistant_enabled: @wod_assistant_enabled_schema
    },
    required: [:wod_goals_visible_by_default, :wod_assistant_enabled]
  }

  @time_zone_schema %Schema{
    type: :object,
    description:
      "ADR-176: the gym's IANA time zone. `source` is confirmed (an admin set it), " <>
        "inferred (guessed from a staff device) or null (unknown; `timezone` is the default).",
    properties: %{
      timezone: %Schema{type: :string},
      source: %Schema{type: :string, enum: ["confirmed", "inferred"], nullable: true},
      confirmed: %Schema{type: :boolean}
    },
    required: [:timezone, :source, :confirmed]
  }

  @admin_settings_response_schema %Schema{
    type: :object,
    properties: %{
      time_zone: @time_zone_schema,
      gamification: @gamification_settings_schema,
      finance: @finance_settings_schema,
      scheduling: @scheduling_settings_schema,
      workouts: @workout_settings_schema,
      provider: @provider_settings_schema
    },
    required: [:gamification, :finance, :scheduling, :workouts, :provider]
  }

  @admin_settings_update_schema %Schema{
    type: :object,
    properties: %{
      gamification: %Schema{
        type: :object,
        properties: %{
          streak_shields: @streak_shields_schema,
          streak_shield_reset_day: @streak_shield_reset_day_schema,
          leaderboard_enabled: %Schema{type: :boolean}
        },
        required: []
      },
      finance: %Schema{
        type: :object,
        properties: %{
          payment_reminder_interval_days: %Schema{type: :integer, minimum: 1},
          subscription_expiry_reminder_days: @expiry_reminder_days_schema,
          subscription_grace_days: @grace_days_schema,
          document_mode: %Schema{type: :string, enum: ["invoice", "receipt"]},
          package_modules: %Schema{
            type: :array,
            uniqueItems: true,
            items: %Schema{type: :string, enum: Finance.package_module_keys()}
          }
        },
        required: []
      },
      scheduling: %Schema{
        type: :object,
        properties: %{
          default_capacity: %Schema{type: :integer, minimum: 1, maximum: 500},
          default_auto_approve: %Schema{type: :boolean},
          default_booking_timeout_minutes: %Schema{
            type: :integer,
            minimum: 1,
            maximum: 10_080
          },
          default_booking_window_days: %Schema{
            type: :integer,
            minimum: 1,
            maximum: 365,
            nullable: true,
            description: "How many days ahead members may book when their package sets no window"
          },
          default_cancellation_cutoff_hours: %Schema{
            type: :integer,
            minimum: 0,
            maximum: 168,
            nullable: true,
            description: "Withdrawals closer to the class than this use the visit"
          }
        },
        required: []
      },
      workouts: %Schema{
        type: :object,
        properties: %{
          wod_goals_visible_by_default: @wod_goals_visible_by_default_schema,
          wod_assistant_enabled: @wod_assistant_enabled_schema
        },
        required: []
      },
      provider: %Schema{
        type: :object,
        properties: %{kind: %Schema{type: :string, enum: ["gym", "coach"]}},
        required: []
      }
    },
    required: []
  }

  operation(:show,
    summary: "Fetch global admin settings",
    responses: [
      ok: {"Admin settings", "application/json", @admin_settings_response_schema}
    ]
  )

  operation(:update_time_zone,
    summary: "Confirm the gym's time zone, or report a guess from this device",
    description:
      "ADR-176: `confirmed` sets the zone. `inferred` is a guess (the device's zone, else an " <>
        "IP-derived zone from the edge) and never replaces a confirmed zone.",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            additionalProperties: false,
            properties: %{
              timezone: %Schema{type: :string, nullable: true, maxLength: 100},
              source: %Schema{type: :string, enum: ["confirmed", "inferred"]}
            },
            required: [:source]
          }
        }
      }
    },
    responses: [
      ok:
        {"Time zone", "application/json",
         %Schema{
           type: :object,
           properties: %{time_zone: @time_zone_schema},
           required: [:time_zone]
         }}
    ]
  )

  def update_time_zone(conn, _params) do
    context = conn.assigns.tenant_context
    body = conn.body_params
    source = body["source"]

    zone =
      if source == "inferred",
        do: Palee.Organizations.infer_timezone([body["timezone"] | ip_time_zones(conn)]),
        else: body["timezone"]

    with :ok <- apply_time_zone(context, zone, source) do
      json(conn, %{time_zone: Palee.Organizations.timezone_status(context.organization_id)})
    end
  end

  # Nothing to guess from (a UTC device behind a plain ingress) changes nothing.
  defp apply_time_zone(_context, nil, "inferred"), do: :ok

  defp apply_time_zone(context, zone, source) do
    with {:ok, _settings} <- Palee.Organizations.set_timezone(context, zone, source), do: :ok
  end

  # Zones some edges derive from the client IP (Cloudflare visitor location,
  # Vercel, CloudFront); absent behind a plain ingress.
  @ip_time_zone_headers ~w(cf-timezone x-vercel-ip-timezone cloudfront-viewer-time-zone)

  defp ip_time_zones(conn),
    do: Enum.flat_map(@ip_time_zone_headers, &Plug.Conn.get_req_header(conn, &1))

  def show(conn, _params) do
    with {:ok, payload} <- GetAdminSettings.call(conn.assigns.tenant_context) do
      json(conn, payload)
    end
  end

  operation(:update,
    summary: "Update global admin settings",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: @admin_settings_update_schema}}
    },
    responses: [
      ok: {"Admin settings", "application/json", @admin_settings_response_schema}
    ]
  )

  def update(conn, _params) do
    with {:ok, payload} <-
           UpdateAdminSettings.call(conn.assigns.tenant_context, conn.body_params) do
      json(conn, payload)
    end
  end
end
