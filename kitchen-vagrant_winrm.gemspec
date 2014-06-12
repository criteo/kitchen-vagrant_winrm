# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'kitchen/driver/vagrant_winrm_version'

Gem::Specification.new do |spec|
  spec.name          = 'kitchen-vagrant_winrm'
  spec.version       = Kitchen::Driver::VAGRANT_WINRM_VERSION
  spec.authors       = ['Baptiste Courtois']
  spec.email         = ['b.courtois@criteo.com']
  spec.description   = %q{Kitchen::Driver::VagrantWinRM - A Test Kitchen Driver using Vagrant-WinRM}
  spec.summary       = 'A Test Kitchen Driver using vagrant winrm'
  spec.homepage      = 'https://github.com/criteo/kitchen-vagant_winrm'
  spec.license       = 'Apache 2.0'

  spec.files         = `git ls-files`.split($/)
  spec.executables   = []
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'test-kitchen', '>= 1.2.1'

  spec.add_development_dependency 'bundler', '~> 1.3'
  spec.add_development_dependency 'rake'

  spec.add_development_dependency 'cane'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'tailor'
  spec.add_development_dependency 'countloc'
end
