import 'package:json_annotation/json_annotation.dart';

/// Canonicalizes serialized domain timestamps as UTC ISO-8601 instants.
class UtcDateTimeConverter implements JsonConverter<DateTime, String> {
  const UtcDateTimeConverter();

  @override
  DateTime fromJson(String json) => DateTime.parse(json).toUtc();

  @override
  String toJson(DateTime object) => object.toUtc().toIso8601String();
}
