# frozen_string_literal: true

module Issuer
  module Sites
    class Factory
      SUPPORTED_SITES = {
        'github' => 'Issuer::Sites::GitHub'
      }.freeze

      def self.create site_name, **options
        site_name = site_name.to_s.downcase

        unless SUPPORTED_SITES.key?(site_name)
          available = SUPPORTED_SITES.keys.join(', ')
          raise Issuer::Error, "Unsupported site '#{site_name}'. Available sites: #{available}"
        end

        site_class = Object.const_get(SUPPORTED_SITES[site_name])
        site_class.new(**options)
      end

      def self.supported_sites
        SUPPORTED_SITES.keys
      end

      def self.default_site
        'github'
      end
    end
  end
end
