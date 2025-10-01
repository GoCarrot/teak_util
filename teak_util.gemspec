# frozen_string_literal: true

require_relative "lib/teak_util/version"

Gem::Specification.new do |spec|
  spec.name          = "teak_util"
  spec.version       = TeakUtil::VERSION
  spec.authors       = ["Alex Scarborough"]
  spec.email         = ["alex@teak.io"]

  spec.summary       = "A collection of utilities used by multiple projects at Teak"
  spec.homepage      = "https://github.com/GoCarrot/teak_util"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.5.0")

  spec.license = "Apache-2.0"

  spec.metadata["rubygems_mfa_required"] = "true"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/GoCarrot/teak_util"
  spec.metadata["changelog_uri"] = "https://github.com/GoCarrot/teak_util/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "aws-sdk-s3", ">= 1.102"
  spec.add_dependency "business_flow", ">= 0.18.0"
  spec.add_dependency "mime-types", ">= 3"
  spec.add_dependency "rubyzip", ">= 2.3", "< 3.0"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
