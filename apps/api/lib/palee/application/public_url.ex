defmodule Palee.Application.PublicURL do
  def base_url, do: Application.fetch_env!(:palee, :public_base_url)
end
