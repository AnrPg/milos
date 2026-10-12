defmodule MilosTrainingWeb.PaymentModelsController do
  @moduledoc "Shared-membership beneficiaries and corporate clients (ADR-098)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug

  alias MilosTraining.Application.{
    AddSubscriptionBeneficiary,
    EnrollCorporateSeat,
    ListCorporateSeats
  }

  alias MilosTraining.Finance
  alias MilosTrainingWeb.Schemas.PaymentModels, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Payment models"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @error %Schema{type: :object, additionalProperties: true}
  @uuid %Schema{type: :string, format: :uuid}
  @id %Parameter{name: :id, in: :path, required: true, schema: @uuid}
  @beneficiary_id %Parameter{name: :beneficiary_id, in: :path, required: true, schema: @uuid}
  @subscription_id %Parameter{name: :subscription_id, in: :path, required: true, schema: @uuid}
  @client_response S.wrap(:client, S.client_schema())
  @beneficiary_response S.wrap(:beneficiary, S.beneficiary_schema())
  @invoice_response S.wrap(:invoice, S.invoice_schema())
  @seat_response S.wrap(:seat, S.seat_schema())

  # Shared memberships

  operation(:beneficiaries,
    summary: "People sharing a membership",
    parameters: [@id],
    responses: [
      ok: {"Beneficiaries", "application/json", S.list(:beneficiaries, S.beneficiary_schema())}
    ]
  )

  def beneficiaries(conn, %{id: id}) do
    json(conn, %{beneficiaries: Finance.list_beneficiaries(conn.assigns.tenant_context, id)})
  end

  operation(:add_beneficiary,
    summary: "Add a gym member to a shared membership",
    parameters: [@id],
    request_body:
      S.body(%Schema{
        type: :object,
        properties: %{user_id: @uuid, is_minor: %Schema{type: :boolean}},
        required: [:user_id]
      }),
    responses: [
      created: {"Beneficiary", "application/json", @beneficiary_response},
      unprocessable_entity: {"Limit reached or not allowed", "application/json", @error}
    ]
  )

  def add_beneficiary(conn, %{id: id}) do
    admin = GuardianPlug.current_resource(conn)

    with {:ok, beneficiary} <-
           AddSubscriptionBeneficiary.call(
             conn.assigns.tenant_context,
             admin,
             id,
             conn.body_params
           ) do
      conn |> put_status(:created) |> json(%{beneficiary: beneficiary})
    end
  end

  operation(:remove_beneficiary,
    summary: "Remove a beneficiary from a shared membership",
    parameters: [@id, @beneficiary_id],
    responses: [ok: {"Beneficiary", "application/json", @beneficiary_response}]
  )

  def remove_beneficiary(conn, %{id: id, beneficiary_id: beneficiary_id}) do
    with {:ok, beneficiary} <-
           Finance.remove_beneficiary(conn.assigns.tenant_context, id, beneficiary_id) do
      json(conn, %{beneficiary: beneficiary})
    end
  end

  # Corporate clients

  operation(:clients,
    summary: "Corporate clients",
    responses: [ok: {"Clients", "application/json", S.list(:clients, S.client_schema())}]
  )

  def clients(conn, _params) do
    json(conn, %{clients: Finance.list_corporate_clients(conn.assigns.tenant_context)})
  end

  operation(:create_client,
    summary: "Create the corporate client of a corporate package",
    request_body:
      S.body(%Schema{
        type: :object,
        additionalProperties: false,
        properties: %{
          membership_package_id: @uuid,
          company_name: %Schema{type: :string, minLength: 2, maxLength: 120},
          billing_email: %Schema{type: :string, maxLength: 200, nullable: true},
          contact_name: %Schema{type: :string, maxLength: 120, nullable: true}
        },
        required: [:membership_package_id, :company_name]
      }),
    responses: [
      created: {"Client", "application/json", @client_response},
      unprocessable_entity: {"Invalid client", "application/json", @error}
    ]
  )

  def create_client(conn, _params) do
    with {:ok, client} <-
           Finance.create_corporate_client(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{client: client})
    end
  end

  operation(:update_client,
    summary: "Edit a corporate client, archive it or issue a new enrollment code",
    parameters: [@id],
    request_body:
      S.body(%Schema{
        type: :object,
        additionalProperties: false,
        properties: %{
          company_name: %Schema{type: :string, minLength: 2, maxLength: 120},
          billing_email: %Schema{type: :string, maxLength: 200, nullable: true},
          contact_name: %Schema{type: :string, maxLength: 120, nullable: true},
          status: %Schema{type: :string, enum: ["active", "archived"]},
          regenerate_code: %Schema{type: :boolean}
        }
      }),
    responses: [ok: {"Client", "application/json", @client_response}]
  )

  def update_client(conn, %{id: id}) do
    with {:ok, client} <-
           Finance.update_corporate_client(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{client: client})
    end
  end

  operation(:seats,
    summary: "Seats of a corporate client",
    parameters: [@id],
    responses: [ok: {"Seats", "application/json", S.list(:seats, S.seat_schema())}]
  )

  def seats(conn, %{id: id}) do
    json(conn, %{seats: ListCorporateSeats.call(conn.assigns.tenant_context, id)})
  end

  operation(:add_seat,
    summary: "Give a gym member a seat on the corporate plan",
    parameters: [@id],
    request_body:
      S.body(%Schema{type: :object, properties: %{user_id: @uuid}, required: [:user_id]}),
    responses: [
      created: {"Seat", "application/json", @seat_response},
      conflict: {"No seats left or already enrolled", "application/json", @error}
    ]
  )

  def add_seat(conn, %{id: id}) do
    user_id = Map.get(conn.body_params, :user_id)

    with {:ok, seat} <-
           Finance.enroll_corporate_seat(conn.assigns.tenant_context, id, user_id, %{}) do
      conn |> put_status(:created) |> json(%{seat: Map.put(seat, :user_id, user_id)})
    end
  end

  operation(:end_seat,
    summary: "End an employee's seat today",
    parameters: [@id, @subscription_id],
    responses: [ok: {"Seat", "application/json", @seat_response}]
  )

  def end_seat(conn, %{id: id, subscription_id: subscription_id}) do
    with {:ok, seat} <-
           Finance.end_corporate_seat(conn.assigns.tenant_context, id, subscription_id) do
      json(conn, %{seat: Map.put_new(seat, :user_id, nil)})
    end
  end

  operation(:invoices,
    summary: "Invoices issued to a corporate client",
    parameters: [@id],
    responses: [ok: {"Invoices", "application/json", S.list(:invoices, S.invoice_schema())}]
  )

  def invoices(conn, %{id: id}) do
    json(conn, %{invoices: Finance.list_corporate_invoices(conn.assigns.tenant_context, id)})
  end

  operation(:create_invoice,
    summary: "Invoice a corporate client for the period containing a date (today by default)",
    parameters: [@id],
    request_body:
      S.optional_body(%Schema{
        type: :object,
        properties: %{on: %Schema{type: :string, format: :date, nullable: true}}
      }),
    responses: [
      created: {"Invoice", "application/json", @invoice_response},
      unprocessable_entity: {"Already invoiced for the period", "application/json", @error}
    ]
  )

  def create_invoice(conn, %{id: id}) do
    on = Map.get(conn.body_params || %{}, :on) || Date.utc_today()

    with {:ok, invoice} <- Finance.generate_corporate_invoice(conn.assigns.tenant_context, id, on) do
      conn |> put_status(:created) |> json(%{invoice: invoice})
    end
  end

  operation(:invoice_status,
    summary: "Mark a corporate invoice paid or void",
    parameters: [@id],
    request_body:
      S.body(%Schema{
        type: :object,
        properties: %{status: %Schema{type: :string, enum: ["paid", "void"]}},
        required: [:status]
      }),
    responses: [ok: {"Invoice", "application/json", @invoice_response}]
  )

  def invoice_status(conn, %{id: id}) do
    status = Map.get(conn.body_params, :status)

    with {:ok, invoice} <-
           Finance.set_corporate_invoice_status(conn.assigns.tenant_context, id, status) do
      json(conn, %{invoice: invoice})
    end
  end

  # Member

  operation(:enroll,
    summary: "Join my company's corporate plan with its code, or by my email domain",
    request_body:
      S.optional_body(%Schema{
        type: :object,
        properties: %{code: %Schema{type: :string, maxLength: 20, nullable: true}}
      }),
    responses: [
      created: {"Seat", "application/json", @seat_response},
      not_found: {"No matching plan", "application/json", @error},
      conflict: {"No seats left or already enrolled", "application/json", @error}
    ]
  )

  def enroll(conn, _params) do
    actor = GuardianPlug.current_resource(conn)

    with {:ok, seat} <-
           EnrollCorporateSeat.call(conn.assigns.tenant_context, actor, conn.body_params || %{}) do
      conn |> put_status(:created) |> json(%{seat: Map.put(seat, :user_id, actor.id)})
    end
  end
end
