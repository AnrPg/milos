defmodule PaleeWeb.StaffController do
  @moduledoc "The gym's staff by their role in this gym (ADR-098)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.ListGymStaff
  alias OpenApiSpex.Schema

  tags(["Staff"])
  security([%{"bearerAuth" => []}])

  @member %Schema{
    title: "StaffMember",
    type: :object,
    properties: %{
      user_id: %Schema{type: :string, format: :uuid},
      nickname: %Schema{type: :string, nullable: true},
      role: %Schema{
        type: :string,
        enum: ["owner", "admin", "coach"],
        description: "Primary role in this gym"
      },
      roles: %Schema{
        type: :array,
        description: "Every role held in this gym (ADR-099), e.g. owner and coach",
        items: %Schema{
          type: :string,
          enum: [
            "owner",
            "admin",
            "coach",
            "front_desk",
            "accountant",
            "janitor",
            "member",
            "athlete"
          ]
        }
      }
    },
    required: [:user_id, :role, :roles]
  }

  operation(:index,
    summary: "Owners, admins and coaches of this gym",
    responses: [
      ok:
        {"Staff", "application/json",
         %Schema{
           type: :object,
           properties: %{staff: %Schema{type: :array, items: @member}},
           required: [:staff]
         }}
    ]
  )

  def index(conn, _params) do
    json(conn, %{staff: ListGymStaff.call(conn.assigns.tenant_context)})
  end
end
