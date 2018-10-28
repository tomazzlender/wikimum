require "minitest/autorun"
require "rack/test"

ENV["DATABASE_URL"] = "postgres://localhost/wikimum_test"
ENV["RACK_ENV"] = "test"
ENV["SESSION_SECRET"] = "test"

require "sequel"
Sequel.extension :migration
Sequel::Migrator.run(Sequel.connect(ENV.fetch("DATABASE_URL")), "migrations")

class AppTest < Minitest::Test
  include Rack::Test::Methods

  OUTER_APP = Rack::Builder.parse_file("config.ru").first

  def app
    OUTER_APP
  end

  def setup
    Page.create(title: "Test", author: User.create)
  end

  def teardown
    Page[title: "Test"].destroy
  end

  def test_root
    get "/"
    assert last_response.ok?
  end

  def test_latest
    get "/latest"
    assert last_response.body.include?("<h2>#{Time.now.to_date}</h2>")
    assert last_response.ok?
  end

  def test_list
    get "/list"
    assert last_response.ok?
  end

  def test_user
    get "/user"
    follow_redirect!
    assert_equal "http://example.org/", last_request.url
    assert last_response.ok?
  end
end