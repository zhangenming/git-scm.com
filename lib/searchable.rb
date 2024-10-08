# frozen_string_literal: true

module Searchable
  extend ActiveSupport::Concern

  included do
    def self.search(keywords, options = {})
      # TODO: find more OOP solution
      # we should never look to search_type variable again here
      # nor when adding to index
      class_name    = name.to_s.downcase
      search_type   = (class_name == "section" ? "book" : "man_doc")

      type_name     = (search_type == "book" ? "section" : "name")
      category_name = (search_type == "book" ? "Book" : "Reference")
      format        = (search_type == "book" ? "html" : "text")
      query_options = {
        "size" => 10,
        "query" => {
          "bool" => {
            "should" => [],
            "minimum_should_match" => 1
          },
        },
        "highlight" => {
          "pre_tags" => ["[highlight]"],
          "post_tags" => ["[xhighlight]"],
          "fields" => { format => { "fragment_size" => 200 } }
        }
      }
      lang_options = { "must" => [{ "term" => { "lang" => options[:lang] } }] }
      query_options["query"]["bool"].merge!(lang_options) if options[:lang].present?

      keywords.split(/\s|-/).each do |keyword|
        query_options["query"]["bool"]["should"] << { "prefix" => { type_name => { "value" => keyword,
                                                                                   "boost" => 12.0 } } }
        query_options["query"]["bool"]["should"] << { "term" => { format => keyword } }
      end

      client = ElasticClient.instance
      search = begin
        client.search index: ELASTIC_SEARCH_INDEX, body: query_options
      rescue StandardError
        nil
      end

      if search
        ref_hits = []
        results = begin
          search["hits"]["hits"]
        rescue StandardError
          []
        end
        results.each do |result|
          source = result["_source"]
          name = source["section"] || source["chapter"] || source["name"]
          slug = result["_id"].gsub("---", "/")
          highlight = if search_type == "book"
                        begin
                          result["highlight"]["html"].first
                        rescue StandardError
                          nil
                        end
                      else
                        begin
                          result["highlight"]["text"].first
                        rescue StandardError
                          nil
                        end
                      end
          hit = {
            name: name,
            score: result["_score"],
            highlight: highlight,
            url: (search_type == "book" ? "/book/#{slug}" : "/docs/#{name}")
          }
          ref_hits << hit
        end
        if !ref_hits.empty?
          { category: category_name, term: keywords, matches: ref_hits }
        end
      end
    end
  end
end
