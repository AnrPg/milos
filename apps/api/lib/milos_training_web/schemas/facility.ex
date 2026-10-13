defmodule MilosTrainingWeb.Schemas.Facility do
  @moduledoc "OpenAPI schemas of the Facility context (ADR-097)."

  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @nullable_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @nullable_string %Schema{type: :string, nullable: true}
  @nullable_date_time %Schema{type: :string, format: :"date-time", nullable: true}

  def location_schema do
    %Schema{
      title: "FacilityLocation",
      type: :object,
      properties: %{
        id: @uuid,
        organization_id: @uuid,
        name: %Schema{type: :string},
        address: @nullable_string,
        archived_at: @nullable_date_time,
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name, :address, :archived_at]
    }
  end

  def location_params_schema do
    %Schema{
      type: :object,
      properties: %{
        name: %Schema{type: :string, minLength: 2, maxLength: 80},
        address: %Schema{type: :string, maxLength: 300, nullable: true}
      }
    }
  end

  def check_in_schema do
    %Schema{
      title: "FacilityCheckIn",
      type: :object,
      properties: %{
        id: @uuid,
        user_id: @uuid,
        nickname: @nullable_string,
        location_id: @nullable_uuid,
        location_name: @nullable_string,
        checked_in_on: %Schema{type: :string, format: :date},
        checked_in_at: %Schema{type: :string, format: :"date-time"},
        source: %Schema{type: :string, enum: ["self", "staff"]},
        recorded_by_id: @nullable_uuid,
        already_checked_in: %Schema{type: :boolean}
      },
      required: [:id, :user_id, :checked_in_on, :checked_in_at, :source]
    }
  end
end
