defmodule Palee.Application.Ports.ImageProcessor do
  @moduledoc """
  Decodes an uploaded image and writes its renditions (ADR-157). Every
  rendition is re-encoded from decoded pixels, turned upright first, with no
  metadata at all (EXIF, GPS, XMP, IPTC, ICC comments), so nothing the camera
  wrote survives. Input types are named explicitly; nothing is guessed.
  """

  @type probe :: %{width: pos_integer(), height: pos_integer()}
  @type variant_spec :: %{name: String.t(), max_edge: pos_integer(), quality: 1..100}
  @type spec :: %{variants: [variant_spec()], placeholder_edge: pos_integer()}
  @type rendition :: %{
          name: String.t(),
          path: Path.t(),
          content_type: String.t(),
          extension: String.t(),
          width: pos_integer(),
          height: pos_integer(),
          bytes: non_neg_integer()
        }
  @type result :: %{
          width: pos_integer(),
          height: pos_integer(),
          renditions: [rendition()],
          placeholder: String.t()
        }

  @doc "Whether the tool this adapter drives is installed."
  @callback available?() :: boolean()

  @doc "Upright dimensions of the image at `path`, of declared `content_type`, without decoding it all."
  @callback probe(Path.t(), String.t()) :: {:ok, probe()} | {:error, term()}

  @doc "Writes every rendition into `work_dir`, plus a tiny data-URI placeholder."
  @callback process(Path.t(), String.t(), spec(), Path.t()) :: {:ok, result()} | {:error, term()}
end
