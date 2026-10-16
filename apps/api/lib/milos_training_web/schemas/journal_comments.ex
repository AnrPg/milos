defmodule MilosTrainingWeb.Schemas.JournalComments do
  @moduledoc """
  Σχόλια (ADR-140 §1): text a member writes on their own entry. The change,
  comment and input shapes are named components so every entry schema that
  embeds comments refers to them instead of repeating them.
  """

  alias OpenApiSpex.Schema

  defmodule Change do
    @moduledoc false
    require OpenApiSpex

    @value %Schema{
      oneOf: [%Schema{type: :string}, %Schema{type: :number}, %Schema{type: :boolean}],
      nullable: true
    }

    OpenApiSpex.schema(
      %{
        title: "JournalCommentChange",
        description:
          "A structured change to the prescription (modification-patch shape); one per row " <>
            "and field, upserted by patch_id.",
        type: :object,
        required: [:patch_id, :section_id, :field],
        properties: %{
          patch_id: %Schema{type: :string},
          type: %Schema{
            type: :string,
            enum: ~w(skipped weight_changed reps_changed time_changed sets_changed
                   exercise_substituted distance_changed calories_changed field_changed other),
            nullable: true
          },
          field: %Schema{type: :string},
          section_id: %Schema{type: :string},
          section_name: %Schema{type: :string, nullable: true},
          segment_key: %Schema{type: :string, nullable: true},
          exercise_id: %Schema{type: :string, nullable: true},
          exercise_name: %Schema{type: :string, nullable: true},
          set_index: %Schema{type: :integer, minimum: 1, nullable: true},
          round_index: %Schema{type: :integer, minimum: 1, nullable: true},
          interval_index: %Schema{type: :integer, minimum: 1, nullable: true},
          row_index: %Schema{type: :integer, minimum: 1, nullable: true},
          canonical_value: @value,
          actual_value: @value,
          unit: %Schema{type: :string, nullable: true},
          note: %Schema{
            type: :string,
            nullable: true,
            description: "Accepted as the comment's text when no body is given; never stored."
          }
        }
      },
      struct?: false
    )
  end

  defmodule Fields do
    @moduledoc false
    alias MilosTrainingWeb.Schemas.JournalComments.Change
    alias OpenApiSpex.Schema

    @anchor_properties %{
      section_id: %Schema{type: :string, maxLength: 200, nullable: true},
      exercise_id: %Schema{
        type: :string,
        maxLength: 200,
        nullable: true,
        description: "Exercise id, or `row:<n>` for a training-log row."
      },
      selected_text: %Schema{type: :string, maxLength: 1000, nullable: true},
      selection_start: %Schema{type: :integer, minimum: 0, nullable: true},
      selection_end: %Schema{type: :integer, minimum: 1, nullable: true},
      tags: %Schema{type: :array, items: %Schema{type: :string}, maxItems: 20},
      body: %Schema{type: :string, maxLength: 4000, nullable: true},
      change: %Schema{allOf: [Change], nullable: true},
      written_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "When it was written on the device (never later than now)."
      }
    }

    @entry_kind %Schema{type: :string, enum: ["execution", "training_log", "pr"]}

    def anchor_properties, do: @anchor_properties
    def entry_kind, do: @entry_kind
  end

  defmodule Comment do
    @moduledoc false
    require OpenApiSpex

    alias MilosTrainingWeb.Schemas.JournalComments.Fields

    OpenApiSpex.schema(
      %{
        title: "JournalComment",
        type: :object,
        required: [:id, :entry_kind, :entry_id, :tags, :written_at],
        properties:
          Map.merge(Fields.anchor_properties(), %{
            id: %Schema{type: :string, format: :uuid},
            user_id: %Schema{type: :string, format: :uuid},
            organization_id: %Schema{type: :string, format: :uuid, nullable: true},
            entry_kind: Fields.entry_kind(),
            entry_id: %Schema{type: :string, format: :uuid},
            tags: %Schema{type: :array, items: %Schema{type: :string}},
            written_at: %Schema{type: :string, format: :"date-time"},
            updated_at: %Schema{type: :string, format: :"date-time"}
          })
      },
      struct?: false
    )
  end

  defmodule Input do
    @moduledoc false
    require OpenApiSpex

    alias MilosTrainingWeb.Schemas.JournalComments.Fields

    OpenApiSpex.schema(
      %{
        title: "JournalCommentInput",
        description: "A comment written together with its entry; the entry is implied.",
        type: :object,
        properties:
          Map.put(Fields.anchor_properties(), :id, %Schema{type: :string, format: :uuid})
      },
      struct?: false
    )
  end

  defmodule Save do
    @moduledoc false
    require OpenApiSpex

    alias MilosTrainingWeb.Schemas.JournalComments.Fields

    OpenApiSpex.schema(
      %{
        title: "JournalCommentSave",
        type: :object,
        required: [:entry_kind, :entry_id],
        properties:
          Map.merge(Fields.anchor_properties(), %{
            entry_kind: Fields.entry_kind(),
            entry_id: %Schema{type: :string, format: :uuid}
          })
      },
      struct?: false
    )
  end

  def comments, do: %Schema{type: :array, items: Comment}
  def inline_inputs, do: %Schema{type: :array, items: Input, maxItems: 200}

  def save_request, do: Save

  def batch_request do
    %Schema{
      title: "JournalCommentBatch",
      type: :object,
      required: [:comments],
      properties: %{
        comments: %Schema{
          type: :array,
          maxItems: 200,
          items: %Schema{
            allOf: [
              Save,
              %Schema{
                type: :object,
                required: [:id],
                properties: %{id: %Schema{type: :string, format: :uuid}}
              }
            ]
          }
        }
      }
    }
  end

  def comment_response do
    %Schema{
      title: "JournalCommentResponse",
      type: :object,
      required: [:comment],
      properties: %{comment: Comment}
    }
  end

  def comments_response do
    %Schema{
      title: "JournalCommentsResponse",
      type: :object,
      required: [:comments],
      properties: %{comments: comments()}
    }
  end
end
