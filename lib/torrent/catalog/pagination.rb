# frozen_string_literal: true

module Torrent
  module Catalog
    class Pagination
      PER_PAGE = 20

      def self.calculate(total, page)
        total_pages = (total.to_f / PER_PAGE).ceil
        start_idx = (page - 1) * PER_PAGE
        end_idx = [start_idx + PER_PAGE, total].min
        [start_idx, end_idx, total_pages]
      end

      def self.get_page_from_env
        (ENV['CATALOG_PAGE'] || '1').to_i
      end
    end
  end
end
