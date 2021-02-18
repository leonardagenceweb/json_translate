# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/BlockLength
# rubocop:disable Metrics/CyclomaticComplexity
# rubocop:disable Metrics/PerceivedComplexity

module JSONTranslate
  # Translates module
  module Translates
    SUFFIX = '_translations'.freeze
    MYSQL_ADAPTERS = %w[MySQL Mysql2 Mysql2Spatial].freeze

    def translates(*attrs, allow_blank: false)
      include InstanceMethods

      class_attribute :translated_attribute_names, :permitted_translated_attributes

      self.translated_attribute_names = attrs
      self.permitted_translated_attributes = [
        *self.ancestors
             .select { |klass| klass.respond_to?(:permitted_translated_attributes) }
             .map(&:permitted_translated_attributes),
        *attrs.product(I18n.available_locales)
              .map { |attribute, locale| :"#{attribute}_#{locale}" }
      ].flatten.compact

      attrs.each do |attr_name|
        define_method attr_name do |**params|
          read_json_translation(attr_name, **params)
        end

        define_method "#{attr_name}=" do |value|
          write_json_translation(attr_name, value, allow_blank: allow_blank)
        end

        I18n.available_locales.each do |locale|
          normalized_locale = locale.to_s.downcase.gsub(/[^a-z]/, '')

          define_method :"#{attr_name}_#{normalized_locale}" do |**params|
            read_json_translation(attr_name, locale, false, **params)
          end

          define_method "#{attr_name}_#{normalized_locale}=" do |value|
            write_json_translation(attr_name, value, locale, allow_blank: allow_blank)
          end
        end

        define_singleton_method "with_#{attr_name}_translation" do |value, locale = I18n.locale|
          quoted_translation_store = connection.quote_column_name("#{attr_name}#{SUFFIX}")
          translation_hash = { locale.to_s => value }

          if MYSQL_ADAPTERS.include?(connection.adapter_name)
            where("JSON_CONTAINS(#{quoted_translation_store}, :translation, '$')", translation: translation_hash.to_json)
          else
            where("#{quoted_translation_store} @> :translation::jsonb", translation: translation_hash.to_json)
          end
        end

        # Methods added since the repo fork.
        define_singleton_method "search_#{attr_name}_translation" do |value, locale = I18n.locale|
          quoted_translation_store = connection.quote_column_name("#{attr_name}#{SUFFIX}")
          query_params = { path: "$.\"#{locale}\"", val: "%#{value}%" }

          if MYSQL_ADAPTERS.include?(connection.adapter_name)
            return where("CAST(#{quoted_translation_store}->>:path as CHAR) LIKE :val", query_params) unless enabled_fallback

            where("CAST(IF(JSON_CONTAINS_PATH(#{quoted_translation_store}, 'one', :path),
                #{quoted_translation_store}->>:path,
                JSON_UNQUOTE(JSON_EXTRACT(JSON_EXTRACT(#{quoted_translation_store},'$[0].*'),'$[0]')) # Fetch the first value, could be better
              ) as CHAR) LIKE :val", query_params)
          else
            # TODO: add compatibility to PostgreSQL
            raise NotImplementedError
          end
        end

        define_singleton_method "order_#{attr_name}_translation" do |order = :asc, locale = I18n.locale|
          quoted_translation_store = connection.quote_column_name("#{attr_name}#{SUFFIX}")

          if MYSQL_ADAPTERS.include?(connection.adapter_name)
            order(Arel.sql("#{quoted_translation_store}->>'$.\"#{locale}\"' #{order.upcase},
              JSON_UNQUOTE(JSON_EXTRACT(JSON_EXTRACT(name_translations,'$[0].*'),'$[0]')) #{order.upcase}")) # Fetch the first value, could be better
          else
            # TODO: add compatibility to PostgreSQL
            raise NotImplementedError
          end
        end
      end
    end

    def translates?
      included_modules.include?(InstanceMethods)
    end
  end
end
