defmodule MilosTraining.Application.Ports.DocumentStorage do
  @callback presigned_upload_post(String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback presigned_download_url(String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback validate_uploaded_document(String.t(), map()) :: {:ok, map()} | {:error, term()}
end
