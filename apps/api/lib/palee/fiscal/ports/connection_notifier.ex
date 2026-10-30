defmodule Palee.Fiscal.Ports.ConnectionNotifier do
  @moduledoc """
  Tells the box's staff that one of its fiscal connections stopped working
  (ADR-273): a scheduled «Δοκιμή σύνδεσης» or a provider refusing the
  credentials while sending marked it invalid. `kind` is the connection
  (`mydata`, `registry`, `tse`, `rksv`, `sign_fr`, `peppol`) and `code`
  the stable error code. Never given any credential.
  """

  @callback connection_failed(context :: map(), kind :: String.t(), code :: String.t()) :: :ok
end
