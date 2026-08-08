defmodule MilosTraining.Application.PresignInvoiceUpload do
  @moduledoc false

  alias MilosTraining.Application.DocumentStorage
  alias MilosTraining.Finance
  alias MilosTraining.Finance.Domain.InvoiceDocumentPolicy

  def call(context, invoice_id, params) do
    file_name = params["file_name"] || params[:file_name]
    content_type = params["content_type"] || params[:content_type]

    with {:ok, invoice} <- Finance.get_invoice(context, invoice_id),
         true <- invoice.organization_id == context.organization_id,
         {:ok, upload} <- InvoiceDocumentPolicy.validate_request(file_name, content_type),
         relative_key <- "invoices/#{invoice_id}/#{Ecto.UUID.generate()}#{upload.extension}",
         {:ok, presigned} <-
           DocumentStorage.tenant_upload_post(
             context,
             relative_key,
             InvoiceDocumentPolicy.storage_policy(upload)
           ) do
      {:ok,
       %{
         upload_url: presigned.url,
         method: presigned.method,
         fields: presigned.fields,
         required_headers: presigned.required_headers,
         file_key: presigned.key,
         file_name: upload.file_name,
         content_type: upload.content_type,
         max_bytes: upload.max_bytes,
         expires_in: presigned.expires_in
       }}
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end
end
