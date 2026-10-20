defmodule MilosTraining.Infrastructure.Ai.GeminiImageDescriber do
  @moduledoc """
  Suggests alternative text for a photo in a post with Gemini (ADR-157):
  one plain sentence in the person's language, saying what is in the photo
  for someone who cannot see it. Model: `GEMINI_VISION_MODEL`.
  """

  @behaviour MilosTraining.Application.Ports.ImageDescriber

  alias MilosTraining.Infrastructure.Ai.GeminiVision

  @languages %{
    "el" => "Greek",
    "en" => "English",
    "de" => "German",
    "fr" => "French",
    "es" => "Spanish",
    "it" => "Italian",
    "pt" => "Portuguese",
    "nl" => "Dutch",
    "pl" => "Polish",
    "ro" => "Romanian",
    "bg" => "Bulgarian",
    "tr" => "Turkish",
    "sq" => "Albanian",
    "ru" => "Russian",
    "uk" => "Ukrainian"
  }

  @instructions """
  You write the alternative text of a photo a gym member is about to post.
  Describe what is visible for someone who cannot see it: people (never
  guess names, age or identity), what they are doing, the equipment, the
  place. One plain sentence, at most 25 words, no "image of" or "photo of",
  no emoji, no hashtags, nothing that is not visible. Reply with the sentence only.
  """

  @impl true
  def describe(image, %{locale: locale}, metering) do
    language = Map.get(@languages, locale |> to_string() |> String.slice(0, 2), "Greek")

    case GeminiVision.generate(
           image,
           @instructions,
           "Write it in #{language}.",
           %{temperature: 0.3, maxOutputTokens: 120},
           metering,
           "alt_text"
         ) do
      {:ok, {:blocked, _reason}} -> {:error, :blocked}
      other -> other
    end
  end
end
