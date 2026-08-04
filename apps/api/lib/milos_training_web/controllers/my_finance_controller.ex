defmodule MilosTrainingWeb.MyFinanceController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias MilosTraining.Application.GetMyFinance
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

    {:ok, finance} =
      case conn.assigns[:tenant_context] do
        nil -> GetMyFinance.call(user.id)
        context -> GetMyFinance.call(context, user.id)
      end

    json(conn, finance)
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

    entitlement =
      case conn.assigns[:tenant_context] do
        nil -> Finance.get_effective_entitlement(user.id)
        context -> Finance.get_effective_entitlement(context, user.id)
      end

    json(conn, %{entitlement: entitlement})
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

    context = conn.assigns[:tenant_context]

    with {:ok, invoice} <- get_invoice(context, invoice_id),
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

  defp verify_invoice_owner(invoice, user_id) do
    if invoice.user_id == user_id, do: :ok, else: {:error, :forbidden}
  end

  defp get_invoice(nil, invoice_id), do: Finance.get_invoice(invoice_id)
  defp get_invoice(context, invoice_id), do: Finance.get_invoice(context, invoice_id)
end
