defmodule Palee.Content.Ports.ContentStore do
  @moduledoc "Persistence port of the Content context (ADR-098)."

  @type context :: %{organization_id: binary()}

  @callback list_videos(context(), keyword()) :: [map()]
  @callback get_video(context(), binary()) :: map() | nil
  @callback create_video(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback update_video(context(), binary(), map()) :: {:ok, map()} | {:error, term()}
  @callback set_video_published(context(), binary(), boolean()) :: {:ok, map()} | {:error, term()}
  @callback archive_video(context(), binary()) :: {:ok, map()} | {:error, term()}
end
