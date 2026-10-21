defmodule PaleeWeb.Schemas.Devices do
  @moduledoc "OpenAPI schemas of connected health devices, Garmin first (ADR-161, P2-M13)."

  alias PaleeWeb.Schemas.Community
  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @maybe_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @datetime %Schema{type: :string, format: :"date-time"}
  @maybe_datetime %Schema{type: :string, format: :"date-time", nullable: true}
  @maybe_string %Schema{type: :string, nullable: true}
  @maybe_integer %Schema{type: :integer, nullable: true}
  @maybe_number %Schema{type: :number, nullable: true}

  def body(schema), do: Community.body(schema)
  def error, do: %Schema{type: :object, additionalProperties: true}

  def sync_prefs do
    %Schema{
      title: "DeviceSyncPrefs",
      type: :object,
      description:
        "What is brought in: workouts (Ημερολόγιο), sleep (Ευεξία), weight (Σώμα), resting heart rate (Πρόοδος)",
      properties: %{
        activities: %Schema{type: :boolean},
        sleep: %Schema{type: :boolean},
        weight: %Schema{type: :boolean},
        resting_hr: %Schema{type: :boolean},
        steps: %Schema{type: :boolean, description: "Phones only (ADR-172)"}
      }
    }
  end

  def garmin_connection do
    %Schema{
      title: "GarminConnection",
      type: :object,
      nullable: true,
      properties: %{
        status: %Schema{type: :string, enum: ~w(active error)},
        connected_at: @maybe_datetime,
        last_synced_at: @maybe_datetime,
        sync_prefs: sync_prefs(),
        backfill_days: %Schema{type: :integer, enum: [0, 30, 90]},
        backfill_status: %Schema{type: :string, enum: ~w(none running done failed)},
        backfill_progress: %Schema{
          type: :integer,
          nullable: true,
          minimum: 0,
          maximum: 100,
          description: "«Εισαγωγή… 40%» while the history import runs"
        },
        last_error: @maybe_string,
        needs_reconnect: %Schema{type: :boolean}
      },
      required: [:status, :sync_prefs, :backfill_days, :backfill_status, :needs_reconnect]
    }
  end

  @doc "The Garmin row (also an item of `integrations` in the devices payload)."
  def garmin_row do
    %Schema{
      title: "GarminDeviceRow",
      type: :object,
      properties: %{
        provider: %Schema{type: :string, enum: ["garmin"]},
        status: %Schema{
          type: :string,
          enum: ~w(unavailable disconnected connected error),
          description: "`unavailable` is «Σύντομα»: this server has no Garmin credentials"
        },
        configured: %Schema{type: :boolean},
        capability: %Schema{type: :string, enum: ~w(available not_configured)},
        sync_prefs: sync_prefs(),
        backfill_day_options: %Schema{type: :array, items: %Schema{type: :integer}},
        connection: garmin_connection()
      },
      required: [:provider, :status, :configured, :capability, :sync_prefs]
    }
  end

  def garmin_row_response do
    %Schema{
      title: "GarminDeviceRowResponse",
      type: :object,
      properties: %{garmin: garmin_row()},
      required: [:garmin]
    }
  end

  def connect_request do
    %Schema{
      title: "GarminConnectRequest",
      type: :object,
      properties: %{
        sync_prefs: sync_prefs(),
        backfill_days: %Schema{
          type: :integer,
          enum: [0, 30, 90],
          description: "History to import; 30 when left out"
        },
        health_data_consent: %Schema{
          type: :boolean,
          description:
            "Grants the health-data consent in the same step when it is missing; needed only when sleep, weight or resting heart rate sync"
        }
      }
    }
  end

  def connect_response do
    %Schema{
      title: "GarminConnectResponse",
      type: :object,
      properties: %{
        authorize_url: %Schema{type: :string, description: "Open it to sign in at Garmin"},
        expires_at: @datetime
      },
      required: [:authorize_url, :expires_at]
    }
  end

  def update_request do
    %Schema{
      title: "GarminUpdateRequest",
      type: :object,
      properties: %{
        sync_prefs: sync_prefs(),
        health_data_consent: %Schema{
          type: :boolean,
          description:
            "Grants the health-data consent when this change turns on sleep, weight or resting heart rate"
        }
      },
      required: [:sync_prefs]
    }
  end

  def disconnect_response do
    %Schema{
      title: "GarminDisconnectResponse",
      type: :object,
      properties: %{
        status: %Schema{type: :string, enum: ["revoked"]},
        deleted: %Schema{
          type: :object,
          nullable: true,
          description: "What was deleted, when delete_data=true",
          properties: %{
            activities: %Schema{type: :integer},
            sleep: %Schema{type: :integer},
            weight: %Schema{type: :integer},
            daily_stats: %Schema{type: :integer},
            imports: %Schema{type: :integer}
          }
        }
      },
      required: [:status]
    }
  end

  def candidate do
    %Schema{
      title: "DeviceActivityCandidate",
      type: :object,
      properties: %{
        kind: %Schema{type: :string, enum: ~w(training_log execution class)},
        id: @uuid,
        organization_id: @maybe_uuid,
        title: @maybe_string,
        starts_at: @datetime,
        ends_at: @datetime
      },
      required: [:kind, :id, :starts_at, :ends_at]
    }
  end

  def activity do
    %Schema{
      title: "DeviceActivity",
      type: :object,
      description:
        "A workout from a watch: its own journal entry, or waiting for confirmation (pending)",
      properties: %{
        id: @uuid,
        organization_id: @maybe_uuid,
        provider: %Schema{type: :string, enum: ~w(garmin apple_health health_connect)},
        state: %Schema{type: :string, enum: ~w(own merged pending)},
        sport: %Schema{
          type: :string,
          enum: Palee.Devices.Domain.Sport.sports(),
          description: "Localized by the client; the raw type is `activity_type`"
        },
        activity_type: @maybe_string,
        title: %Schema{type: :string},
        started_at: @datetime,
        started_tz: %Schema{type: :string},
        duration_seconds: %Schema{type: :integer},
        distance_meters: @maybe_number,
        avg_heart_rate: @maybe_integer,
        max_heart_rate: @maybe_integer,
        calories: @maybe_integer,
        class_id: @maybe_uuid,
        journal_visibility: %Schema{type: :string, enum: ~w(private coach_can_view)},
        candidates: %Schema{type: :array, items: candidate()}
      },
      required: [:id, :provider, :state, :sport, :title, :started_at, :duration_seconds]
    }
  end

  @doc "The watch's numbers on an execution or training-log entry («από Garmin»)."
  def merged_metrics do
    %Schema{
      title: "DeviceMetrics",
      type: :object,
      nullable: true,
      properties: %{
        id: @uuid,
        provider: %Schema{type: :string, enum: ~w(garmin apple_health health_connect)},
        sport: %Schema{type: :string, enum: Palee.Devices.Domain.Sport.sports()},
        started_at: @datetime,
        duration_seconds: %Schema{type: :integer},
        distance_meters: @maybe_number,
        avg_heart_rate: @maybe_integer,
        max_heart_rate: @maybe_integer,
        calories: @maybe_integer
      },
      required: [:id, :provider, :sport, :started_at, :duration_seconds]
    }
  end

  def pending_response do
    %Schema{
      title: "DevicePendingImports",
      type: :object,
      properties: %{
        imports: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              id: @uuid,
              kind: %Schema{type: :string, enum: ["activity"]},
              received_at: @datetime,
              activity: activity()
            },
            required: [:id, :kind, :received_at, :activity]
          }
        }
      },
      required: [:imports]
    }
  end

  def confirm_request do
    %Schema{
      title: "DeviceImportConfirmRequest",
      type: :object,
      description: "Either one of the activity's candidates, or keep it as its own entry",
      properties: %{
        target_id: @uuid,
        as_new: %Schema{type: :boolean}
      }
    }
  end

  def activity_response do
    %Schema{
      title: "DeviceActivityResponse",
      type: :object,
      properties: %{activity: activity()},
      required: [:activity]
    }
  end

  def summary_response do
    %Schema{
      title: "DeviceSummary",
      type: :object,
      description: "The journal's device card; show it only when `visible`",
      properties: %{
        provider: %Schema{
          type: :string,
          description: "The device whose news the card shows (Garmin first when connected)"
        },
        providers: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Every connected device"
        },
        connected: %Schema{type: :boolean},
        status: @maybe_string,
        visible: %Schema{type: :boolean},
        new_total: %Schema{type: :integer},
        new_counts: %Schema{
          type: :object,
          properties: %{
            activity: %Schema{type: :integer},
            sleep: %Schema{type: :integer},
            weight: %Schema{type: :integer}
          }
        },
        needs_confirmation: %Schema{type: :integer},
        latest_at: @maybe_datetime,
        seen_at: @maybe_datetime,
        backfill_progress: @maybe_integer
      },
      required: [:provider, :connected, :visible, :new_total, :new_counts, :needs_confirmation]
    }
  end

  def daily_stats_response do
    point = %Schema{
      title: "DailyStatPoint",
      type: :object,
      properties: %{
        on: %Schema{type: :string, format: :date},
        value: %Schema{
          type: :integer,
          description: "Beats per minute for resting_hr, a count for steps"
        },
        source: %Schema{
          type: :string,
          enum: ~w(garmin apple_health health_connect),
          description: "The device that sent it («από Garmin»)"
        }
      },
      required: [:on, :value, :source]
    }

    %Schema{
      title: "DailyStats",
      type: :object,
      description:
        "Πρόοδος: one point per day and source, oldest first; `latest` and `average` are null without data",
      properties: %{
        metric: %Schema{type: :string, enum: ["resting_hr", "steps"]},
        range: %Schema{type: :string, enum: ~w(1m 3m 1y)},
        from: %Schema{type: :string, format: :date},
        to: %Schema{type: :string, format: :date},
        points: %Schema{type: :array, items: point},
        latest: %{point | nullable: true, title: "DailyStatLatest"},
        average: @maybe_integer,
        sources: %Schema{type: :array, items: %Schema{type: :string}}
      },
      required: [:metric, :range, :from, :to, :points, :latest, :average, :sources]
    }
  end

  def push_response do
    %Schema{
      title: "GarminPushResponse",
      type: :object,
      properties: %{
        queued: %Schema{type: :integer},
        deregistered: %Schema{type: :integer},
        ignored: %Schema{type: :integer}
      }
    }
  end
end
