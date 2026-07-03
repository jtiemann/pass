defmodule Pass.Vault.Asset do
  @moduledoc """
  A single asset the family wants to track: what it is, where it lives, and how to
  access, prove ownership of, or sell it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @categories ~w(financial real_estate vehicle insurance digital crypto valuables business other)a
  @statuses ~w(active archived)a

  schema "assets" do
    field :name, :string
    field :category, Ecto.Enum, values: @categories, default: :other
    field :status, Ecto.Enum, values: @statuses, default: :active

    field :institution, :string
    field :location, :string
    field :description, :string
    field :estimated_value, :decimal
    field :currency, :string, default: "USD"

    field :access_instructions, :string
    field :ownership_proof, :string
    field :sale_instructions, :string

    # Growth assumptions for projections. Nil return = use the category's
    # historical default (see Pass.Vault.Projection).
    field :annual_return_pct, :decimal
    field :dividend_yield_pct, :decimal
    field :dividends_reinvested, :boolean, default: true

    belongs_to :created_by, Pass.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc "All valid category atoms."
  def categories, do: @categories

  @doc "All valid status atoms."
  def statuses, do: @statuses

  @doc "Options suitable for a `<.input type=\"select\">` (label/value tuples)."
  def category_options, do: Enum.map(@categories, &{humanize_category(&1), &1})

  @doc "Turns a category atom into a display label."
  def humanize_category(category) do
    category
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  def changeset(asset, attrs) do
    asset
    |> cast(attrs, [
      :name,
      :category,
      :status,
      :institution,
      :location,
      :description,
      :estimated_value,
      :currency,
      :access_instructions,
      :ownership_proof,
      :sale_instructions,
      :annual_return_pct,
      :dividend_yield_pct,
      :dividends_reinvested
    ])
    |> validate_required([:name, :category, :status])
    |> validate_length(:name, max: 200)
    |> validate_number(:estimated_value, greater_than_or_equal_to: 0)
    |> validate_number(:annual_return_pct,
      greater_than_or_equal_to: -100,
      less_than_or_equal_to: 100
    )
    |> validate_number(:dividend_yield_pct,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
  end
end
