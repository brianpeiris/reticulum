defmodule Ret.Repo.Migrations.CreateHubsTable do
  use Ecto.Migration

  def change do
    create table(:hubs, prefix: "ret0", primary_key: false) do
      add :hub_id, :bigint, default: fragment("ret0.next_id()"), primary_key: true
      add :hub_sid, :string
      add :slug, :string, null: false
      add :name, :string, null: false
      add :default_environment_gltf_bundle_url, :string, null: false

      timestamps()
    end

    create index(:hubs, [:hub_sid], unique: true)
  end
end
