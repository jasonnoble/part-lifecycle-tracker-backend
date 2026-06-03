class AddStytchUserIdToUsers < ActiveRecord::Migration[8.1]
  def change
    # Stytch's opaque user_id (the JWT `sub`). Nullable: seeded personas are
    # linked once their Stytch users are provisioned (JAS-76). Postgres allows
    # multiple NULLs under a unique index, so unseeded rows don't collide.
    add_column :users, :stytch_user_id, :string
    add_index :users, :stytch_user_id, unique: true
  end
end
