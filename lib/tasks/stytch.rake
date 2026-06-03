namespace :stytch do
  desc "Provision/link every seeded User to a Stytch user (idempotent)"
  task sync_users: :environment do
    linked = 0
    User.find_each do |user|
      StytchUserSync.call(user)
      if user.stytch_user_id.present?
        linked += 1
        puts "  ✓ #{user.email.ljust(28)} #{user.stytch_user_id}"
      else
        warn "  ✗ #{user.email.ljust(28)} not linked (Stytch create failed)"
      end
    end
    puts "\nLinked #{linked}/#{User.count} users to Stytch."
  end
end
