defmodule MilosTraining.Application.DocumentStorage do
  @behaviour MilosTraining.Application.Ports.DocumentStorage

  @impl true
  def presigned_upload_url(key), do: impl().presigned_upload_url(key)
  @impl true
  def presigned_download_url(key), do: impl().presigned_download_url(key)

  defp impl, do: Application.fetch_env!(:milos_training, :document_storage)
end
