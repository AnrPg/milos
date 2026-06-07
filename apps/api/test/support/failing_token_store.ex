defmodule MilosTraining.TestSupport.FailingTokenStore do
  def revoked?(_jti), do: {:error, :redis_down}
  def revoke(_jti, _ttl_ms), do: {:error, :redis_down}
end
