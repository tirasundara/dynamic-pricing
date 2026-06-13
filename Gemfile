source "https://rubygems.org"

ruby "3.2.6"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 7.1.5", ">= 7.1.5.2"

# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 1.4"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

# Redis backs the shared cache, single-flight lock, and daily budget counter
gem "redis", ">= 4.0.1"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# HTTP client for external API call
gem 'httparty'

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
# gem "rack-cors"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ]

  # RSpec is the test framework for this project (replaces the default Minitest)
  gem "rspec-rails", "~> 6.1"
end

group :test do
  # Stub the upstream pricing API at the HTTP boundary in specs
  gem "webmock"
end

group :development do
  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"

  # Live reloading for development
  gem "listen", "~> 3.3"
end

