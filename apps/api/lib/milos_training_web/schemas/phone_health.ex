defmodule MilosTrainingWeb.Schemas.PhoneHealth do
  @moduledoc """
  OpenAPI schemas of Apple Health and Health Connect through the store apps
  (ADR-172), and of the device-data export.

  Instants in a batch are plain ISO 8601 strings with the wearer's offset
  (`2026-10-20T07:30:00+03:00`), not `date-time`, so the offset reaches the
  server: it gives the local day and the zone, as with Garmin.
  """

  alias MilosTrainingWeb.Schemas.Devices
  alias OpenApiSpex.Schema

  @maybe_datetime %Schema{type: :string, format: :"date-time", nullable: true}
  @datetime %Schema{type: :string, format: :"date-time"}
  @provider %Schema{type: :string, enum: ~w(apple_health health_connect)}
  @instant %Schema{
    type: :string,
    description: "ISO 8601 with the offset at the time, e.g. 2026-10-20T07:30:00+03:00"
  }
  @day %Schema{type: :string, description: "The wearer's local day, YYYY-MM-DD"}
  @maybe_number %Schema{type: :number, nullable: true}

  def provider, do: @provider

  def sync_prefs do
    %Schema{
      title: "PhoneHealthSyncPrefs",
      type: :object,
      description:
        "What the phone brings in: workouts (Ημερολόγιο), sleep (Ευεξία), weight (Σώμα), resting heart rate and steps (Πρόοδος)",
      properties: %{
        activities: %Schema{type: :boolean},
        sleep: %Schema{type: :boolean},
        weight: %Schema{type: :boolean},
        resting_hr: %Schema{type: :boolean},
        steps: %Schema{type: :boolean}
      }
    }
  end

  def connection do
    %Schema{
      title: "PhoneHealthConnection",
      type: :object,
      nullable: true,
      properties: %{
        status: %Schema{type: :string, enum: ["active"]},
        connected_at: @maybe_datetime,
        last_synced_at: @maybe_datetime,
        sync_prefs: sync_prefs(),
        read_from: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description:
            "Where the app starts reading at its next sync: 30 days back at first, then two days before the last sync"
        }
      },
      required: [:status, :sync_prefs]
    }
  end

  def row do
    %Schema{
      title: "PhoneHealthRow",
      type: :object,
      description:
        "Apple Health or Health Connect on Συνδεδεμένες συσκευές: `native_only` until the store app connects it",
      properties: %{
        provider: @provider,
        status: %Schema{type: :string, enum: ~w(native_only connected)},
        sync_prefs: sync_prefs(),
        history_days: %Schema{type: :integer, description: "Days read back at the first sync"},
        connection: connection()
      },
      required: [:provider, :status, :sync_prefs]
    }
  end

  def row_response do
    %Schema{
      title: "PhoneHealthRowResponse",
      type: :object,
      properties: %{row: row()},
      required: [:row]
    }
  end

  def connect_request do
    %Schema{
      title: "PhoneHealthConnectRequest",
      type: :object,
      properties: %{
        sync_prefs: sync_prefs(),
        health_data_consent: %Schema{
          type: :boolean,
          description:
            "Grants the health-data consent in the same step when it is missing; needed when sleep, weight, resting heart rate or steps sync"
        }
      }
    }
  end

  def update_request do
    %Schema{
      title: "PhoneHealthUpdateRequest",
      type: :object,
      properties: %{
        sync_prefs: sync_prefs(),
        health_data_consent: %Schema{type: :boolean}
      },
      required: [:sync_prefs]
    }
  end

  def ingest_request do
    activity = %Schema{
      title: "PhoneHealthActivity",
      type: :object,
      properties: %{
        id: %Schema{type: :string, description: "The phone's id of the workout"},
        type: %Schema{
          type: :string,
          description: "The workout type in upper snake case (RUNNING, STRENGTH_TRAINING, …)"
        },
        title: %Schema{type: :string, nullable: true},
        start: @instant,
        end: @instant,
        distance_m: @maybe_number,
        avg_hr: @maybe_number,
        max_hr: @maybe_number,
        source_app: %Schema{
          type: :string,
          nullable: true,
          description: "The app that recorded it"
        }
      },
      required: [:id, :start, :end]
    }

    sleep = %Schema{
      title: "PhoneHealthSleep",
      type: :object,
      description: "The main sleep of one night (the app joins the phone's segments)",
      properties: %{id: %Schema{type: :string}, start: @instant, end: @instant},
      required: [:id, :start, :end]
    }

    weight = %Schema{
      title: "PhoneHealthWeight",
      type: :object,
      properties: %{id: %Schema{type: :string}, at: @instant, kg: %Schema{type: :number}},
      required: [:id, :at, :kg]
    }

    daily = %Schema{
      title: "PhoneHealthDaily",
      type: :object,
      properties: %{date: @day, resting_hr: @maybe_number, steps: @maybe_number},
      required: [:date]
    }

    %Schema{
      title: "PhoneHealthIngestRequest",
      type: :object,
      description: "What the app read from the phone; at most 500 records per list",
      properties: %{
        activities: %Schema{type: :array, items: activity},
        sleeps: %Schema{type: :array, items: sleep},
        weights: %Schema{type: :array, items: weight},
        dailies: %Schema{type: :array, items: daily}
      }
    }
  end

  def ingest_response do
    %Schema{
      title: "PhoneHealthIngestResponse",
      type: :object,
      properties: %{
        counts: %Schema{
          type: :object,
          description:
            "Records by outcome: imported, merged, duplicate, ignored, skipped, invalid, failed",
          additionalProperties: %Schema{type: :integer}
        },
        row: row()
      },
      required: [:counts, :row]
    }
  end

  def export_response do
    %Schema{
      title: "DeviceDataExport",
      type: :object,
      description:
        "Everything the connected devices brought in, except nights and weigh-ins (in the Ευεξία and Σώμα exports)",
      properties: %{
        exported_at: @datetime,
        connections: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              provider: %Schema{type: :string},
              status: %Schema{type: :string},
              connected_at: @maybe_datetime,
              last_synced_at: @maybe_datetime,
              revoked_at: @maybe_datetime,
              sync_prefs: %Schema{type: :object, additionalProperties: %Schema{type: :boolean}}
            },
            required: [:provider, :status]
          }
        },
        activities: %Schema{type: :array, items: Devices.activity()},
        daily_stats: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              on: %Schema{type: :string, format: :date},
              source: %Schema{type: :string},
              resting_heart_rate: %Schema{type: :integer, nullable: true},
              steps: %Schema{type: :integer, nullable: true}
            },
            required: [:on, :source]
          }
        },
        imports: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              provider: %Schema{type: :string},
              kind: %Schema{type: :string},
              status: %Schema{type: :string},
              reason: %Schema{type: :string, nullable: true},
              target_type: %Schema{type: :string, nullable: true},
              received_at: @datetime
            },
            required: [:provider, :kind, :status, :received_at]
          }
        }
      },
      required: [:exported_at, :connections, :activities, :daily_stats, :imports]
    }
  end
end
