# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

require 'json'
require 'fluent/plugin/output'
require 'application_insights'

module Fluent::Plugin
  class ApplicationInsightsOutput < Output
    Fluent::Plugin.register_output("application_insights", self)

    attr_accessor :tc

    # The Application Insights instrumentation key
    config_param :instrumentation_key, :string
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
    config_param :severity_level_verbose, :string, default: 'verbose'
    # The value of severity property that maps to Application Insights' information severity level.
    config_param :severity_level_information, :string, default: 'information'
    # The value of severity property that maps to Application Insights' warning severity level.
    config_param :severity_level_warning, :string, default: 'warning'
    # The value of severity property that maps to Application Insights' error severity level.
    config_param :severity_level_error, :string, default: 'error'
    # The value of severity property that maps to Application Insights' critical severity level.
    config_param :severity_level_critical, :string, default: 'critical'
    # The dictionary that instructs the Application Insights plugin to set Application Insights context tags using record properties.
    # In this dictionary keys are Application Insights context tags to set, and values are names of properties to use as source of data.
    config_param :context_tag_sources, :hash, default: {}, value_type: :string

    TELEMETRY_TYPES = ["RequestData", "RemoteDependencyData", "MessageData", "ExceptionData", "EventData", "MetricData", "PageViewData", "AvailabilityData"]

    def configure(conf)
      super

      @severity_level_mapping = {}
      @severity_level_mapping[@severity_level_verbose.downcase] = Channel::Contracts::SeverityLevel::VERBOSE
      @severity_level_mapping[@severity_level_information.downcase] = Channel::Contracts::SeverityLevel::INFORMATION
      @severity_level_mapping[@severity_level_warning.downcase] = Channel::Contracts::SeverityLevel::WARNING
      @severity_level_mapping[@severity_level_error.downcase] = Channel::Contracts::SeverityLevel::ERROR
      @severity_level_mapping[@severity_level_critical.downcase] = Channel::Contracts::SeverityLevel::CRITICAL

      context_tag_keys = []
      context_tag_keys.concat Channel::Contracts::Application.json_mappings.values
      context_tag_keys.concat Channel::Contracts::Cloud.json_mappings.values
      context_tag_keys.concat Channel::Contracts::Device.json_mappings.values
      context_tag_keys.concat Channel::Contracts::Internal.json_mappings.values
      context_tag_keys.concat Channel::Contracts::Location.json_mappings.values
      context_tag_keys.concat Channel::Contracts::Operation.json_mappings.values
      context_tag_keys.concat Channel::Contracts::Session.json_mappings.values
      context_tag_keys.concat Channel::Contracts::User.json_mappings.values

      context_tag_sources.keys.each do |tag|
        raise ArgumentError.new("Context tag '#{tag}' is invalid!") unless context_tag_keys.include?(tag)
      end
    end

    def start
      super

      sender = Channel::AsynchronousSender.new
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
        # Convert the fluentd EventTime object to ruby Time object
        time_ruby = Time.at(time.sec, time.nsec / 1000).utc
        if @standard_schema
          process_standard_schema_log record, time_ruby
        else
          process_non_standard_schema_log record, time_ruby
        end
      end
    end

    def process_standard_schema_log(record, time)
      if record["name"] && record["data"] && record["data"].is_a?(Hash) && record["data"]["baseType"] && record["data"]["baseData"]
        base_type = record["data"]["baseType"]

        if TELEMETRY_TYPES.include? base_type
          # If the record is processed by json parser plugin, e.g., in_http use it by default, the time property will be removed. Add it back in this case.
          record["time"] ||= time.iso8601(7)
          record["iKey"] = @instrumentation_key
          set_context_standard_schema record

          envelope = Channel::Contracts::Envelope.new
          Channel::Contracts::Envelope.json_mappings.each do |attr, name|
            envelope.send(:"#{attr}=", record[name]) if record[name]
          end

          @tc.channel.queue.push(envelope)
        else
          log.warn "Unknown telemetry type #{base_type}. Event will be treated as as non standard schema event."
          process_non_standard_schema_log record, time
        end
      else
        log.warn "The event does not meet the standard schema of Application Insights output. Missing name, data, baseType or baseData property. Event will be treated as as non standard schema event."
        process_non_standard_schema_log record, time
      end
    end

    def set_context_standard_schema(record)
      return if @context_tag_sources.length == 0

      record["tags"] = record["tags"] || {}
      @context_tag_sources.each do |context_tag, source_property|
        context_value = record.delete source_property
        record["tags"][context_tag] = context_value if context_value
      end
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

      @context_tag_sources.each do |context_tag, source_property|
        if record[source_property]
          set_context_tag context, context_tag, record[source_property]
        end
      end

      return context
    end

    def set_context_tag(context, tag_name, tag_value)
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
