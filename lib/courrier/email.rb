module Courrier
  class Email
    extend ActiveModel::Callbacks
    define_model_callbacks :initialize, only: :after

    class_attribute :required_keys
    class_attribute :delivery_block
    class_attribute :delivery_keys
    class_attribute :default_delivery_keys
    class_attribute :recipient_method
    class_attribute :email_name
    class_attribute :email_template_name

    self.required_keys = []
    self.delivery_keys = []
    self.delivery_block = nil

    self.default_delivery_keys = [
      :show_call_to_action
    ]

    # Public: Specify an instance method that returns a user
    # or email address to whom the email should be delivered.
    #
    def self.recipient(user_or_email_address)
      self.recipient_method = user_or_email_address
    end

    # Public: Shorthand for requiring a model id and method for
    # retrieving instance of model from db using that id. Though
    # activerecord-inspired, it doesn't support any fancy options.
    #
    def self.belongs_to(*attrs)
      attrs.each do |attribute|
        requires :"#{attribute}_id"

        define_method(attribute) do
          instance_variable_get("@#{attribute}") ||
            instance_variable_set("@#{attribute}",
              attribute.to_s.camelize.constantize.find(send(:"#{attribute}_id")))
        end
      end
    end

    # Public: Specify a required attribute for new instances.
    #
    def self.requires(*attrs)
      self.required_keys += attrs
      attr_reader *attrs
    end

    def self.deliver(*attrs, &block)
      if block_given?
        self.delivery_block = block
      end

      self.delivery_keys += attrs
    end

    def self.email_name
      (self.name || 'Generic').demodulize.underscore.gsub(/_email$/, '')
    end

    def self.email_template_name
      self.email_name
    end

    def self.subclass_by_email_name(email_name)
      "notifier/#{email_name}_email".camelize.constantize
    end

    def recipient
      return Courrier.configuration.interceptor_email if Courrier.configuration.interceptor_email.present?
      method = self.class.recipient_method
      raise Courrier::RecipientUndefinedError.new("Please declare a recipient in #{self.class.name}") if method.nil? || !self.respond_to?(method, true)
      send(method)
    end

    def delivery_attributes
      {}.tap do |attrs|
        if delivery_block
          instance_exec(attrs, &delivery_block)
        end

        delivery_keys.each do |attribute|
          begin
            attrs[attribute] = send(attribute)
          rescue NoMethodError => e
            if respond_to?(attribute)
              raise e
            else
              raise Courrier::DeliveredAttributeError.new("#{self.class.name} #{e}")
            end
          end
        end
      end
    end

    def initialize(attributes = {})
      attrs = attributes.with_indifferent_access
      begin
        required_keys.each do |attribute|
          instance_variable_set("@#{attribute}", attrs.fetch(attribute))
        end
      rescue KeyError => e
        raise Courrier::RequiredAttributeError.new("#{self.class.name} #{e}")
      end

      # Set optional attributes via attr_writer
      attrs.except(*required_keys).each do |key, value|
        self.send("#{key}=", value)
      end

      run_callbacks :initialize
    end

    def payload
      [email_template_name, recipient, delivery_attributes]
    end

    # attributes

    def show_call_to_action
      'false'
    end

    def delivery_keys
      (default_delivery_keys + self.class.delivery_keys).uniq
    end
  end

  class RequiredAttributeError < KeyError; end
  class RecipientUndefinedError < RuntimeError; end
  class DeliveredAttributeError < RuntimeError; end
end
