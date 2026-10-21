defmodule Palee.Application.MediaTools do
  @moduledoc """
  The configured media adapters (ADR-157): image processing, video
  transcoding and alternative text suggestions.
  """

  def image_processor, do: Application.fetch_env!(:palee, :image_processor)
  def video_transcoder, do: Application.fetch_env!(:palee, :video_transcoder)
  def image_describer, do: Application.fetch_env!(:palee, :image_describer)

  @doc "Whether video posts can be processed on this server."
  def video_available?, do: video_transcoder().available?() and image_processor().available?()

  @doc "Whether background jobs run (otherwise work runs inline, as in tests)."
  def background?, do: Application.get_env(:palee, :start_oban, true)
end
