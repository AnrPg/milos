defmodule MilosTraining.Application.Ports.DocumentStorage do
  @callback presigned_upload_url(String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback presigned_download_url(String.t()) :: {:ok, String.t()} | {:error, term()}
end
