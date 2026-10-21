defmodule Palee.Coaching.Ports.FormReviewStore do
  @moduledoc "Persistence port for form reviews and overdue-reply alerts (ADR-098)."

  @callback create_review(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_review(map(), binary()) :: map() | nil
  @callback list_reviews(map(), map()) :: [map()]
  @callback review(map(), binary(), map()) :: {:ok, map()} | {:error, term()}
  @callback withdraw(map(), binary()) :: {:ok, map()} | {:error, term()}
  @callback alerted_message_ids(map(), [binary()]) :: [binary()]
  @callback record_alert(map(), map()) :: :ok | {:error, term()}
end
