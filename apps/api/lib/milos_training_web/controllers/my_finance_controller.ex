defmodule MilosTrainingWeb.MyFinanceController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug

  alias MilosTraining.Application.{
    GetFinanceRefundReceipt,
    GetMyFinance,
    ListFinanceRefundReceipts,
    RenderFinanceRefundReceipt
  }

  alias MilosTrainingWeb.Controllers.ReceiptDocumentResponse
  alias MilosTrainingWeb.Schemas.FinanceAccounting
  alias MilosTraining.Finance
  alias MilosTraining.Application.DocumentStorage
  alias OpenApiSpex.Schema

  action_fallback MilosTrainingWeb.FallbackController

  def action(conn, _) do
    case conn.assigns[:tenant_context] do
      nil ->
        apply(__MODULE__, action_name(conn), [conn, conn.params])

      context ->
        MilosTraining.Finance.with_tenant_context(context, fn ->
          apply(__MODULE__, action_name(conn), [conn, conn.params])
        end)
    end
  end

  tags(["Member Finance"])
  security([%{"bearerAuth" => []}])

  operation(:index,
    summary: "Get the current member's finance summary",
    responses: [
      ok:
        {"Member finance data", "application/json",
         %Schema{type: :object, additionalProperties: true}}
    ]
  )

  def index(conn, _params) do
    user = GuardianPlug.current_resource(conn)

    with {:ok, context} <- tenant_context(conn),
         {:ok, finance} <- GetMyFinance.call(context, user.id) do
      json(conn, finance)
    end
  end

  operation(:entitlement,
    summary: "Get the current user's effective package benefits and allowance usage",
    responses: [
      ok:
        {"Effective entitlement", "application/json",
         %Schema{type: :object, additionalProperties: true}}
    ]
  )

  def entitlement(conn, _params) do
    user = GuardianPlug.current_resource(conn)

    with {:ok, context} <- tenant_context(conn) do
      entitlement = Finance.get_effective_entitlement(context, user.id)
      json(conn, %{entitlement: entitlement})
    end
  end

  operation(:invoice_download_url,
    summary: "Get a presigned download URL for one of the current member's invoices",
    parameters: [
      %OpenApiSpex.Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok:
        {"Download URL", "application/json", %Schema{type: :object, additionalProperties: true}},
      not_found: {"Not found", "application/json", %Schema{type: :object}},
      forbidden: {"Forbidden", "application/json", %Schema{type: :object}}
    ]
  )

  def invoice_download_url(conn, %{"id" => invoice_id}) do
    user = GuardianPlug.current_resource(conn)

    with {:ok, context} <- tenant_context(conn),
         {:ok, invoice} <- get_invoice(context, invoice_id),
         :ok <- verify_invoice_owner(invoice, user.id),
         file_key when is_binary(file_key) <- (invoice.params || %{})["file_key"],
         {:ok, download_url} <-
           DocumentStorage.tenant_download_url(
             %{organization_id: invoice.organization_id},
             file_key
           ) do
      file_name = (invoice.params || %{})["file_name"] || Path.basename(file_key)
      json(conn, %{download_url: download_url, file_name: file_name})
    else
      nil -> {:error, :not_found}
      {:error, :forbidden} -> {:error, :forbidden}
      err -> err
    end
  end

  # ADR-126: a member's own refund receipts. Receipts of other members are
  # reported as not found.
  @receipt_id %OpenApiSpex.Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:refund_receipts,
    summary: "List the current member's refund receipts",
    responses: [
      ok: {"Refund receipts", "application/json", FinanceAccounting.refund_receipt_collection()}
    ]
  )

  def refund_receipts(conn, _params) do
    user = GuardianPlug.current_resource(conn)

    with {:ok, context} <- tenant_context(conn),
         {:ok, payload} <- ListFinanceRefundReceipts.call(context, {:member, user.id}, %{}) do
      json(conn, payload)
    end
  end

  operation(:refund_receipt,
    summary: "Get one of the current member's refund receipts",
    parameters: [@receipt_id],
    responses: [
      ok: {"Refund receipt", "application/json", FinanceAccounting.refund_receipt_response()},
      not_found: {"Not found", "application/json", %Schema{type: :object}}
    ]
  )

  def refund_receipt(conn, %{"id" => id}) do
    user = GuardianPlug.current_resource(conn)

    with {:ok, context} <- tenant_context(conn),
         {:ok, receipt} <- GetFinanceRefundReceipt.call(context, id, {:member, user.id}) do
      json(conn, %{refund_receipt: receipt})
    end
  end

  operation(:refund_receipt_document,
    summary: "Printable HTML version of one of the current member's refund receipts",
    parameters: [
      @receipt_id,
      %OpenApiSpex.Parameter{name: :locale, in: :query, schema: %Schema{type: :string}}
    ],
    responses: [
      ok: {"Receipt document", "text/html", %Schema{type: :string}},
      not_found: {"Not found", "application/json", %Schema{type: :object}}
    ]
  )

  def refund_receipt_document(conn, %{"id" => id} = params) do
    user = GuardianPlug.current_resource(conn)
    locale = ReceiptDocumentResponse.locale(conn, params)

    with {:ok, context} <- tenant_context(conn),
         {:ok, document} <-
           RenderFinanceRefundReceipt.call(context, id, {:member, user.id}, locale) do
      ReceiptDocumentResponse.send(conn, document)
    end
  end

  defp verify_invoice_owner(invoice, user_id) do
    if invoice.user_id == user_id, do: :ok, else: {:error, :forbidden}
  end

  defp get_invoice(context, invoice_id), do: Finance.get_invoice(context, invoice_id)

  defp tenant_context(conn) do
    case conn.assigns[:tenant_context] do
      %{organization_id: organization_id} = context when is_binary(organization_id) ->
        {:ok, context}

      _missing ->
        {:error, :organization_context_required}
    end
  end
end
