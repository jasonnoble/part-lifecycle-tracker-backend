class CreateLifecycleEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :lifecycle_events, id: :uuid do |t|
      t.references :part_instance, null: false, type: :uuid, foreign_key: { to_table: :part_instances }
      t.string :event_type, null: false
      t.string :actor, null: false
      t.text :notes
      t.jsonb :metadata
      t.datetime :occurred_at, null: false # user-supplied, NO default
      t.datetime :recorded_at, null: false, default: -> { "now()" }
      t.datetime :created_at
      # no created_at / updated_at — append-only; recorded_at is the creation stamp
    end

    add_index :lifecycle_events, :occurred_at
    add_index :lifecycle_events, [ :part_instance_id, :occurred_at ], name: "index_lifecycle_events_on_instance_occurred_at"
    add_check_constraint :lifecycle_events, "event_type in ('ORDERED','RECEIVED','INSPECTED', 'IN_ASSEMBLY', 'INSTALLED', 'VALIDATED', 'CERTIFIED')", name: "lifecycle_events_event_type_check"
    add_check_constraint :lifecycle_events, "length(trim(actor)) > 0", name: "lifecycle_events_actor_present"
  end
end
