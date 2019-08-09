# [UNSUPPORTED] fluent-plugin-application-insights

[![Gem Version](https://badge.fury.io/rb/fluent-plugin-application-insights.svg)](https://badge.fury.io/rb/fluent-plugin-application-insights)
[![Build Status](https://travis-ci.org/Microsoft/fluent-plugin-application-insights.svg?branch=master)](https://travis-ci.org/Microsoft/fluent-plugin-application-insights)

This is the [Fluentd](https://fluentd.org/) output plugin for [Azure Application Insights](https://docs.microsoft.com/azure/application-insights/)

Application Insights is an extensible Application Performance Management (APM) service for web developers on multiple platforms.
Use it to monitor your live web application. It will automatically detect performance anomalies. It includes powerful analytics
tools to help you diagnose issues and to understand what users actually do with your app.
It's designed to help you continuously improve performance and usability.

## Installation

```
$ gem install fluent-plugin-application-insights
```

## Configuration

To send data to Application Insights, add the following piece to your fluentd configuration file:

```
<match **>
  @type application_insights
  instrumentation_key <your instrumentation key>
</match>
```

Here is the configuration options for this plugin:

* `instrumentation_key` - Required, the Application Insights instrumentation key
* `send_buffer_size` - The batch size to send data to Application Insights service (default `1000`). Setting this to a large size will usually result in better output throughput.
* `standard_schema` - The parameter indicating whether the record is in standard schema. i.e., the format that is recognized by Application Insights backend (default `false`).
If the record is not in standard schema, it will be tracked as Application Insights trace telemetry. Otherwise, the record is just forwarded to the backend. See [Standard Schema](#standard-schema) for more info.
* `message_property` - The property name for the trace message (default `message`).
* `time_property` - The property name for the timestamp (default `nil`).  
    Fluentd input plugin will assign a timestamp for each emitted record, and this timestamp is used as the telemetry creation time by default. Set the `time_property` if you want to use the value of this property instead of the one assigned by the input plugin.
* `severity_property` - The property name for severity level (default `severity`). If the severity property doesn't exist, the record will be treated as information level. See [Severity Level](https://docs.microsoft.com/azure/application-insights/application-insights-data-model-trace-telemetry#severity-level) for more info.
* `severity_level_verbose` - The value of severity property that maps to Application Insights' verbose severity level (default `verbose`).
* `severity_level_information` - The value of severity property that maps to Application Insights' information severity level (default `information`).
* `severity_level_warning` - The value of severity property that maps to Application Insights' warning severity level (default `warning`).
* `severity_level_error` - The value of severity property that maps to Application Insights' error severity level (default `error`).
* `severity_level_critical` - The value of severity property that maps to Application Insights' critical severity level (default `critical`).
* `context_tag_sources` - The dictionary that instructs the Application Insights plugin to set Application Insights context tags using record properties.  
    In this dictionary keys are Application Insights context tags to set, and values are the source properties that are used to set the context tags value. For the source property, you can specify the property name or jsonpath like syntax for nested property, see [record_accessor syntax](https://docs.fluentd.org/v1.0/articles/api-plugin-helper-record_accessor#syntax) for more info. For example:
    ```
    context_tag_sources {
      "ai.cloud.role": "kubernetes_container_name",
      "ai.cloud.roleInstance": "$.docker.container_id"
    }
    ```
    Here is the list of all [context tag keys](https://github.com/Microsoft/ApplicationInsights-dotnet/blob/develop/Schema/PublicSchema/ContextTagKeys.bond)

## Standard Schema

The standard schema for Application Insights telemetry is defined [here](https://github.com/Microsoft/ApplicationInsights-Home/tree/master/EndpointSpecs/Schemas/Bond).

Below is an example of a Request telemetry in standard schema format. `data`, `data.baseType` and `data.baseData` are required properties. Different telemetry types will have different properties associated with the `baseData` object.

```
{
  "name": "Microsoft.ApplicationInsights.Request",
  "time": "2018-02-28T00:24:00.5676240Z",
  "tags":{
    "ai.cloud.role": "webfront",
    "ai.cloud.roleInstance":"85a1e424491d07b6c1ed032f"
  },
  "data": {
    "baseType": "RequestData",
    "baseData": {
      "ver":2,
      "id":"|85a1e424-491d07b6c1ed032f.",
      "name":"PUT Flights/StartNewFlightAsync",
      "duration":"00:00:01.0782934",
      "success":true,
      "responseCode":"204",
      "url":"http://localhost:5023/api/flights
  }
}
```

## Contributing
Refer to [Contributing Guide](CONTRIBUTING.md).

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
