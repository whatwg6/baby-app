// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'record_draft.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
RecordDraftAttachment _$RecordDraftAttachmentFromJson(
  Map<String, dynamic> json
) {
        switch (json['runtimeType']) {
                  case 'picked':
          return PickedAttachment.fromJson(
            json
          );
                case 'existing':
          return ExistingAttachment.fromJson(
            json
          );

          default:
            throw CheckedFromJsonException(
  json,
  'runtimeType',
  'RecordDraftAttachment',
  'Invalid union type "${json['runtimeType']}"!'
);
        }

}

/// @nodoc
mixin _$RecordDraftAttachment {

 MediaType get mediaType;
/// Create a copy of RecordDraftAttachment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecordDraftAttachmentCopyWith<RecordDraftAttachment> get copyWith => _$RecordDraftAttachmentCopyWithImpl<RecordDraftAttachment>(this as RecordDraftAttachment, _$identity);

  /// Serializes this RecordDraftAttachment to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecordDraftAttachment&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,mediaType);

@override
String toString() {
  return 'RecordDraftAttachment(mediaType: $mediaType)';
}


}

/// @nodoc
abstract mixin class $RecordDraftAttachmentCopyWith<$Res>  {
  factory $RecordDraftAttachmentCopyWith(RecordDraftAttachment value, $Res Function(RecordDraftAttachment) _then) = _$RecordDraftAttachmentCopyWithImpl;
@useResult
$Res call({
 MediaType mediaType
});




}
/// @nodoc
class _$RecordDraftAttachmentCopyWithImpl<$Res>
    implements $RecordDraftAttachmentCopyWith<$Res> {
  _$RecordDraftAttachmentCopyWithImpl(this._self, this._then);

  final RecordDraftAttachment _self;
  final $Res Function(RecordDraftAttachment) _then;

/// Create a copy of RecordDraftAttachment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? mediaType = null,}) {
  return _then(_self.copyWith(
mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as MediaType,
  ));
}

}


/// Adds pattern-matching-related methods to [RecordDraftAttachment].
extension RecordDraftAttachmentPatterns on RecordDraftAttachment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PickedAttachment value)?  picked,TResult Function( ExistingAttachment value)?  existing,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PickedAttachment() when picked != null:
return picked(_that);case ExistingAttachment() when existing != null:
return existing(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PickedAttachment value)  picked,required TResult Function( ExistingAttachment value)  existing,}){
final _that = this;
switch (_that) {
case PickedAttachment():
return picked(_that);case ExistingAttachment():
return existing(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PickedAttachment value)?  picked,TResult? Function( ExistingAttachment value)?  existing,}){
final _that = this;
switch (_that) {
case PickedAttachment() when picked != null:
return picked(_that);case ExistingAttachment() when existing != null:
return existing(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String sourcePath,  MediaType mediaType)?  picked,TResult Function( String id,  MediaType mediaType,  String filePath,  String? thumbnailPath)?  existing,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PickedAttachment() when picked != null:
return picked(_that.sourcePath,_that.mediaType);case ExistingAttachment() when existing != null:
return existing(_that.id,_that.mediaType,_that.filePath,_that.thumbnailPath);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String sourcePath,  MediaType mediaType)  picked,required TResult Function( String id,  MediaType mediaType,  String filePath,  String? thumbnailPath)  existing,}) {final _that = this;
switch (_that) {
case PickedAttachment():
return picked(_that.sourcePath,_that.mediaType);case ExistingAttachment():
return existing(_that.id,_that.mediaType,_that.filePath,_that.thumbnailPath);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String sourcePath,  MediaType mediaType)?  picked,TResult? Function( String id,  MediaType mediaType,  String filePath,  String? thumbnailPath)?  existing,}) {final _that = this;
switch (_that) {
case PickedAttachment() when picked != null:
return picked(_that.sourcePath,_that.mediaType);case ExistingAttachment() when existing != null:
return existing(_that.id,_that.mediaType,_that.filePath,_that.thumbnailPath);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class PickedAttachment implements RecordDraftAttachment {
  const PickedAttachment({required this.sourcePath, required this.mediaType,  String? $type}): $type = $type ?? 'picked';
  factory PickedAttachment.fromJson(Map<String, dynamic> json) => _$PickedAttachmentFromJson(json);

 final  String sourcePath;
@override final  MediaType mediaType;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of RecordDraftAttachment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PickedAttachmentCopyWith<PickedAttachment> get copyWith => _$PickedAttachmentCopyWithImpl<PickedAttachment>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PickedAttachmentToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PickedAttachment&&(identical(other.sourcePath, sourcePath) || other.sourcePath == sourcePath)&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,sourcePath,mediaType);

@override
String toString() {
  return 'RecordDraftAttachment.picked(sourcePath: $sourcePath, mediaType: $mediaType)';
}


}

/// @nodoc
abstract mixin class $PickedAttachmentCopyWith<$Res> implements $RecordDraftAttachmentCopyWith<$Res> {
  factory $PickedAttachmentCopyWith(PickedAttachment value, $Res Function(PickedAttachment) _then) = _$PickedAttachmentCopyWithImpl;
@override @useResult
$Res call({
 String sourcePath, MediaType mediaType
});




}
/// @nodoc
class _$PickedAttachmentCopyWithImpl<$Res>
    implements $PickedAttachmentCopyWith<$Res> {
  _$PickedAttachmentCopyWithImpl(this._self, this._then);

  final PickedAttachment _self;
  final $Res Function(PickedAttachment) _then;

/// Create a copy of RecordDraftAttachment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sourcePath = null,Object? mediaType = null,}) {
  return _then(PickedAttachment(
sourcePath: null == sourcePath ? _self.sourcePath : sourcePath // ignore: cast_nullable_to_non_nullable
as String,mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as MediaType,
  ));
}


}

/// @nodoc
@JsonSerializable()

class ExistingAttachment implements RecordDraftAttachment {
  const ExistingAttachment({required this.id, required this.mediaType, required this.filePath, this.thumbnailPath,  String? $type}): $type = $type ?? 'existing';
  factory ExistingAttachment.fromJson(Map<String, dynamic> json) => _$ExistingAttachmentFromJson(json);

 final  String id;
@override final  MediaType mediaType;
 final  String filePath;
 final  String? thumbnailPath;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of RecordDraftAttachment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExistingAttachmentCopyWith<ExistingAttachment> get copyWith => _$ExistingAttachmentCopyWithImpl<ExistingAttachment>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ExistingAttachmentToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExistingAttachment&&(identical(other.id, id) || other.id == id)&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType)&&(identical(other.filePath, filePath) || other.filePath == filePath)&&(identical(other.thumbnailPath, thumbnailPath) || other.thumbnailPath == thumbnailPath));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,mediaType,filePath,thumbnailPath);

@override
String toString() {
  return 'RecordDraftAttachment.existing(id: $id, mediaType: $mediaType, filePath: $filePath, thumbnailPath: $thumbnailPath)';
}


}

/// @nodoc
abstract mixin class $ExistingAttachmentCopyWith<$Res> implements $RecordDraftAttachmentCopyWith<$Res> {
  factory $ExistingAttachmentCopyWith(ExistingAttachment value, $Res Function(ExistingAttachment) _then) = _$ExistingAttachmentCopyWithImpl;
@override @useResult
$Res call({
 String id, MediaType mediaType, String filePath, String? thumbnailPath
});




}
/// @nodoc
class _$ExistingAttachmentCopyWithImpl<$Res>
    implements $ExistingAttachmentCopyWith<$Res> {
  _$ExistingAttachmentCopyWithImpl(this._self, this._then);

  final ExistingAttachment _self;
  final $Res Function(ExistingAttachment) _then;

/// Create a copy of RecordDraftAttachment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? mediaType = null,Object? filePath = null,Object? thumbnailPath = freezed,}) {
  return _then(ExistingAttachment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as MediaType,filePath: null == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String,thumbnailPath: freezed == thumbnailPath ? _self.thumbnailPath : thumbnailPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$RecordDraft {

 RecordType get type;@UtcDateTimeConverter() DateTime get occurredAt; String? get note; RecordDetails? get details; List<RecordDraftAttachment> get attachments;
/// Create a copy of RecordDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecordDraftCopyWith<RecordDraft> get copyWith => _$RecordDraftCopyWithImpl<RecordDraft>(this as RecordDraft, _$identity);

  /// Serializes this RecordDraft to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecordDraft&&(identical(other.type, type) || other.type == type)&&(identical(other.occurredAt, occurredAt) || other.occurredAt == occurredAt)&&(identical(other.note, note) || other.note == note)&&(identical(other.details, details) || other.details == details)&&const DeepCollectionEquality().equals(other.attachments, attachments));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,occurredAt,note,details,const DeepCollectionEquality().hash(attachments));

@override
String toString() {
  return 'RecordDraft(type: $type, occurredAt: $occurredAt, note: $note, details: $details, attachments: $attachments)';
}


}

/// @nodoc
abstract mixin class $RecordDraftCopyWith<$Res>  {
  factory $RecordDraftCopyWith(RecordDraft value, $Res Function(RecordDraft) _then) = _$RecordDraftCopyWithImpl;
@useResult
$Res call({
 RecordType type,@UtcDateTimeConverter() DateTime occurredAt, String? note, RecordDetails? details, List<RecordDraftAttachment> attachments
});


$RecordDetailsCopyWith<$Res>? get details;

}
/// @nodoc
class _$RecordDraftCopyWithImpl<$Res>
    implements $RecordDraftCopyWith<$Res> {
  _$RecordDraftCopyWithImpl(this._self, this._then);

  final RecordDraft _self;
  final $Res Function(RecordDraft) _then;

/// Create a copy of RecordDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? occurredAt = null,Object? note = freezed,Object? details = freezed,Object? attachments = null,}) {
  return _then(RecordDraft(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as RecordType,occurredAt: null == occurredAt ? _self.occurredAt : occurredAt // ignore: cast_nullable_to_non_nullable
as DateTime,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,details: freezed == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as RecordDetails?,attachments: null == attachments ? _self.attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<RecordDraftAttachment>,
  ));
}
/// Create a copy of RecordDraft
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


/// Adds pattern-matching-related methods to [RecordDraft].
extension RecordDraftPatterns on RecordDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecordDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecordDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecordDraft value)  $default,){
final _that = this;
switch (_that) {
case _RecordDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecordDraft value)?  $default,){
final _that = this;
switch (_that) {
case _RecordDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( RecordType type, @UtcDateTimeConverter()  DateTime occurredAt,  String? note,  RecordDetails? details,  List<RecordDraftAttachment> attachments)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RecordDraft() when $default != null:
return $default(_that.type,_that.occurredAt,_that.note,_that.details,_that.attachments);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( RecordType type, @UtcDateTimeConverter()  DateTime occurredAt,  String? note,  RecordDetails? details,  List<RecordDraftAttachment> attachments)  $default,) {final _that = this;
switch (_that) {
case _RecordDraft():
return $default(_that.type,_that.occurredAt,_that.note,_that.details,_that.attachments);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( RecordType type, @UtcDateTimeConverter()  DateTime occurredAt,  String? note,  RecordDetails? details,  List<RecordDraftAttachment> attachments)?  $default,) {final _that = this;
switch (_that) {
case _RecordDraft() when $default != null:
return $default(_that.type,_that.occurredAt,_that.note,_that.details,_that.attachments);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RecordDraft extends RecordDraft {
  const _RecordDraft({required this.type, @UtcDateTimeConverter() required this.occurredAt, this.note, this.details,  List<RecordDraftAttachment> attachments = const <RecordDraftAttachment>[]}): _attachments = attachments,super._();
  factory _RecordDraft.fromJson(Map<String, dynamic> json) => _$RecordDraftFromJson(json);

@override final  RecordType type;
@override@UtcDateTimeConverter() final  DateTime occurredAt;
@override final  String? note;
@override final  RecordDetails? details;
 final  List<RecordDraftAttachment> _attachments;
@override@JsonKey() List<RecordDraftAttachment> get attachments {
  if (_attachments is EqualUnmodifiableListView) return _attachments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_attachments);
}


/// Create a copy of RecordDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecordDraftCopyWith<_RecordDraft> get copyWith => __$RecordDraftCopyWithImpl<_RecordDraft>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RecordDraftToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecordDraft&&(identical(other.type, type) || other.type == type)&&(identical(other.occurredAt, occurredAt) || other.occurredAt == occurredAt)&&(identical(other.note, note) || other.note == note)&&(identical(other.details, details) || other.details == details)&&const DeepCollectionEquality().equals(other._attachments, _attachments));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,occurredAt,note,details,const DeepCollectionEquality().hash(_attachments));

@override
String toString() {
  return 'RecordDraft(type: $type, occurredAt: $occurredAt, note: $note, details: $details, attachments: $attachments)';
}


}

/// @nodoc
abstract mixin class _$RecordDraftCopyWith<$Res> implements $RecordDraftCopyWith<$Res> {
  factory _$RecordDraftCopyWith(_RecordDraft value, $Res Function(_RecordDraft) _then) = __$RecordDraftCopyWithImpl;
@override @useResult
$Res call({
 RecordType type,@UtcDateTimeConverter() DateTime occurredAt, String? note, RecordDetails? details, List<RecordDraftAttachment> attachments
});


@override $RecordDetailsCopyWith<$Res>? get details;

}
/// @nodoc
class __$RecordDraftCopyWithImpl<$Res>
    implements _$RecordDraftCopyWith<$Res> {
  __$RecordDraftCopyWithImpl(this._self, this._then);

  final _RecordDraft _self;
  final $Res Function(_RecordDraft) _then;

/// Create a copy of RecordDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? occurredAt = null,Object? note = freezed,Object? details = freezed,Object? attachments = null,}) {
  return _then(_RecordDraft(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as RecordType,occurredAt: null == occurredAt ? _self.occurredAt : occurredAt // ignore: cast_nullable_to_non_nullable
as DateTime,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,details: freezed == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as RecordDetails?,attachments: null == attachments ? _self._attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<RecordDraftAttachment>,
  ));
}

/// Create a copy of RecordDraft
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


/// @nodoc
mixin _$NewRecordInput {

 RecordType get type;@UtcDateTimeConverter() DateTime get occurredAt; String? get note; RecordDetails? get details; List<NewAttachmentInput> get attachments;
/// Create a copy of NewRecordInput
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NewRecordInputCopyWith<NewRecordInput> get copyWith => _$NewRecordInputCopyWithImpl<NewRecordInput>(this as NewRecordInput, _$identity);

  /// Serializes this NewRecordInput to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NewRecordInput&&(identical(other.type, type) || other.type == type)&&(identical(other.occurredAt, occurredAt) || other.occurredAt == occurredAt)&&(identical(other.note, note) || other.note == note)&&(identical(other.details, details) || other.details == details)&&const DeepCollectionEquality().equals(other.attachments, attachments));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,occurredAt,note,details,const DeepCollectionEquality().hash(attachments));

@override
String toString() {
  return 'NewRecordInput(type: $type, occurredAt: $occurredAt, note: $note, details: $details, attachments: $attachments)';
}


}

/// @nodoc
abstract mixin class $NewRecordInputCopyWith<$Res>  {
  factory $NewRecordInputCopyWith(NewRecordInput value, $Res Function(NewRecordInput) _then) = _$NewRecordInputCopyWithImpl;
@useResult
$Res call({
 RecordType type,@UtcDateTimeConverter() DateTime occurredAt, String? note, RecordDetails? details, List<NewAttachmentInput> attachments
});


$RecordDetailsCopyWith<$Res>? get details;

}
/// @nodoc
class _$NewRecordInputCopyWithImpl<$Res>
    implements $NewRecordInputCopyWith<$Res> {
  _$NewRecordInputCopyWithImpl(this._self, this._then);

  final NewRecordInput _self;
  final $Res Function(NewRecordInput) _then;

/// Create a copy of NewRecordInput
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? occurredAt = null,Object? note = freezed,Object? details = freezed,Object? attachments = null,}) {
  return _then(NewRecordInput(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as RecordType,occurredAt: null == occurredAt ? _self.occurredAt : occurredAt // ignore: cast_nullable_to_non_nullable
as DateTime,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,details: freezed == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as RecordDetails?,attachments: null == attachments ? _self.attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<NewAttachmentInput>,
  ));
}
/// Create a copy of NewRecordInput
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


/// Adds pattern-matching-related methods to [NewRecordInput].
extension NewRecordInputPatterns on NewRecordInput {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NewRecordInput value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NewRecordInput() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NewRecordInput value)  $default,){
final _that = this;
switch (_that) {
case _NewRecordInput():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NewRecordInput value)?  $default,){
final _that = this;
switch (_that) {
case _NewRecordInput() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( RecordType type, @UtcDateTimeConverter()  DateTime occurredAt,  String? note,  RecordDetails? details,  List<NewAttachmentInput> attachments)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NewRecordInput() when $default != null:
return $default(_that.type,_that.occurredAt,_that.note,_that.details,_that.attachments);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( RecordType type, @UtcDateTimeConverter()  DateTime occurredAt,  String? note,  RecordDetails? details,  List<NewAttachmentInput> attachments)  $default,) {final _that = this;
switch (_that) {
case _NewRecordInput():
return $default(_that.type,_that.occurredAt,_that.note,_that.details,_that.attachments);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( RecordType type, @UtcDateTimeConverter()  DateTime occurredAt,  String? note,  RecordDetails? details,  List<NewAttachmentInput> attachments)?  $default,) {final _that = this;
switch (_that) {
case _NewRecordInput() when $default != null:
return $default(_that.type,_that.occurredAt,_that.note,_that.details,_that.attachments);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _NewRecordInput implements NewRecordInput {
  const _NewRecordInput({required this.type, @UtcDateTimeConverter() required this.occurredAt, this.note, this.details,  List<NewAttachmentInput> attachments = const <NewAttachmentInput>[]}): _attachments = attachments;
  factory _NewRecordInput.fromJson(Map<String, dynamic> json) => _$NewRecordInputFromJson(json);

@override final  RecordType type;
@override@UtcDateTimeConverter() final  DateTime occurredAt;
@override final  String? note;
@override final  RecordDetails? details;
 final  List<NewAttachmentInput> _attachments;
@override@JsonKey() List<NewAttachmentInput> get attachments {
  if (_attachments is EqualUnmodifiableListView) return _attachments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_attachments);
}


/// Create a copy of NewRecordInput
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NewRecordInputCopyWith<_NewRecordInput> get copyWith => __$NewRecordInputCopyWithImpl<_NewRecordInput>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$NewRecordInputToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _NewRecordInput&&(identical(other.type, type) || other.type == type)&&(identical(other.occurredAt, occurredAt) || other.occurredAt == occurredAt)&&(identical(other.note, note) || other.note == note)&&(identical(other.details, details) || other.details == details)&&const DeepCollectionEquality().equals(other._attachments, _attachments));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,occurredAt,note,details,const DeepCollectionEquality().hash(_attachments));

@override
String toString() {
  return 'NewRecordInput(type: $type, occurredAt: $occurredAt, note: $note, details: $details, attachments: $attachments)';
}


}

/// @nodoc
abstract mixin class _$NewRecordInputCopyWith<$Res> implements $NewRecordInputCopyWith<$Res> {
  factory _$NewRecordInputCopyWith(_NewRecordInput value, $Res Function(_NewRecordInput) _then) = __$NewRecordInputCopyWithImpl;
@override @useResult
$Res call({
 RecordType type,@UtcDateTimeConverter() DateTime occurredAt, String? note, RecordDetails? details, List<NewAttachmentInput> attachments
});


@override $RecordDetailsCopyWith<$Res>? get details;

}
/// @nodoc
class __$NewRecordInputCopyWithImpl<$Res>
    implements _$NewRecordInputCopyWith<$Res> {
  __$NewRecordInputCopyWithImpl(this._self, this._then);

  final _NewRecordInput _self;
  final $Res Function(_NewRecordInput) _then;

/// Create a copy of NewRecordInput
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? occurredAt = null,Object? note = freezed,Object? details = freezed,Object? attachments = null,}) {
  return _then(_NewRecordInput(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as RecordType,occurredAt: null == occurredAt ? _self.occurredAt : occurredAt // ignore: cast_nullable_to_non_nullable
as DateTime,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,details: freezed == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as RecordDetails?,attachments: null == attachments ? _self._attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<NewAttachmentInput>,
  ));
}

/// Create a copy of NewRecordInput
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
