defmodule MilosTrainingWeb.MyFinanceController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias MilosTraining.Application.GetMyFinance
  alias MilosTraining.Finance
  alias MilosTraining.Infrastructure.Storage.MinioStorage
  alias OpenApiSpex.Schema

  action_fallback MilosTrainingWeb.FallbackController

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

    {:ok, finance} = GetMyFinance.call(user.id)

    json(conn, finance)
  end

  operation(:entitlement,
    summary: "Get the current user's effective package benefits and allowance usage",
    responses: [
      ok:
        {"Effective entitlement", "application/json",
         %Schema{type: :object, additionalProperties: true}},
      not_found: {"Finance profile not found", "application/json", %Schema{type: :object}}
    ]
  )

  def entitlement(conn, _params) do
    user = GuardianPlug.current_resource(conn)

    case Finance.get_effective_entitlement(user.id) do
      nil -> {:error, :not_found}
      entitlement -> json(conn, %{entitlement: entitlement})
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

    with {:ok, invoice} <- Finance.get_invoice(invoice_id),
         :ok <- verify_invoice_owner(invoice, user.id),
         file_key when is_binary(file_key) <- (invoice.params || %{})["file_key"],
         {:ok, download_url} <- MinioStorage.presigned_download_url(file_key) do
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
end
