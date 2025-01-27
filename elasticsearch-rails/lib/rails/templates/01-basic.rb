# Licensed to Elasticsearch B.V. under one or more contributor
# license agreements. See the NOTICE file distributed with
# this work for additional information regarding copyright
# ownership. Elasticsearch B.V. licenses this file to you under
# the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#	http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# =====================================================================================================
# Template for generating a no-frills Rails application with support for Elasticsearch full-text search
# =====================================================================================================
#
# This file creates a basic, fully working Rails application with support for Elasticsearch full-text
# search via the `elasticsearch-rails` gem; https://github.com/elasticsearch/elasticsearch-rails.
#
# Requirements:
# -------------
#
# * Git
# * Ruby  >= 1.9.3
# * Rails >= 5
#
# Usage:
# ------
#
#     $ rails new searchapp --skip --skip-bundle --template https://raw.github.com/elasticsearch/elasticsearch-rails/master/elasticsearch-rails/lib/rails/templates/01-basic.rb
#
# =====================================================================================================

require 'uri'
require 'net/http'
require 'json'

$elasticsearch_url = ENV.fetch('ELASTICSEARCH_URL', 'http://localhost:9200')

# ----- Check for Elasticsearch -------------------------------------------------------------------

required_elasticsearch_version = '7'

docker_command =<<-CMD.gsub(/\s{1,}/, ' ').strip
  docker run \
    --name elasticsearch-rails-searchapp \
    --publish 9200:9200 \
    --env "discovery.type=single-node" \
    --env "cluster.name=elasticsearch-rails" \
    --env "cluster.routing.allocation.disk.threshold_enabled=false" \
    --rm \
    docker.elastic.co/elasticsearch/elasticsearch-oss:7.6.0
CMD

begin
  cluster_info = Net::HTTP.get(URI.parse($elasticsearch_url))
rescue Errno::ECONNREFUSED => e
  say_status "ERROR", "Cannot connect to Elasticsearch on <#{$elasticsearch_url}>\n\n", :red
  say_status "", "The application requires an Elasticsearch cluster running, " +
                 "but no cluster has been found on <#{$elasticsearch_url}>."
  say_status "", "The easiest way of launching Elasticsearch is by running it with Docker (https://www.docker.com/get-docker):\n\n"
  say_status "", docker_command + "\n"
  exit(1)
rescue StandardError => e
  say_status "ERROR", "#{e.class}: #{e.message}", :red
  exit(1)
end

cluster_info = JSON.parse(cluster_info)

unless cluster_info['version']
  say_status "ERROR", "Cannot determine Elasticsearch version from <#{$elasticsearch_url}>", :red
  say_status "", JSON.dump(cluster_info), :red
  exit(1)
end

if cluster_info['version']['number'] < required_elasticsearch_version
  say_status "ERROR",
             "The application requires Elasticsearch version #{required_elasticsearch_version} or higher, found version #{cluster_info['version']['number']}.\n\n", :red
  say_status "", "The easiest way of launching Elasticsearch is by running it with Docker (https://www.docker.com/get-docker):\n\n"
  say_status "", docker_command + "\n"
  exit(1)
end

# ----- Application skeleton ----------------------------------------------------------------------

run "touch tmp/.gitignore"

append_to_file ".gitignore", "vendor/elasticsearch-5.2.1/\n"

git :init
git add:    "."
git commit: "-m 'Initial commit: Clean application'"

# ----- Add README --------------------------------------------------------------------------------

puts
say_status  "README", "Adding Readme...\n", :yellow
puts        '-'*80, ''; sleep 0.25

remove_file 'README.md'

create_file 'README.md', <<-README
# Ruby on Rails and Elasticsearch: Example application

This application is an example of integrating the {Elasticsearch}[https://www.elastic.co]
search engine with the {Ruby On Rails}[http://rubyonrails.org] web framework.

It has been generated by application templates available at
https://github.com/elasticsearch/elasticsearch-rails/tree/master/elasticsearch-rails/lib/rails/templates.

## [1] Basic

The `basic` version provides a simple integration for a simple Rails model, `Article`, showing how
to include the search engine support in your model, automatically index changes to records,
and use a form to perform simple search require 'requests.'

README


git add:    "."
git commit: "-m '[01] Added README for the application'"

# ----- Use Thin ----------------------------------------------------------------------------------

begin
  require 'thin'
  puts
  say_status  "Rubygems", "Adding Thin into Gemfile...\n", :yellow
  puts        '-'*80, '';

  gem 'thin'
rescue LoadError
end

# ----- Auxiliary gems ----------------------------------------------------------------------------

gem 'mocha', group: 'test'
gem 'rails-controller-testing', group: 'test'

# ----- Remove CoffeeScript, Sass and "all that jazz" ---------------------------------------------

comment_lines 'Gemfile', /gem 'coffee/
comment_lines 'Gemfile', /gem 'sass/
comment_lines 'Gemfile', /gem 'uglifier/
uncomment_lines 'Gemfile', /gem 'therubyracer/

# ----- Add gems into Gemfile ---------------------------------------------------------------------

puts
say_status  "Rubygems", "Adding Elasticsearch libraries into Gemfile...\n", :yellow
puts        '-'*80, ''; sleep 0.75

gem 'elasticsearch'
gem 'elasticsearch-model', git: 'https://github.com/elasticsearch/elasticsearch-rails.git'
gem 'elasticsearch-rails', git: 'https://github.com/elasticsearch/elasticsearch-rails.git'


git add:    "Gemfile*"
git commit: "-m 'Added libraries into Gemfile'"

# ----- Disable asset logging in development ------------------------------------------------------

puts
say_status  "Application", "Disabling asset logging in development...\n", :yellow
puts        '-'*80, ''; sleep 0.25

environment 'config.assets.logger = false', env: 'development'
environment 'config.assets.quiet  = true',  env: 'development'

git add:    "config/"
git commit: "-m 'Disabled asset logging in development'"

# ----- Install gems ------------------------------------------------------------------------------

puts
say_status  "Rubygems", "Installing Rubygems...", :yellow
puts        '-'*80, ''

run "bundle install"

# ----- Generate Article resource -----------------------------------------------------------------

puts
say_status  "Model", "Generating the Article resource...", :yellow
puts        '-'*80, ''; sleep 0.75

generate :scaffold, "Article title:string content:text published_on:date"
route "root to: 'articles#index'"
rake  "db:migrate"

git add:    "."
git commit: "-m 'Added the generated Article resource'"

# ----- Add Elasticsearch integration into the model ----------------------------------------------

puts
say_status  "Model", "Adding search support into the Article model...", :yellow
puts        '-'*80, ''; sleep 0.25

run "rm -f app/models/article.rb"
file 'app/models/article.rb', <<-CODE
class Article < ActiveRecord::Base
  include Elasticsearch::Model
  include Elasticsearch::Model::Callbacks
  #{'attr_accessible :title, :content, :published_on' if Rails::VERSION::STRING < '4'}
end
CODE

git commit: "-a -m 'Added Elasticsearch support into the Article model'"

# ----- Add Elasticsearch integration into the interface ------------------------------------------

puts
say_status  "Controller", "Adding controller action, route, and HTML for searching...", :yellow
puts        '-'*80, ''; sleep 0.25

inject_into_file 'app/controllers/articles_controller.rb', before: %r|^\s*# GET /articles/1$| do
  <<-CODE

  # GET /articles/search
  def search
    @articles = Article.search(params[:q]).records

    render action: "index"
  end

  CODE
end

inject_into_file 'app/views/articles/index.html.erb', after: %r{<h1>.*Articles</h1>}i do
  <<-CODE


  <hr>

  <%= form_tag search_articles_path, method: 'get' do %>
    <%= label_tag :query %>
    <%= text_field_tag :q, params[:q] %>
    <%= submit_tag :search %>
  <% end %>

  <hr>
  CODE
end

inject_into_file 'app/views/articles/index.html.erb', after: %r{<%= link_to 'New Article', new_article_path %>} do
  <<-CODE
  <%= link_to 'All Articles', articles_path if params[:q] %>
  CODE
end

gsub_file 'config/routes.rb', %r{resources :articles$}, <<-CODE
resources :articles do
    collection { get :search }
  end
CODE

gsub_file "test/controllers/articles_controller_test.rb", %r{setup do.*?end}m, <<-CODE
setup do
    @article = articles(:one)

    Article.__elasticsearch__.import force: true
    Article.__elasticsearch__.refresh_index!
  end
CODE

inject_into_file "test/controllers/articles_controller_test.rb", after: %r{test "should get index" do.*?end}m do
  <<-CODE


  test "should get search results" do
    #{ Rails::VERSION::STRING > '5' ? 'get search_articles_url(q: "mystring")' : 'get :search, q: "mystring"' }
    assert_response :success
    assert_not_nil assigns(:articles)
    assert_equal 2, assigns(:articles).size
  end
  CODE
end

git commit: "-a -m 'Added search form and controller action'"

# ----- Seed the database -------------------------------------------------------------------------

puts
say_status  "Database", "Seeding the database with data...", :yellow
puts        '-'*80, ''; sleep 0.25

remove_file "db/seeds.rb"
create_file 'db/seeds.rb', %q{
contents = [
'Lorem ipsum dolor sit amet.',
'Consectetur adipisicing elit, sed do eiusmod tempor incididunt.',
'Labore et dolore magna aliqua.',
'Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.',
'Excepteur sint occaecat cupidatat non proident.'
]

puts "Deleting all articles..."
Article.delete_all

unless ENV['COUNT']

  puts "Creating articles..."
  %w[ One Two Three Four Five ].each_with_index do |title, i|
    Article.create title: title, content: contents[i], published_on: i.days.ago.utc
  end

else

  print "Generating articles..."
  (1..ENV['COUNT'].to_i).each_with_index do |title, i|
    Article.create title: "Title #{title}", content: 'Lorem ipsum dolor', published_on: i.days.ago.utc
    print '.' if i % ENV['COUNT'].to_i/10 == 0
  end
  puts "\n"

end
}

run  "rails runner 'Article.__elasticsearch__.create_index! force: true'"
rake "db:seed"

git add:    "db/seeds.rb"
git commit: "-m 'Added the database seeding script'"

# ----- Print Git log -----------------------------------------------------------------------------

puts
say_status  "Git", "Details about the application:", :yellow
puts        '-'*80, ''

git tag: "basic"
git log: "--reverse --oneline"

# ----- Install Webpacker -------------------------------------------------------------------------

run 'rails webpacker:install'

# ----- Start the application ---------------------------------------------------------------------

unless ENV['RAILS_NO_SERVER_START']
  require 'net/http'
  if (begin; Net::HTTP.get(URI('http://localhost:3000')); rescue Errno::ECONNREFUSED; false; rescue Exception; true; end)
    puts        "\n"
    say_status  "ERROR", "Some other application is running on port 3000!\n", :red
    puts        '-'*80

    port = ask("Please provide free port:", :bold)
  else
    port = '3000'
  end

  puts  "", "="*80
  say_status  "DONE", "\e[1mStarting the application.\e[0m", :yellow
  puts  "="*80, ""

  run  "rails server --port=#{port}"
end
