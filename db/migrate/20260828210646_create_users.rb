class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false

      # The second factor.  The secret is written through `encrypts`, so the column holds ciphertext and
      # is far longer than the 32 base32 characters it stands for — a plaintext TOTP secret *is* the
      # second factor to anyone holding a copy of the database file, in a way a bcrypt digest is not.
      #
      # Three columns rather than a secret and a boolean, because there are three states and the third
      # is worth telling apart: never enrolled (no secret), scanned but not yet proved (secret, no
      # confirmation), and live (both).  The timestamp also answers "since when", which is the question
      # worth asking of a login several people share.
      #
      # otp_last_used_at is the step of the last accepted code, so the same one cannot be used twice.
      t.string   :otp_secret
      t.datetime :otp_confirmed_at
      t.datetime :otp_last_used_at

      t.timestamps
    end
    add_index :users, :email_address, unique: true
  end
end
