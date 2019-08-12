lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name    = "fluent-plugin-application-insights"
  spec.version = "0.2.4"
  spec.authors = ["Microsoft Corporation"]
  spec.email   = ["azure-tools@microsoft.com"]

  spec.summary       = "This is the fluentd output plugin for Azure Application Insights."
  spec.description   = "Fluentd output plugin for Azure Application Insights."

  spec.homepage      = "https://github.com/Microsoft/fluent-plugin-application-insights"
  spec.license       = "MIT"

  test_files, files  = `git ls-files -z`.split("\x0").partition do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.files         = files.push('lib/fluent/plugin/out_application_insights.rb')
  spec.executables   = files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = test_files
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.14"
  spec.add_development_dependency "rake", "~> 12.0"
  spec.add_development_dependency "test-unit", "~> 3.0"
  spec.add_runtime_dependency "fluentd", [">= 1.0", "< 2"]
  spec.add_runtime_dependency "application_insights", "~> 0.5.5"
end
