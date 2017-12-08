
require_relative 'lib/meeco-client-version.rb'

Gem::Specification.new do |spec|
  spec.name = 'meeco-client'
  spec.version = Meeco::Client::VERSION

  spec.summary = 'A collection of classes used to interact with the Meeco API'
  spec.homepage = 'https://github.com/Meeco/meeco-client'
  spec.email = 'developers@meeco.me'

  spec.authors = [
      'Brent Jacobs',
      'Jeff Cressman',
      "Jared O'Conner",
      'Andrew Williams',
      'Graham Towse',
      'Meeco',
      'NextFaze'
    ]

  spec.files = [
      'lib/meeco-client.rb',
    ]

  spec.required_ruby_version = '~> 2.0'
  spec.add_dependency 'rest-client', '~> 2.0'
end
