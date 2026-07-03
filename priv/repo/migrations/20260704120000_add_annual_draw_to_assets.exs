defmodule Pass.Repo.Migrations.AddAnnualDrawToAssets do
  use Ecto.Migration

  def change do
    alter table(:assets) do
      # Amount withdrawn at the end of each year (in the asset's currency) to
      # cover expenses elsewhere. Nil/0 = no draw.
      add :annual_draw, :decimal
    end
  end
end
