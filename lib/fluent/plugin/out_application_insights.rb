# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

require 'json'
require 'fluent/plugin/output'
require 'application_insights'

module Fluent::Plugin
  class ApplicationInsightsOutput < Output
    Fluent::Plugin.register_output("application_insights", self)

    attr_accessor :tc

    helpers :record_accessor

    # The Application Insights instrumentation key
    config_param :instrumentation_key, :string
    # The service endpoint uri to push the telemetry to
    config_param :service_endpoint_uri, :string, default: nil
    # The batch size to send data to Application Insights service.
    config_param :send_buffer_size, :integer, default: 1000
    # The parameter indication whether the record is in standard schema. i.e., the format that is recognized by Application Insights backend.
    config_param :standard_schema, :bool, default: false
    # The property name for the message. It will be ignored if the record is in standard schema.
    config_param :message_property, :string, default: 'message'
    # The property name for the timestamp. It will be ignored if the record is in standard schema.
    config_param :time_property, :string, default: nil
    # The property name for severity level. It will be ignored if the record is in standard schema.
    config_param :severity_property, :string, default: 'severity'
    # The value of severity property that maps to Application Insights' verbose severity level.
    config_param :severity_level_verbose, :array, value_type: :string, default: ['verbose']
    # The value of severity property that maps to Application Insights' information severity level.
    config_param :severity_level_information, :array, value_type: :string, default: ['information']
    # The value of severity property that maps to Application Insights' warning severity level.
    config_param :severity_level_warning, :array, value_type: :string, default: ['warning']
    # The value of severity property that maps to Application Insights' error severity level.
    config_param :severity_level_error, :array, value_type: :string, default: ['error']
    # The value of severity property that maps to Application Insights' critical severity level.
    config_param :severity_level_critical, :array, value_type: :string, default: ['critical']
    # The dictionary that instructs the Application Insights plugin to set Application Insights context tags using record properties.
    # In this dictionary keys are Application Insights context tags to set, and values are names of properties to use as source of data.
    config_param :context_tag_sources, :hash, default: {}, value_type: :string

    TELEMETRY_TYPES = ["RequestData", "RemoteDependencyData", "MessageData", "ExceptionData", "EventData", "MetricData", "PageViewData", "AvailabilityData"]

    def configure(conf)
      super

      @severity_level_mapping = {}
      @severity_level_verbose.each { |l| @severity_level_mapping[l.downcase] = Channel::Contracts::SeverityLevel::VERBOSE }
      @severity_level_information.each { |l| @severity_level_mapping[l.downcase] = Channel::Contracts::SeverityLevel::INFORMATION }
      @severity_level_warning.each { |l| @severity_level_mapping[l.downcase] = Channel::Contracts::SeverityLevel::WARNING }
      @severity_level_error.each { |l| @severity_level_mapping[l.downcase] = Channel::Contracts::SeverityLevel::ERROR }
      @severity_level_critical.each { |l| @severity_level_mapping[l.downcase] = Channel::Contracts::SeverityLevel::CRITICAL }

      context_tag_keys = []
      context_tag_keys.concat Channel::Contracts::Application.json_mappings.values
      context_tag_keys.concat Channel::Contracts::Cloud.json_mappings.values
      context_tag_keys.concat Channel::Contracts::Device.json_mappings.values
      context_tag_keys.concat Channel::Contracts::Internal.json_mappings.values
      context_tag_keys.concat Channel::Contracts::Location.json_mappings.values
      context_tag_keys.concat Channel::Contracts::Operation.json_mappings.values
      context_tag_keys.concat Channel::Contracts::Session.json_mappings.values
      context_tag_keys.concat Channel::Contracts::User.json_mappings.values

      @context_tag_accessors = {}
      context_tag_sources.each do |tag, property_path|
        raise ArgumentError.new("Context tag '#{tag}' is invalid!") unless context_tag_keys.include?(tag)

        @context_tag_accessors[tag] = record_accessor_create(property_path)
      end
    end

    def start
      super

      sender = Channel::AsynchronousSender.new if @service_endpoint_uri.nil? else Channel::AsynchronousSender.new @service_endpoint_uri
      queue = Channel::AsynchronousQueue.new sender
      channel = Channel::TelemetryChannel.new nil, queue
      @tc = TelemetryClient.new @instrumentation_key, channel
      @tc.channel.queue.max_queue_length = @send_buffer_size
      @tc.channel.sender.send_buffer_size = @send_buffer_size
    end

    def shutdown
      super

      # Draining the events in the queue.
      # We need to make sure the work thread has finished. Otherwise, it's possible that the queue is empty, but the http request to send the data is not finished.
      # However, a drawback of waiting for the work thread to finish is that even if the events have been drained, it will still poll the queue for some time (default is 3 seconds, set by sender.send_time).
      # This can be improved if the SDK exposes another variable indicating whether the work thread is sending data or just polling the queue.
      while !@tc.channel.queue.empty? || @tc.channel.sender.work_thread != nil
        # It's possible that the work thread has already exited but there are still items in the queue.
        # https://github.com/Microsoft/ApplicationInsights-Ruby/blob/master/lib/application_insights/channel/asynchronous_sender.rb#L115
        # Trigger flush to make the work thread working again in this case.
        if @tc.channel.sender.work_thread == nil && !@tc.channel.queue.empty?
          @tc.flush
        end

        sleep(1)
      end
    end

    def process(tag, es)
      es.each do |time, record|
        # 'time' is a Fluent::EventTime object or an Integer. Convert it to ruby Time object.
        time_ruby = time.is_a?(Fluent::EventTime) ? Time.at(time.sec, time.nsec / 1000).utc : Time.at(time)
        if @standard_schema
          process_standard_schema_log record, time_ruby
        else
          process_non_standard_schema_log record, time_ruby
        end
      end
    end

    def process_standard_schema_log(record, time)
      if record["data"] && record["data"].is_a?(Hash) && record["data"]["baseType"] && record["data"]["baseData"]
        base_type = record["data"]["baseType"]

        if TELEMETRY_TYPES.include? base_type
          # If the record is processed by json parser plugin, e.g., in_http use it by default, the time property will be removed. Add it back in this case.
          record["time"] ||= time.iso8601(7)
          record["iKey"] = @instrumentation_key
          set_name_property(record) if !record["name"]
          set_context_standard_schema record

          envelope = Channel::Contracts::Envelope.new
          Channel::Contracts::Envelope.json_mappings.each do |attr, name|
            property = record.delete(name)
            envelope.send(:"#{attr}=", property) if property
          end

          # There could be extra properties added during the fluentd pipeline. Merge the extra properties so they are not lost.
          merge_extra_properties_standard_schema record, envelope

          @tc.channel.queue.push(envelope)
        else
          log.debug "Unknown telemetry type #{base_type}. Event will be treated as as non standard schema event."
          process_non_standard_schema_log record, time
        end
      else
        log.debug "The event does not meet the standard schema of Application Insights output. Missing data, baseType or baseData property. Event will be treated as as non standard schema event."
        process_non_standard_schema_log record, time
      end
    end

    def set_name_property(record)
      normalizedIKey = @instrumentation_key.gsub("-", "")
      normalizedIKey = normalizedIKey.empty? ? "" : normalizedIKey + "."
      type = record["data"]["baseType"][0..-5]
      record["name"] = "Microsoft.ApplicationInsights.#{normalizedIKey}#{type}"
    end

    def set_context_standard_schema(record)
      return if @context_tag_sources.length == 0

      record["tags"] = record["tags"] || {}
      @context_tag_accessors.each do |tag, accessor|
        tag_value = accessor.call(record)
        record["tags"][tag] = tag_value if !tag_value.nil?
      end
    end

    def merge_extra_properties_standard_schema(record, envelope)
      return if record.empty?

      envelope.data["baseData"]["properties"] ||= {}
      envelope.data["baseData"]["properties"].merge!(record)
      stringify_properties(envelope.data["baseData"]["properties"])
    end

    def process_non_standard_schema_log(record, time)
      time = record.delete(@time_property) || time
      context = get_context_non_standard_schema(record)
      message = record.delete @message_property
      severity_level_value = record.delete @severity_property
      severity_level = severity_level_value ? @severity_level_mapping[severity_level_value.to_s.downcase] : nil
      props = stringify_properties(record)

      data = Channel::Contracts::MessageData.new(
        :message => message || 'Null',
        :severity_level => severity_level || Channel::Contracts::SeverityLevel::INFORMATION,
        :properties => props || {}
      )

      @tc.channel.write(data, context, time)
    end

    def get_context_non_standard_schema(record)
      context = Channel::TelemetryContext.new
      context.instrumentation_key = @instrumentation_key
      return context if @context_tag_sources.length == 0

      @context_tag_accessors.each do |tag, accessor|
        set_context_tag context, tag, accessor.call(record)
      end

      return context
    end

    def set_context_tag(context, tag_name, tag_value)
      return if tag_value.nil?

      context_set = [context.application, context.cloud, context.device, context.location, context.operation, context.session, context.user]
      context_set.each do |c|
        c.class.json_mappings.each do |attr, name|
          if (name == tag_name)
            c.send(:"#{attr}=", tag_value)
            return
          end
        end
      end
    end

    def stringify_properties(record)
      # If the property value is a json object or array, e.g., {"prop": {"inner_prop": value}}, it needs to be serialized.
      # Otherwise, the property will become {"prop": "[object Object]"} in the final telemetry.
      # The stringified property can be queried as described here: https://docs.loganalytics.io/docs/Language-Reference/Scalar-functions/parse_json()
      record.each do |key, value|
        if value.is_a?(Hash) || value.is_a?(Array)
          record[key] = JSON.generate(value)
        end
      end
      record
    end

  end
end
