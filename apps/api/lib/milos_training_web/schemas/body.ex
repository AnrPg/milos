defmodule MilosTrainingWeb.Schemas.Body do
  @moduledoc """
  OpenAPI schemas of Ημερολόγιο › Σώμα (ADR-158). Metric values are in the
  person's units (`units`); weight and body fat are left out when the
  person shows weight as a trend or hides it (`withheld_metrics` names the
  ones that exist under `trend`).
  """

  alias MilosTraining.Body
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @uuid %Schema{type: :string, format: :uuid}
  @datetime %Schema{type: :string, format: :"date-time"}

  def uuid, do: @uuid

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  defp metrics_schema(description) do
    %Schema{
      type: :object,
      description: description,
      properties: Map.new(Body.metric_keys(), &{String.to_atom(&1), %Schema{type: :number}}),
      additionalProperties: false
    }
  end

  def photo do
    %Schema{
      title: "BodyPhoto",
      type: :object,
      description:
        "A private body photo. Renditions are WebP (thumb ~320, feed ~1080, full ~2048 px); URLs are presigned and short-lived, present once status is ready.",
      required: [:id, :pose, :status],
      properties: %{
        id: @uuid,
        snapshot_id: @uuid,
        pose: %Schema{type: :string, enum: Body.poses()},
        status: %Schema{type: :string, enum: Body.photo_statuses()},
        width: %Schema{type: :integer, nullable: true},
        height: %Schema{type: :integer, nullable: true},
        placeholder: %Schema{type: :string, nullable: true},
        thumb_url: %Schema{type: :string, nullable: true},
        feed_url: %Schema{type: :string, nullable: true},
        full_url: %Schema{type: :string, nullable: true},
        taken_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "Set on the latest photo per pose (ghost outline)"
        }
      }
    }
  end

  def snapshot do
    %Schema{
      title: "BodySnapshot",
      type: :object,
      required: [
        :id,
        :taken_at,
        :units,
        :metrics,
        :withheld_metrics,
        :weight_display,
        :visibility,
        :photos,
        :photo_count
      ],
      properties: %{
        id: @uuid,
        taken_at: @datetime,
        taken_tz: %Schema{type: :string},
        units: %Schema{type: :string, enum: Body.unit_systems()},
        metrics:
          metrics_schema(
            "Values in `units`; weight and body fat only when weight shows as a number"
          ),
        withheld_metrics: %Schema{
          type: :array,
          items: %Schema{type: :string, enum: Body.metric_keys()},
          description: "Metrics recorded but not shown as numbers (weight shown as trend)"
        },
        weight_display: %Schema{type: :string, enum: Body.display_modes()},
        visibility: %Schema{type: :string, enum: Body.visibilities()},
        source: %Schema{
          type: :string,
          enum: Body.sources(),
          description: "manual, or garmin when a connected device sent it"
        },
        notes: %Schema{type: :string, nullable: true, description: "Never shown to a coach"},
        photos: %Schema{type: :array, items: photo()},
        photo_count: %Schema{type: :integer},
        inserted_at: @datetime,
        updated_at: @datetime
      }
    }
  end

  def snapshot_response do
    %Schema{
      title: "BodySnapshotResponse",
      type: :object,
      required: [:snapshot],
      properties: %{snapshot: snapshot()}
    }
  end

  def snapshot_page do
    %Schema{
      title: "BodySnapshotPage",
      type: :object,
      required: [:snapshots],
      properties: %{
        snapshots: %Schema{type: :array, items: snapshot()},
        next_cursor: %Schema{type: :string, nullable: true}
      }
    }
  end

  defp photo_entry do
    %Schema{
      type: :object,
      required: [:media_id, :pose],
      properties: %{media_id: @uuid, pose: %Schema{type: :string, enum: Body.poses()}}
    }
  end

  def photo_request, do: Map.put(photo_entry(), :title, "BodyPhotoRequest")

  def create_request do
    %Schema{
      title: "BodySnapshotCreateRequest",
      type: :object,
      description: "At least one metric or one photo.",
      properties: %{
        taken_at: %Schema{type: :string, format: :"date-time", description: "Defaults to now"},
        taken_tz: %Schema{type: :string},
        units: %Schema{
          type: :string,
          enum: Body.unit_systems(),
          description: "Units of `metrics`; defaults to your setting"
        },
        metrics: metrics_schema("Values in `units`"),
        notes: %Schema{type: :string, nullable: true, maxLength: 2000},
        visibility: %Schema{
          type: :string,
          enum: Body.visibilities(),
          description: "Defaults to the visibility you used last"
        },
        photos: %Schema{type: :array, items: photo_entry(), maxItems: Body.max_photos()}
      }
    }
  end

  def update_request do
    %Schema{
      title: "BodySnapshotUpdateRequest",
      type: :object,
      properties: %{
        taken_at: @datetime,
        taken_tz: %Schema{type: :string},
        units: %Schema{type: :string, enum: Body.unit_systems()},
        metrics: %Schema{
          type: :object,
          description: "Merged: a value sets a metric (in `units`), null removes it",
          properties:
            Map.new(
              Body.metric_keys(),
              &{String.to_atom(&1), %Schema{type: :number, nullable: true}}
            ),
          additionalProperties: false
        },
        notes: %Schema{type: :string, nullable: true, maxLength: 2000},
        visibility: %Schema{type: :string, enum: Body.visibilities()}
      }
    }
  end

  def series do
    %Schema{
      title: "BodySeries",
      type: :object,
      required: [:metric, :range, :units, :unit, :display, :points],
      properties: %{
        metric: %Schema{type: :string, enum: Body.metric_keys()},
        range: %Schema{type: :string, enum: Body.ranges()},
        units: %Schema{type: :string, enum: Body.unit_systems()},
        unit: %Schema{type: :string},
        display: %Schema{
          type: :string,
          enum: Body.display_modes(),
          description: "number: points with values; trend: only the trend word; hidden: neither"
        },
        trend: %Schema{type: :string, enum: Body.trend_words(), nullable: true},
        points: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:at, :value, :smoothed],
            properties: %{
              at: @datetime,
              value: %Schema{type: :number},
              smoothed: %Schema{type: :number}
            }
          }
        }
      }
    }
  end

  def compare do
    %Schema{
      title: "BodyComparison",
      type: :object,
      required: [:from, :to, :deltas, :units],
      properties: %{
        from: snapshot(),
        to: snapshot(),
        units: %Schema{type: :string, enum: Body.unit_systems()},
        deltas: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:metric, :direction],
            properties: %{
              metric: %Schema{type: :string, enum: Body.metric_keys()},
              delta: %Schema{
                type: :number,
                nullable: true,
                description: "In `units`; null when weight shows as a trend"
              },
              direction: %Schema{type: :string, enum: Body.trend_words(), nullable: true}
            }
          }
        }
      }
    }
  end

  defp settings_schema do
    %Schema{
      type: :object,
      required: [
        :units,
        :weight_display,
        :journal_sections,
        :measure_reminder_weeks,
        :default_visibility,
        :blur_photos,
        :compare_mode
      ],
      properties: %{
        units: %Schema{type: :string, enum: Body.unit_systems()},
        weight_display: %Schema{type: :string, enum: Body.display_modes()},
        journal_sections: sections_schema(),
        measure_reminder_weeks: %Schema{
          type: :integer,
          nullable: true,
          minimum: 1,
          maximum: Body.max_reminder_weeks()
        },
        default_visibility: %Schema{type: :string, enum: Body.visibilities()},
        blur_photos: %Schema{type: :boolean, description: "Photos show blurred until tapped"},
        compare_mode: %Schema{type: :string, enum: Body.compare_modes()}
      }
    }
  end

  defp sections_schema do
    %Schema{
      type: :object,
      properties:
        Map.new(Body.journal_sections(), &{String.to_atom(&1), %Schema{type: :boolean}}),
      additionalProperties: false
    }
  end

  def settings_response do
    %Schema{
      title: "BodySettingsResponse",
      type: :object,
      required: [:settings, :catalog, :photos, :ranges, :max_reminder_weeks],
      properties: %{
        settings: settings_schema(),
        catalog: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:key, :unit, :min, :max, :sensitive],
            properties: %{
              key: %Schema{type: :string, enum: Body.metric_keys()},
              unit: %Schema{type: :string},
              min: %Schema{type: :number},
              max: %Schema{type: :number},
              sensitive: %Schema{
                type: :boolean,
                description: "Follows weight_display (weight, body fat)"
              }
            }
          }
        },
        photos: %Schema{
          type: :object,
          required: [:content_types, :max_bytes, :max_photos, :poses],
          properties: %{
            content_types: %Schema{type: :array, items: %Schema{type: :string}},
            max_bytes: %Schema{type: :integer},
            max_photos: %Schema{type: :integer},
            poses: %Schema{type: :array, items: %Schema{type: :string}}
          }
        },
        ranges: %Schema{type: :array, items: %Schema{type: :string}},
        max_reminder_weeks: %Schema{type: :integer}
      }
    }
  end

  def settings_request do
    %Schema{
      title: "BodySettingsRequest",
      type: :object,
      description: "Partial: only the fields given change",
      properties: %{
        units: %Schema{type: :string, enum: Body.unit_systems()},
        weight_display: %Schema{type: :string, enum: Body.display_modes()},
        journal_sections: sections_schema(),
        measure_reminder_weeks: %Schema{
          type: :integer,
          nullable: true,
          minimum: 1,
          maximum: Body.max_reminder_weeks(),
          description: "null turns the reminder off"
        },
        default_visibility: %Schema{type: :string, enum: Body.visibilities()},
        blur_photos: %Schema{type: :boolean, description: "Photos show blurred until tapped"},
        compare_mode: %Schema{type: :string, enum: Body.compare_modes()}
      }
    }
  end

  def consents_response do
    %Schema{
      title: "HealthConsents",
      type: :object,
      required: [:consents],
      properties: %{
        consents: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:scope, :active],
            properties: %{
              scope: %Schema{type: :string, enum: Body.consent_scopes()},
              active: %Schema{type: :boolean},
              granted_at: %Schema{type: :string, format: :"date-time", nullable: true},
              withdrawn_at: %Schema{type: :string, format: :"date-time", nullable: true}
            }
          }
        }
      }
    }
  end

  def access_log_response do
    %Schema{
      title: "BodyAccessLog",
      type: :object,
      required: [:entries],
      properties: %{
        entries: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:id, :read_at, :subject, :snapshot_ids, :photos_shown, :reader],
            properties: %{
              id: @uuid,
              read_at: @datetime,
              subject: %Schema{type: :string, enum: ~w(list snapshot)},
              snapshot_ids: %Schema{type: :array, items: @uuid},
              photos_shown: %Schema{type: :boolean},
              reader: %Schema{
                type: :object,
                properties: %{id: @uuid, nickname: %Schema{type: :string, nullable: true}}
              },
              organization: %Schema{
                type: :object,
                properties: %{id: @uuid, name: %Schema{type: :string, nullable: true}}
              }
            }
          }
        }
      }
    }
  end

  def photo_response do
    %Schema{
      title: "BodyPhotoResponse",
      type: :object,
      required: [:photo],
      properties: %{photo: photo()}
    }
  end

  def photos_response do
    %Schema{
      title: "BodyPhotos",
      type: :object,
      required: [:photos],
      properties: %{photos: %Schema{type: :array, items: photo()}}
    }
  end

  def upload_request do
    %Schema{
      title: "BodyPhotoUploadRequest",
      type: :object,
      required: [:content_type, :byte_size],
      properties: %{
        content_type: %Schema{
          type: :string,
          enum: MilosTraining.Media.content_types("body_photo") |> Enum.sort(),
          description: "As picked; the server strips metadata (EXIF, GPS) and re-encodes."
        },
        byte_size: %Schema{type: :integer, minimum: 1}
      }
    }
  end

  def delete_all_response do
    %Schema{
      title: "BodyPhotosDeleted",
      type: :object,
      required: [:deleted_photos, :deleted_snapshots],
      properties: %{
        deleted_photos: %Schema{type: :integer},
        deleted_snapshots: %Schema{
          type: :integer,
          description: "Snapshots that held only photos and so were left empty"
        }
      }
    }
  end

  def share_request do
    %Schema{
      title: "BodyShareRequest",
      type: :object,
      description:
        "A before/after of one pose as a post. Needs confirm: true (a separate confirmation) and the body-photo consent; the photos are copied, no numbers are added.",
      required: [:from_snapshot_id, :to_snapshot_id, :pose, :audience, :confirm],
      properties: %{
        from_snapshot_id: @uuid,
        to_snapshot_id: @uuid,
        pose: %Schema{type: :string, enum: Body.poses()},
        text: %Schema{type: :string, maxLength: 5000, nullable: true},
        audience: %Schema{type: :string, enum: ~w(followers public club_channel)},
        channel_id: %Schema{type: :string, format: :uuid, description: "For club_channel"},
        confirm: %Schema{type: :boolean, description: "Must be true"},
        client_operation_id: %Schema{type: :string, maxLength: 120}
      }
    }
  end
end
