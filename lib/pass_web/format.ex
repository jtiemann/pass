defmodule PassWeb.Format do
  @moduledoc "Small display-formatting helpers shared across views."

  @doc ~S"""
  Formats a Decimal as money with thousands separators.

      iex> PassWeb.Format.money(Decimal.new("90000"), "$")
      "$90,000.00"

      iex> PassWeb.Format.money(Decimal.new("1234567.5"), "USD ")
      "USD 1,234,567.50"
  """
  def money(%Decimal{} = value, prefix \\ "$") do
    [int, frac] =
      case value |> Decimal.round(2) |> Decimal.to_string(:normal) |> String.split(".") do
        [int] -> [int, "00"]
        [int, frac] -> [int, String.pad_trailing(frac, 2, "0")]
      end

    {sign, digits} =
      case int do
        "-" <> rest -> {"-", rest}
        _ -> {"", int}
      end

    grouped =
      digits
      |> String.reverse()
      |> String.codepoints()
      |> Enum.chunk_every(3)
      |> Enum.map_join(",", &Enum.join/1)
      |> String.reverse()

    "#{sign}#{prefix}#{grouped}.#{frac}"
  end
end
