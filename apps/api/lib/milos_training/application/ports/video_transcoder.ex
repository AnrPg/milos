defmodule MilosTraining.Application.Ports.VideoTranscoder do
  @moduledoc """
  Transcodes an uploaded short video (ADR-157) into one H.264/AAC MP4 that
  plays everywhere (at most `max_edge` on the long side, fast start), with
  every metadata block and chapter dropped, and grabs a JPEG poster frame.
  """

  @type probe :: %{
          duration_ms: non_neg_integer(),
          width: pos_integer(),
          height: pos_integer(),
          has_video: boolean()
        }
  @type spec :: %{max_edge: pos_integer(), max_duration_ms: pos_integer()}
  @type result :: %{
          path: Path.t(),
          content_type: String.t(),
          width: pos_integer(),
          height: pos_integer(),
          duration_ms: non_neg_integer(),
          bytes: non_neg_integer(),
          poster_path: Path.t()
        }

  @doc "Whether the tool this adapter drives is installed."
  @callback available?() :: boolean()

  @callback probe(Path.t()) :: {:ok, probe()} | {:error, term()}

  @doc "Writes the MP4 and its poster into `work_dir`."
  @callback transcode(Path.t(), spec(), Path.t()) :: {:ok, result()} | {:error, term()}
end
