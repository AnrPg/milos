defmodule MilosTraining.Application.CalendarFeedToken do
  # Calendar clients cannot attach bearer auth headers, so feed URLs use signed
  # bearer tokens. The token embeds a per-user version so regenerating calendar
  # links revokes previously leaked URLs without rotating the app secret.
  @salt "calendar-feed-v1"

  alias MilosTraining.Application.SignedToken
  alias MilosTraining.Identity

  def sign(user) do
    SignedToken.sign(@salt, %{
      "user_id" => user.id,
      "role" => to_string(user.role),
      "version" => user.calendar_feed_token_version || 1
    })
  end

  def verify(token) when is_binary(token) do
    with {:ok, %{"user_id" => user_id, "version" => token_version}} <-
           SignedToken.verify(@salt, token, max_age: :infinity),
         user when not is_nil(user) <- Identity.find_by_id(user_id) do
      if token_version == (user.calendar_feed_token_version || 1) do
        {:ok, user}
      else
        {:error, :invalid_token}
      end
    else
      nil -> {:error, :not_found}
      {:error, _reason} -> {:error, :invalid_token}
      {:ok, _payload} -> {:error, :invalid_token}
    end
  end

  def verify(_token), do: {:error, :invalid_token}
end
