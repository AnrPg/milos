defmodule PaleeWeb.Schemas.Imports do
  @moduledoc "OpenAPI schemas of CSV imports (ADR-254)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}
  alias Palee.Imports.Domain.{DateParser, Encoding, Fields, ImportPolicy, Presets}

  @uuid %Schema{type: :string, format: :uuid}
  @time %Schema{type: :string, format: :"date-time", nullable: true}
  @counts %Schema{type: :object, additionalProperties: %Schema{type: :integer}}

  def uuid, do: @uuid

  def field_enum, do: %Schema{type: :string, enum: Fields.keys()}
  def source_enum, do: %Schema{type: :string, enum: Presets.keys()}
  def status_enum, do: %Schema{type: :string, enum: ImportPolicy.statuses()}
  def row_status_enum, do: %Schema{type: :string, enum: ImportPolicy.row_statuses()}
  def outcome_enum, do: %Schema{type: :string, enum: ImportPolicy.outcomes()}
  def date_order_enum, do: %Schema{type: :string, enum: DateParser.orders()}
  def role_enum, do: %Schema{type: :string, enum: ImportPolicy.roles()}
  def warning_enum, do: %Schema{type: :string, enum: ImportPolicy.warnings()}
  def error_enum, do: %Schema{type: :string, enum: ImportPolicy.errors()}

  def json_body(schema),
    do: %RequestBody{required: false, content: %{"application/json" => %MediaType{schema: schema}}}

  def upload_body do
    %RequestBody{
      required: true,
      content: %{
        "multipart/form-data" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              file: %Schema{type: :string, format: :binary, description: "The CSV file (≤ 5 MB)"},
              source: %Schema{source_enum() | nullable: true}
            },
            required: [:file]
          }
        }
      }
    }
  end

  def catalog do
    %Schema{
      type: :object,
      properties: %{
        fields: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              key: field_enum(),
              type: %Schema{type: :string, enum: Fields.types()},
              group: %Schema{type: :string, enum: Fields.groups()}
            },
            required: [:group, :key, :type]
          }
        },
        presets: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{key: source_enum(), name: %Schema{type: :string}, date_order: date_order_enum()},
            required: [:date_order, :key, :name]
          }
        },
        date_orders: %Schema{type: :array, items: date_order_enum()},
        roles: %Schema{type: :array, items: role_enum()},
        limits: %Schema{
          type: :object,
          properties: %{
            max_bytes: %Schema{type: :integer},
            max_rows: %Schema{type: :integer},
            max_invitations: %Schema{type: :integer},
            undo_days: %Schema{type: :integer}
          },
          required: [:max_bytes, :max_invitations, :max_rows, :undo_days]
        },
        statuses: %Schema{type: :array, items: status_enum()},
        row_statuses: %Schema{type: :array, items: row_status_enum()},
        outcomes: %Schema{type: :array, items: outcome_enum()},
        warnings: %Schema{type: :array, items: warning_enum()},
        errors: %Schema{type: :array, items: error_enum()},
        encodings: %Schema{type: :array, items: %Schema{type: :string, enum: Encoding.encodings()}}
      },
      required: [
        :date_orders,
        :encodings,
        :errors,
        :fields,
        :limits,
        :outcomes,
        :presets,
        :roles,
        :row_statuses,
        :statuses,
        :warnings
      ]
    }
  end

  def mapping_entry do
    %Schema{
      type: :object,
      properties: %{
        column: %Schema{type: :integer, minimum: 0},
        field: %Schema{field_enum() | nullable: true}
      },
      required: [:column, :field]
    }
  end

  def import do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        status: status_enum(),
        source: source_enum(),
        filename: %Schema{type: :string},
        byte_size: %Schema{type: :integer},
        encoding: %Schema{type: :string, enum: Encoding.encodings()},
        delimiter: %Schema{type: :string},
        header: %Schema{type: :array, items: %Schema{type: :string}},
        row_count: %Schema{type: :integer},
        mapping: %Schema{type: :array, items: mapping_entry()},
        date_order: date_order_enum(),
        default_role: role_enum(),
        file_warnings: %Schema{type: :array, items: %Schema{type: :string}},
        preview: %Schema{
          type: :object,
          nullable: true,
          properties: %{
            rows: %Schema{type: :integer},
            outcomes: @counts,
            actions: @counts,
            warnings: @counts
          }
        },
        previewed_at: @time,
        summary: %Schema{type: :object, nullable: true, additionalProperties: true},
        counts: %Schema{
          type: :object,
          nullable: true,
          properties: %{statuses: @counts, outcomes: @counts},
          required: [:outcomes, :statuses]
        },
        queued_at: @time,
        started_at: @time,
        finished_at: @time,
        undo_until: @time,
        undone_at: @time,
        last_error: %Schema{type: :string, nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [
        :byte_size,
        :date_order,
        :default_role,
        :delimiter,
        :encoding,
        :filename,
        :header,
        :id,
        :mapping,
        :row_count,
        :source,
        :status
      ]
    }
  end

  def one(schema),
    do: %Schema{type: :object, properties: %{import: schema}, required: [:import]}

  def list,
    do: %Schema{
      type: :object,
      properties: %{imports: %Schema{type: :array, items: import()}},
      required: [:imports]
    }

  def issue(code_enum) do
    %Schema{
      type: :object,
      properties: %{code: code_enum, field: %Schema{field_enum() | nullable: true}},
      required: [:code, :field]
    }
  end

  def row do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        row_number: %Schema{type: :integer},
        cells: %Schema{type: :array, items: %Schema{type: :string}},
        status: row_status_enum(),
        outcome: %Schema{outcome_enum() | nullable: true},
        warnings: %Schema{type: :array, items: issue(warning_enum())},
        errors: %Schema{type: :array, items: issue(error_enum())},
        result: %Schema{type: :object, additionalProperties: true},
        user_id: %Schema{@uuid | nullable: true},
        error_code: %Schema{type: :string, nullable: true},
        applied_at: @time
      },
      required: [:cells, :errors, :id, :result, :row_number, :status, :warnings]
    }
  end

  def rows do
    %Schema{
      type: :object,
      properties: %{
        rows: %Schema{type: :array, items: row()},
        next_after_row: %Schema{type: :integer, nullable: true}
      },
      required: [:next_after_row, :rows]
    }
  end

  def preview_body do
    %Schema{
      type: :object,
      properties: %{
        mapping: %Schema{type: :array, items: mapping_entry()},
        date_order: date_order_enum(),
        default_role: role_enum()
      }
    }
  end

  def invitations_body do
    %Schema{
      type: :object,
      properties: %{
        person_ids: %Schema{type: :array, items: @uuid, maxItems: ImportPolicy.max_invitations()},
        limit: %Schema{type: :integer, minimum: 1, maximum: ImportPolicy.max_invitations()}
      }
    }
  end

  def invitations do
    %Schema{
      type: :object,
      properties: %{
        sent: %Schema{type: :integer},
        failed: %Schema{type: :integer},
        remaining: %Schema{type: :integer},
        results: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              person_id: @uuid,
              email: %Schema{type: :string},
              status: %Schema{type: :string, enum: ["queued", "failed"]},
              error: %Schema{type: :string, nullable: true}
            },
            required: [:email, :error, :person_id, :status]
          }
        }
      },
      required: [:failed, :remaining, :results, :sent]
    }
  end
end
