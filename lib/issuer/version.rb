# frozen_string_literal: true

module Issuer
  unless defined?(VERSION)
    # Read version from README.adoc (source repo only)
    readme_path = File.join(File.dirname(__FILE__), '..', '..', 'README.adoc')
    
    if File.exist?(readme_path)
      # Parse README.adoc to find :this_prod_vrsn: attribute
      File.foreach(readme_path) do |line|
        if line.match(/^:this_prod_vrsn:\s*(.+)$/)
          VERSION = $1.strip
          break
        end
      end
    end
    
    # Fallback if README.adoc not found or version not found
    VERSION ||= '0.0.0'
  end
end
