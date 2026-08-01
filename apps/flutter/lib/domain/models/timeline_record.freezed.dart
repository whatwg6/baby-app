// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'timeline_record.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
RecordDetails _$RecordDetailsFromJson(
  Map<String, dynamic> json
) {
        switch (json['runtimeType']) {
                  case 'growth':
          return GrowthDetails.fromJson(
            json
          );
                case 'activity':
          return ActivityDetails.fromJson(
            json
          );
                case 'milestone':
          return MilestoneDetails.fromJson(
            json
          );

          default:
            throw CheckedFromJsonException(
  json,
  'runtimeType',
  'RecordDetails',
  'Invalid union type "${json['runtimeType']}"!'
);
        }

}

/// @nodoc
mixin _$RecordDetails {



  /// Serializes this RecordDetails to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecordDetails);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RecordDetails()';
}


}

/// @nodoc
class $RecordDetailsCopyWith<$Res>  {
$RecordDetailsCopyWith(RecordDetails _, $Res Function(RecordDetails) __);
}


/// Adds pattern-matching-related methods to [RecordDetails].
extension RecordDetailsPatterns on RecordDetails {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( GrowthDetails value)?  growth,TResult Function( ActivityDetails value)?  activity,TResult Function( MilestoneDetails value)?  milestone,required TResult orElse(),}){
final _that = this;
switch (_that) {
case GrowthDetails() when growth != null:
return growth(_that);case ActivityDetails() when activity != null:
return activity(_that);case MilestoneDetails() when milestone != null:
return milestone(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( GrowthDetails value)  growth,required TResult Function( ActivityDetails value)  activity,required TResult Function( MilestoneDetails value)  milestone,}){
final _that = this;
switch (_that) {
case GrowthDetails():
return growth(_that);case ActivityDetails():
return activity(_that);case MilestoneDetails():
return milestone(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( GrowthDetails value)?  growth,TResult? Function( ActivityDetails value)?  activity,TResult? Function( MilestoneDetails value)?  milestone,}){
final _that = this;
switch (_that) {
case GrowthDetails() when growth != null:
return growth(_that);case ActivityDetails() when activity != null:
return activity(_that);case MilestoneDetails() when milestone != null:
return milestone(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( double? heightCm,  double? weightKg,  double? headCm)?  growth,TResult Function( ActivityType activityType,  double? amount,  int? durationMinutes)?  activity,TResult Function( String title,  String? presetKey)?  milestone,required TResult orElse(),}) {final _that = this;
switch (_that) {
case GrowthDetails() when growth != null:
return growth(_that.heightCm,_that.weightKg,_that.headCm);case ActivityDetails() when activity != null:
return activity(_that.activityType,_that.amount,_that.durationMinutes);case MilestoneDetails() when milestone != null:
return milestone(_that.title,_that.presetKey);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( double? heightCm,  double? weightKg,  double? headCm)  growth,required TResult Function( ActivityType activityType,  double? amount,  int? durationMinutes)  activity,required TResult Function( String title,  String? presetKey)  milestone,}) {final _that = this;
switch (_that) {
case GrowthDetails():
return growth(_that.heightCm,_that.weightKg,_that.headCm);case ActivityDetails():
return activity(_that.activityType,_that.amount,_that.durationMinutes);case MilestoneDetails():
return milestone(_that.title,_that.presetKey);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( double? heightCm,  double? weightKg,  double? headCm)?  growth,TResult? Function( ActivityType activityType,  double? amount,  int? durationMinutes)?  activity,TResult? Function( String title,  String? presetKey)?  milestone,}) {final _that = this;
switch (_that) {
case GrowthDetails() when growth != null:
return growth(_that.heightCm,_that.weightKg,_that.headCm);case ActivityDetails() when activity != null:
return activity(_that.activityType,_that.amount,_that.durationMinutes);case MilestoneDetails() when milestone != null:
return milestone(_that.title,_that.presetKey);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class GrowthDetails implements RecordDetails {
  const GrowthDetails({this.heightCm, this.weightKg, this.headCm,  String? $type}): $type = $type ?? 'growth';
  factory GrowthDetails.fromJson(Map<String, dynamic> json) => _$GrowthDetailsFromJson(json);

 final  double? heightCm;
 final  double? weightKg;
 final  double? headCm;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of RecordDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GrowthDetailsCopyWith<GrowthDetails> get copyWith => _$GrowthDetailsCopyWithImpl<GrowthDetails>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GrowthDetailsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GrowthDetails&&(identical(other.heightCm, heightCm) || other.heightCm == heightCm)&&(identical(other.weightKg, weightKg) || other.weightKg == weightKg)&&(identical(other.headCm, headCm) || other.headCm == headCm));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,heightCm,weightKg,headCm);

@override
String toString() {
  return 'RecordDetails.growth(heightCm: $heightCm, weightKg: $weightKg, headCm: $headCm)';
}


}

/// @nodoc
abstract mixin class $GrowthDetailsCopyWith<$Res> implements $RecordDetailsCopyWith<$Res> {
  factory $GrowthDetailsCopyWith(GrowthDetails value, $Res Function(GrowthDetails) _then) = _$GrowthDetailsCopyWithImpl;
@useResult
$Res call({
 double? heightCm, double? weightKg, double? headCm
});




}
/// @nodoc
class _$GrowthDetailsCopyWithImpl<$Res>
    implements $GrowthDetailsCopyWith<$Res> {
  _$GrowthDetailsCopyWithImpl(this._self, this._then);

  final GrowthDetails _self;
  final $Res Function(GrowthDetails) _then;

/// Create a copy of RecordDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? heightCm = freezed,Object? weightKg = freezed,Object? headCm = freezed,}) {
  return _then(GrowthDetails(
heightCm: freezed == heightCm ? _self.heightCm : heightCm // ignore: cast_nullable_to_non_nullable
as double?,weightKg: freezed == weightKg ? _self.weightKg : weightKg // ignore: cast_nullable_to_non_nullable
as double?,headCm: freezed == headCm ? _self.headCm : headCm // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

/// @nodoc
@JsonSerializable()

class ActivityDetails implements RecordDetails {
  const ActivityDetails({required this.activityType, this.amount, this.durationMinutes,  String? $type}): $type = $type ?? 'activity';
  factory ActivityDetails.fromJson(Map<String, dynamic> json) => _$ActivityDetailsFromJson(json);

 final  ActivityType activityType;
 final  double? amount;
 final  int? durationMinutes;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of RecordDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActivityDetailsCopyWith<ActivityDetails> get copyWith => _$ActivityDetailsCopyWithImpl<ActivityDetails>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ActivityDetailsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActivityDetails&&(identical(other.activityType, activityType) || other.activityType == activityType)&&(identical(other.amount, amount) || other.amount == amount)&&(identical(other.durationMinutes, durationMinutes) || other.durationMinutes == durationMinutes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,activityType,amount,durationMinutes);

@override
String toString() {
  return 'RecordDetails.activity(activityType: $activityType, amount: $amount, durationMinutes: $durationMinutes)';
}


}

/// @nodoc
abstract mixin class $ActivityDetailsCopyWith<$Res> implements $RecordDetailsCopyWith<$Res> {
  factory $ActivityDetailsCopyWith(ActivityDetails value, $Res Function(ActivityDetails) _then) = _$ActivityDetailsCopyWithImpl;
@useResult
$Res call({
 ActivityType activityType, double? amount, int? durationMinutes
});




}
/// @nodoc
class _$ActivityDetailsCopyWithImpl<$Res>
    implements $ActivityDetailsCopyWith<$Res> {
  _$ActivityDetailsCopyWithImpl(this._self, this._then);

  final ActivityDetails _self;
  final $Res Function(ActivityDetails) _then;

/// Create a copy of RecordDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? activityType = null,Object? amount = freezed,Object? durationMinutes = freezed,}) {
  return _then(ActivityDetails(
activityType: null == activityType ? _self.activityType : activityType // ignore: cast_nullable_to_non_nullable
as ActivityType,amount: freezed == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as double?,durationMinutes: freezed == durationMinutes ? _self.durationMinutes : durationMinutes // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
@JsonSerializable()

class MilestoneDetails implements RecordDetails {
  const MilestoneDetails({required this.title, this.presetKey,  String? $type}): $type = $type ?? 'milestone';
  factory MilestoneDetails.fromJson(Map<String, dynamic> json) => _$MilestoneDetailsFromJson(json);

 final  String title;
 final  String? presetKey;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of RecordDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MilestoneDetailsCopyWith<MilestoneDetails> get copyWith => _$MilestoneDetailsCopyWithImpl<MilestoneDetails>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MilestoneDetailsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MilestoneDetails&&(identical(other.title, title) || other.title == title)&&(identical(other.presetKey, presetKey) || other.presetKey == presetKey));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,title,presetKey);

@override
String toString() {
  return 'RecordDetails.milestone(title: $title, presetKey: $presetKey)';
}


}

/// @nodoc
abstract mixin class $MilestoneDetailsCopyWith<$Res> implements $RecordDetailsCopyWith<$Res> {
  factory $MilestoneDetailsCopyWith(MilestoneDetails value, $Res Function(MilestoneDetails) _then) = _$MilestoneDetailsCopyWithImpl;
@useResult
$Res call({
 String title, String? presetKey
});




}
/// @nodoc
class _$MilestoneDetailsCopyWithImpl<$Res>
    implements $MilestoneDetailsCopyWith<$Res> {
  _$MilestoneDetailsCopyWithImpl(this._self, this._then);

  final MilestoneDetails _self;
  final $Res Function(MilestoneDetails) _then;

/// Create a copy of RecordDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? title = null,Object? presetKey = freezed,}) {
  return _then(MilestoneDetails(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,presetKey: freezed == presetKey ? _self.presetKey : presetKey // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$TimelineRecord {

 String get id; RecordType get type;@UtcDateTimeConverter() DateTime get occurredAt; String? get note; RecordDetails? get details; List<Attachment> get attachments;@UtcDateTimeConverter() DateTime get createdAt;@UtcDateTimeConverter() DateTime get updatedAt;
/// Create a copy of TimelineRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineRecordCopyWith<TimelineRecord> get copyWith => _$TimelineRecordCopyWithImpl<TimelineRecord>(this as TimelineRecord, _$identity);

  /// Serializes this TimelineRecord to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.occurredAt, occurredAt) || other.occurredAt == occurredAt)&&(identical(other.note, note) || other.note == note)&&(identical(other.details, details) || other.details == details)&&const DeepCollectionEquality().equals(other.attachments, attachments)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,type,occurredAt,note,details,const DeepCollectionEquality().hash(attachments),createdAt,updatedAt);

@override
String toString() {
  return 'TimelineRecord(id: $id, type: $type, occurredAt: $occurredAt, note: $note, details: $details, attachments: $attachments, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $TimelineRecordCopyWith<$Res>  {
  factory $TimelineRecordCopyWith(TimelineRecord value, $Res Function(TimelineRecord) _then) = _$TimelineRecordCopyWithImpl;
@useResult
$Res call({
 String id, RecordType type,@UtcDateTimeConverter() DateTime occurredAt, String? note, RecordDetails? details, List<Attachment> attachments,@UtcDateTimeConverter() DateTime createdAt,@UtcDateTimeConverter() DateTime updatedAt
});


$RecordDetailsCopyWith<$Res>? get details;

}
/// @nodoc
class _$TimelineRecordCopyWithImpl<$Res>
    implements $TimelineRecordCopyWith<$Res> {
  _$TimelineRecordCopyWithImpl(this._self, this._then);

  final TimelineRecord _self;
  final $Res Function(TimelineRecord) _then;

/// Create a copy of TimelineRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? type = null,Object? occurredAt = null,Object? note = freezed,Object? details = freezed,Object? attachments = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(TimelineRecord(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as RecordType,occurredAt: null == occurredAt ? _self.occurredAt : occurredAt // ignore: cast_nullable_to_non_nullable
as DateTime,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,details: freezed == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as RecordDetails?,attachments: null == attachments ? _self.attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<Attachment>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}
/// Create a copy of TimelineRecord
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecordDetailsCopyWith<$Res>? get details {
    if (_self.details == null) {
    return null;
  }

  return $RecordDetailsCopyWith<$Res>(_self.details!, (value) {
    return _then(_self.copyWith(details: value));
  });
}
}


/// Adds pattern-matching-related methods to [TimelineRecord].
extension TimelineRecordPatterns on TimelineRecord {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TimelineRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TimelineRecord() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TimelineRecord value)  $default,){
final _that = this;
switch (_that) {
case _TimelineRecord():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TimelineRecord value)?  $default,){
final _that = this;
switch (_that) {
case _TimelineRecord() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  RecordType type, @UtcDateTimeConverter()  DateTime occurredAt,  String? note,  RecordDetails? details,  List<Attachment> attachments, @UtcDateTimeConverter()  DateTime createdAt, @UtcDateTimeConverter()  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TimelineRecord() when $default != null:
return $default(_that.id,_that.type,_that.occurredAt,_that.note,_that.details,_that.attachments,_that.createdAt,_that.updatedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  RecordType type, @UtcDateTimeConverter()  DateTime occurredAt,  String? note,  RecordDetails? details,  List<Attachment> attachments, @UtcDateTimeConverter()  DateTime createdAt, @UtcDateTimeConverter()  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _TimelineRecord():
return $default(_that.id,_that.type,_that.occurredAt,_that.note,_that.details,_that.attachments,_that.createdAt,_that.updatedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  RecordType type, @UtcDateTimeConverter()  DateTime occurredAt,  String? note,  RecordDetails? details,  List<Attachment> attachments, @UtcDateTimeConverter()  DateTime createdAt, @UtcDateTimeConverter()  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _TimelineRecord() when $default != null:
return $default(_that.id,_that.type,_that.occurredAt,_that.note,_that.details,_that.attachments,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TimelineRecord implements TimelineRecord {
  const _TimelineRecord({required this.id, required this.type, @UtcDateTimeConverter() required this.occurredAt, this.note, this.details,  List<Attachment> attachments = const <Attachment>[], @UtcDateTimeConverter() required this.createdAt, @UtcDateTimeConverter() required this.updatedAt}): _attachments = attachments;
  factory _TimelineRecord.fromJson(Map<String, dynamic> json) => _$TimelineRecordFromJson(json);

@override final  String id;
@override final  RecordType type;
@override@UtcDateTimeConverter() final  DateTime occurredAt;
@override final  String? note;
@override final  RecordDetails? details;
 final  List<Attachment> _attachments;
@override@JsonKey() List<Attachment> get attachments {
  if (_attachments is EqualUnmodifiableListView) return _attachments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_attachments);
}

@override@UtcDateTimeConverter() final  DateTime createdAt;
@override@UtcDateTimeConverter() final  DateTime updatedAt;

/// Create a copy of TimelineRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TimelineRecordCopyWith<_TimelineRecord> get copyWith => __$TimelineRecordCopyWithImpl<_TimelineRecord>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TimelineRecordToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TimelineRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.occurredAt, occurredAt) || other.occurredAt == occurredAt)&&(identical(other.note, note) || other.note == note)&&(identical(other.details, details) || other.details == details)&&const DeepCollectionEquality().equals(other._attachments, _attachments)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,type,occurredAt,note,details,const DeepCollectionEquality().hash(_attachments),createdAt,updatedAt);

@override
String toString() {
  return 'TimelineRecord(id: $id, type: $type, occurredAt: $occurredAt, note: $note, details: $details, attachments: $attachments, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$TimelineRecordCopyWith<$Res> implements $TimelineRecordCopyWith<$Res> {
  factory _$TimelineRecordCopyWith(_TimelineRecord value, $Res Function(_TimelineRecord) _then) = __$TimelineRecordCopyWithImpl;
@override @useResult
$Res call({
 String id, RecordType type,@UtcDateTimeConverter() DateTime occurredAt, String? note, RecordDetails? details, List<Attachment> attachments,@UtcDateTimeConverter() DateTime createdAt,@UtcDateTimeConverter() DateTime updatedAt
});


@override $RecordDetailsCopyWith<$Res>? get details;

}
/// @nodoc
class __$TimelineRecordCopyWithImpl<$Res>
    implements _$TimelineRecordCopyWith<$Res> {
  __$TimelineRecordCopyWithImpl(this._self, this._then);

  final _TimelineRecord _self;
  final $Res Function(_TimelineRecord) _then;

/// Create a copy of TimelineRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? type = null,Object? occurredAt = null,Object? note = freezed,Object? details = freezed,Object? attachments = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_TimelineRecord(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as RecordType,occurredAt: null == occurredAt ? _self.occurredAt : occurredAt // ignore: cast_nullable_to_non_nullable
as DateTime,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,details: freezed == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as RecordDetails?,attachments: null == attachments ? _self._attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<Attachment>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

/// Create a copy of TimelineRecord
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecordDetailsCopyWith<$Res>? get details {
    if (_self.details == null) {
    return null;
  }

  return $RecordDetailsCopyWith<$Res>(_self.details!, (value) {
    return _then(_self.copyWith(details: value));
  });
}
}

// dart format on
