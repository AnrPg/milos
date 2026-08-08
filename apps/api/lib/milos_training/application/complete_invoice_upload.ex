defmodule MilosTraining.Application.CompleteInvoiceUpload do
  @moduledoc false

  alias MilosTraining.Application.DocumentStorage
  alias MilosTraining.Finance
  alias MilosTraining.Finance.Domain.InvoiceDocumentPolicy

  def call(context, invoice_id, params) do
    file_key = params["file_key"] || params[:file_key]
    file_name = params["file_name"] || params[:file_name]
    content_type = params["content_type"] || params[:content_type]

    with {:ok, invoice} <- Finance.get_invoice(context, invoice_id),
         true <- invoice.organization_id == context.organization_id,
         {:ok, upload} <- InvoiceDocumentPolicy.validate_request(file_name, content_type),
         :ok <- validate_key_belongs_to_invoice(context, invoice_id, file_key, upload.extension),
         {:ok, object} <-
           DocumentStorage.validate_tenant_upload(
             context,
             file_key,
             InvoiceDocumentPolicy.storage_policy(upload)
           ),
         updated_params <-
           Map.merge(invoice.params || %{}, %{
             "file_key" => file_key,
             "file_name" => upload.file_name,
             "content_type" => object.content_type,
             "byte_size" => object.byte_size
           }),
         {:ok, _invoice} <- Finance.update_invoice_params(invoice_id, updated_params) do
      {:ok,
       %{
         file_key: file_key,
         file_name: upload.file_name,
         content_type: object.content_type,
         byte_size: object.byte_size
       }}
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end

  defp validate_key_belongs_to_invoice(
         %{organization_id: organization_id},
         invoice_id,
         key,
         extension
       )
       when is_binary(key) do
    expected_prefix = "organizations/#{organization_id}/invoices/#{invoice_id}/"

    if String.starts_with?(key, expected_prefix) and String.ends_with?(key, extension),
      do: :ok,
      else: {:error, :document_key_forbidden}
  end

  defp validate_key_belongs_to_invoice(_context, _invoice_id, _key, _extension),
    do: {:error, :document_key_forbidden}
end
