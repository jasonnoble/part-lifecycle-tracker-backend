class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: :uuid do |t|
      t.string :email
      t.string :name
      t.string :role

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_check_constraint :users, "length(trim(email)) > 0", name: "users_email_present"
    add_check_constraint :users, "length(trim(name)) > 0", name: "users_name_present"
    add_check_constraint :users, "role in ('salesperson', 'floor_manager', 'installer', 'qa_engineer', 'site_manager')", name: "users_role_check"
  end
end
