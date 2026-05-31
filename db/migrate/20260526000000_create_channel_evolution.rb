class CreateChannelEvolution < ActiveRecord::Migration[7.1]
  def change
    create_table :channel_evolution do |t|
      t.integer :account_id, null: false
      t.string :identifier, null: false
      t.string :instance_name, null: false
      t.string :instance_id
      t.string :webhook_url
      t.string :qr_code
      t.string :status, default: 'pending'
      t.jsonb :additional_attributes, default: {}
      t.string :phone_number
      t.string :session
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false

      t.index :identifier, unique: true
      t.index :instance_id
      t.index :account_id
    end
  end
end
