require_relative "seeds/seed_helper"

SeedHelper.banner("Part Lifecycle Tracker - db:seed")
Dir[Rails.root.join("db/seeds/*.rb")].sort.each { |f| require f }
SeedHelper.summary
