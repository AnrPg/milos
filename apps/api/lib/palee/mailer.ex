defmodule Palee.Mailer do
  use Swoosh.Mailer, otp_app: :palee

  # gen_smtp names a message after the host it runs on, so without this every
  # Message-ID carried the pod's hostname. Each email gets one from the sender's
  # own domain instead (TD-109).
  def deliver(email, config \\ []), do: super(stamp(email), config)

  @doc """
  Adds a `Message-ID` on the sender's domain and the configured `Reply-To`
  (`MAIL_REPLY_TO`, so a reply reaches support rather than `no-reply@`),
  each unless the email already has one.
  """
  def stamp(%Swoosh.Email{} = email), do: email |> put_message_id() |> put_reply_to()

  defp put_message_id(%Swoosh.Email{headers: %{"Message-ID" => _}} = email), do: email

  defp put_message_id(email),
    do: Swoosh.Email.header(email, "Message-ID", message_id(sender_domain(email)))

  defp put_reply_to(%Swoosh.Email{reply_to: nil} = email) do
    mail_from = Application.fetch_env!(:palee, :mail_from)

    case Keyword.get(mail_from, :reply_to) do
      address when is_binary(address) and address != "" ->
        Swoosh.Email.reply_to(email, {Keyword.fetch!(mail_from, :name), address})

      _unset ->
        email
    end
  end

  defp put_reply_to(email), do: email

  def message_id(domain), do: "<#{Ecto.UUID.generate()}@#{domain}>"

  @doc """
  The address emails come from when `MAIL_FROM_ADDRESS` is not set: the public
  host's `no-reply`, but never an internal or placeholder host, which would put
  infrastructure names in every header (raises instead).
  """
  def default_from_address(host) when is_binary(host) do
    if internal_host?(host) do
      raise """
      MAIL_FROM_ADDRESS is missing and PHX_HOST (#{host}) is not a public mail domain.
      Set MAIL_FROM_ADDRESS, e.g. no-reply@palee.app.
      """
    else
      "no-reply@#{host}"
    end
  end

  def internal_host?(host) do
    host = String.downcase(host)

    not String.contains?(host, ".") or host in ["example.com", "localhost"] or
      Enum.any?(~w(.4kq.net .local .localhost .internal .svc .cluster.local), &String.ends_with?(host, &1)) or
      host == "4kq.net"
  end

  def domain_of(address) when is_binary(address) do
    case String.split(address, "@") do
      [_local, domain] when domain != "" -> domain
      _ -> raise ArgumentError, "not an email address: #{inspect(address)}"
    end
  end

  defp sender_domain(%Swoosh.Email{from: {_name, address}}), do: domain_of(address)

  defp sender_domain(_email),
    do: :palee |> Application.fetch_env!(:mail_from) |> Keyword.fetch!(:address) |> domain_of()
end
