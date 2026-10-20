defmodule MilosTraining.Infrastructure.Wallet.Der do
  @moduledoc """
  The few DER encodings a CMS (PKCS#7) signature needs (ADR-155), and a TLV
  reader to lift the issuer and serial number out of a certificate as their
  original bytes. Small on purpose: everything here is X.690 DER.
  """

  import Bitwise

  def sequence(items), do: tlv(0x30, IO.iodata_to_binary(items))

  @doc "A DER SET OF: elements sorted by their encodings."
  def set(items), do: tlv(0x31, items |> Enum.sort() |> IO.iodata_to_binary())

  def integer(value) when is_integer(value) and value >= 0 do
    bytes = :binary.encode_unsigned(value)
    bytes = if :binary.first(bytes) >= 0x80, do: <<0>> <> bytes, else: bytes
    tlv(0x02, bytes)
  end

  def null, do: <<0x05, 0x00>>
  def octet_string(bytes), do: tlv(0x04, bytes)

  def oid(dotted) when is_binary(dotted) do
    [first, second | rest] = dotted |> String.split(".") |> Enum.map(&String.to_integer/1)
    tlv(0x06, IO.iodata_to_binary([first * 40 + second | Enum.map(rest, &base128/1)]))
  end

  def utc_time(%DateTime{} = at) do
    tlv(0x17, Calendar.strftime(DateTime.shift_zone!(at, "Etc/UTC"), "%y%m%d%H%M%SZ"))
  end

  @doc "`[n] EXPLICIT` around already-encoded content."
  def explicit(n, content), do: tlv(0xA0 + n, content)

  @doc "`[n] IMPLICIT` constructed: replaces the tag of a SET/SEQUENCE encoding."
  def implicit_constructed(n, <<_tag, rest::binary>>), do: <<0xA0 + n>> <> rest

  def tlv(tag, content), do: <<tag>> <> encode_length(byte_size(content)) <> content

  defp encode_length(size) when size < 0x80, do: <<size>>

  defp encode_length(size) do
    bytes = :binary.encode_unsigned(size)
    <<0x80 ||| byte_size(bytes)>> <> bytes
  end

  defp base128(value) when value < 0x80, do: <<value>>

  defp base128(value) do
    value
    |> Integer.digits(128)
    |> then(fn digits ->
      {init, [last]} = Enum.split(digits, -1)
      IO.iodata_to_binary(Enum.map(init, &<<&1 ||| 0x80>>) ++ [<<last>>])
    end)
  end

  @doc "Reads one TLV: `{tag, content, whole_encoding, rest}`."
  def read(<<tag, rest::binary>> = all) do
    {size, after_length} = read_length(rest)
    <<content::binary-size(size), tail::binary>> = after_length
    header = byte_size(all) - byte_size(after_length)
    {tag, content, binary_part(all, 0, header + size), tail}
  end

  defp read_length(<<size, rest::binary>>) when size < 0x80, do: {size, rest}

  defp read_length(<<marker, rest::binary>>) do
    count = marker &&& 0x7F
    <<bytes::binary-size(count), tail::binary>> = rest
    {:binary.decode_unsigned(bytes), tail}
  end

  @doc "All TLVs of a constructed value, as whole encodings."
  def children(content), do: children(content, [])

  defp children(<<>>, acc), do: Enum.reverse(acc)

  defp children(content, acc) do
    {_tag, _inner, whole, rest} = read(content)
    children(rest, [whole | acc])
  end

  @doc """
  The issuer `Name` and `serialNumber` of a DER certificate, as their DER
  encodings (for a CMS IssuerAndSerialNumber).
  """
  def issuer_and_serial(certificate_der) do
    {0x30, cert_content, _whole, _rest} = read(certificate_der)
    [tbs | _] = children(cert_content)
    {0x30, tbs_content, _whole, _rest} = read(tbs)

    fields =
      case children(tbs_content) do
        [<<0xA0, _::binary>> | rest] -> rest
        all -> all
      end

    [serial, _signature_algorithm, issuer | _] = fields
    {issuer, serial}
  end
end
