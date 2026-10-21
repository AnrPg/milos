defmodule MilosTrainingWeb.Schemas.JournalFeed do
  @moduledoc """
  OpenAPI schemas of the journal feed, ladder moves and Σημείωση notes
  (ADR-139). A feed item's `entry` is the entry as its own endpoint returns
  it (execution, training-log entry, PR, injury, review, note, check-in or,
  ADR-158, a body snapshot, only ever in your own feed), chosen by `kind`.
  ADR-159: `wellness` is a day (date, summary, entries, photos) and
  `craving` one Λιγούρα; single wellness entries move as `wellness_entry`.
  """

  alias OpenApiSpex.Schema

  @kinds ~w(execution training_log pr injury review note check_in body wellness craving
            device_activity)
  @movable_kinds @kinds ++ ~w(wellness_entry)
  @rungs ~w(private coach_can_view coach_reply_requested rated posted)
  @topics ~w(technique thought mood goal)

  def kinds, do: @kinds

  @doc "Kinds whose entries move on the ladder: feed kinds plus single wellness entries."
  def movable_kinds, do: @movable_kinds

  defmodule Item do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(
      %{
        title: "JournalFeedItem",
        type: :object,
        required: [
          :kind,
          :id,
          :occurred_at,
          :journal_visibility,
          :choosable_visibilities,
          :entry
        ],
        properties: %{
          kind: %Schema{
            type: :string,
            enum: ~w(execution training_log pr injury review note check_in body wellness craving
                     device_activity)
          },
          id: %Schema{type: :string, format: :uuid},
          occurred_at: %Schema{type: :string, format: :"date-time"},
          occurred_tz: %Schema{type: :string, nullable: true},
          occurred_on: %Schema{
            type: :string,
            format: :date,
            nullable: true,
            description: "Set for entries dated by day only (PRs)."
          },
          organization_id: %Schema{type: :string, format: :uuid, nullable: true},
          journal_visibility: %Schema{
            type: :string,
            enum: ~w(private coach_can_view coach_reply_requested rated posted)
          },
          choosable_visibilities: %Schema{
            type: :array,
            items: %Schema{
              type: :string,
              enum: ~w(private coach_can_view coach_reply_requested)
            }
          },
          entry: %Schema{
            description:
              "The entry, chosen by `kind`. ADR-161: a `device_activity` entry is a DeviceActivity; an execution or training-log entry a watch matched carries its numbers as `device` (DeviceMetrics).",
            anyOf: [
              MilosTrainingWeb.Schemas.Devices.activity(),
              %Schema{
                title: "JournalFeedEntry",
                type: :object,
                additionalProperties: true,
                properties: %{device: MilosTrainingWeb.Schemas.Devices.merged_metrics()}
              }
            ]
          }
        }
      },
      struct?: false
    )
  end

  defmodule Note do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(
      %{
        title: "JournalNote",
        type: :object,
        required: [:id, :topic, :body, :written_at, :journal_visibility, :lock_version],
        properties: %{
          id: %Schema{type: :string, format: :uuid},
          user_id: %Schema{type: :string, format: :uuid},
          organization_id: %Schema{type: :string, format: :uuid, nullable: true},
          topic: %Schema{type: :string, enum: ~w(technique thought mood goal)},
          body: %Schema{type: :string},
          linked_kind: %Schema{
            type: :string,
            enum: ~w(execution training_log workout),
            nullable: true
          },
          linked_id: %Schema{type: :string, format: :uuid, nullable: true},
          written_at: %Schema{type: :string, format: :"date-time"},
          written_tz: %Schema{type: :string},
          journal_visibility: %Schema{type: :string},
          lock_version: %Schema{type: :integer}
        }
      },
      struct?: false
    )
  end

  def page do
    %Schema{
      title: "JournalFeedPage",
      type: :object,
      required: [:items],
      properties: %{
        items: %Schema{type: :array, items: Item},
        next_cursor: %Schema{type: :string, nullable: true}
      }
    }
  end

  def visibility_request do
    %Schema{
      title: "JournalVisibilityRequest",
      type: :object,
      required: [:visibility],
      properties: %{
        visibility: %Schema{type: :string, enum: ~w(private coach_can_view coach_reply_requested)},
        question: %Schema{
          type: :string,
          maxLength: 5000,
          description: "Required for coach_reply_requested: sent to the coach as a message."
        },
        coach_user_id: %Schema{
          type: :string,
          format: :uuid,
          description: "Which coach answers, when the member has several."
        }
      },
      additionalProperties: false
    }
  end

  def visibility_response do
    %Schema{
      title: "JournalVisibilityResponse",
      type: :object,
      required: [:kind, :id, :journal_visibility, :choosable_visibilities],
      properties: %{
        kind: %Schema{type: :string, enum: @kinds},
        id: %Schema{type: :string, format: :uuid},
        journal_visibility: %Schema{type: :string, enum: @rungs},
        choosable_visibilities: %Schema{type: :array, items: %Schema{type: :string}},
        reply_request: %Schema{
          type: :object,
          nullable: true,
          description: "The message sent to the coach, for coach_reply_requested.",
          properties: %{
            id: %Schema{type: :string, format: :uuid},
            thread_id: %Schema{type: :string, format: :uuid}
          }
        }
      }
    }
  end

  @note_fields %{
    topic: %Schema{type: :string, enum: @topics},
    body: %Schema{type: :string, minLength: 1, maxLength: 4000},
    linked_kind: %Schema{type: :string, enum: ~w(execution training_log workout), nullable: true},
    linked_id: %Schema{type: :string, format: :uuid, nullable: true},
    written_at: %Schema{type: :string, format: :"date-time", nullable: true},
    written_tz: %Schema{type: :string, nullable: true}
  }

  def note_create_request do
    %Schema{
      title: "JournalNoteCreateRequest",
      type: :object,
      required: [:topic, :body],
      properties:
        Map.put(@note_fields, :organization_slug, %Schema{
          type: :string,
          nullable: true,
          description: "The gym the note is written in; personal when absent."
        }),
      additionalProperties: false
    }
  end

  def note_update_request do
    %Schema{
      title: "JournalNoteUpdateRequest",
      type: :object,
      properties: Map.put(@note_fields, :lock_version, %Schema{type: :integer, minimum: 1}),
      additionalProperties: false
    }
  end

  def note_response do
    %Schema{
      title: "JournalNoteResponse",
      type: :object,
      required: [:note],
      properties: %{note: Note}
    }
  end
end
