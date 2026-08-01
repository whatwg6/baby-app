// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'attachment.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Attachment {

 String get id; String get recordId; MediaType get mediaType; String get filePath; String? get thumbnailPath;@UtcDateTimeConverter() DateTime get createdAt;
/// Create a copy of Attachment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AttachmentCopyWith<Attachment> get copyWith => _$AttachmentCopyWithImpl<Attachment>(this as Attachment, _$identity);

  /// Serializes this Attachment to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Attachment&&(identical(other.id, id) || other.id == id)&&(identical(other.recordId, recordId) || other.recordId == recordId)&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType)&&(identical(other.filePath, filePath) || other.filePath == filePath)&&(identical(other.thumbnailPath, thumbnailPath) || other.thumbnailPath == thumbnailPath)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,recordId,mediaType,filePath,thumbnailPath,createdAt);

@override
String toString() {
  return 'Attachment(id: $id, recordId: $recordId, mediaType: $mediaType, filePath: $filePath, thumbnailPath: $thumbnailPath, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $AttachmentCopyWith<$Res>  {
  factory $AttachmentCopyWith(Attachment value, $Res Function(Attachment) _then) = _$AttachmentCopyWithImpl;
@useResult
$Res call({
 String id, String recordId, MediaType mediaType, String filePath, String? thumbnailPath,@UtcDateTimeConverter() DateTime createdAt
});




}
/// @nodoc
class _$AttachmentCopyWithImpl<$Res>
    implements $AttachmentCopyWith<$Res> {
  _$AttachmentCopyWithImpl(this._self, this._then);

  final Attachment _self;
  final $Res Function(Attachment) _then;

/// Create a copy of Attachment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? recordId = null,Object? mediaType = null,Object? filePath = null,Object? thumbnailPath = freezed,Object? createdAt = null,}) {
  return _then(Attachment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,recordId: null == recordId ? _self.recordId : recordId // ignore: cast_nullable_to_non_nullable
as String,mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as MediaType,filePath: null == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String,thumbnailPath: freezed == thumbnailPath ? _self.thumbnailPath : thumbnailPath // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [Attachment].
extension AttachmentPatterns on Attachment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Attachment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Attachment() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Attachment value)  $default,){
final _that = this;
switch (_that) {
case _Attachment():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Attachment value)?  $default,){
final _that = this;
switch (_that) {
case _Attachment() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String recordId,  MediaType mediaType,  String filePath,  String? thumbnailPath, @UtcDateTimeConverter()  DateTime createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Attachment() when $default != null:
return $default(_that.id,_that.recordId,_that.mediaType,_that.filePath,_that.thumbnailPath,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String recordId,  MediaType mediaType,  String filePath,  String? thumbnailPath, @UtcDateTimeConverter()  DateTime createdAt)  $default,) {final _that = this;
switch (_that) {
case _Attachment():
return $default(_that.id,_that.recordId,_that.mediaType,_that.filePath,_that.thumbnailPath,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String recordId,  MediaType mediaType,  String filePath,  String? thumbnailPath, @UtcDateTimeConverter()  DateTime createdAt)?  $default,) {final _that = this;
switch (_that) {
case _Attachment() when $default != null:
return $default(_that.id,_that.recordId,_that.mediaType,_that.filePath,_that.thumbnailPath,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Attachment implements Attachment {
  const _Attachment({required this.id, required this.recordId, required this.mediaType, required this.filePath, this.thumbnailPath, @UtcDateTimeConverter() required this.createdAt});
  factory _Attachment.fromJson(Map<String, dynamic> json) => _$AttachmentFromJson(json);

@override final  String id;
@override final  String recordId;
@override final  MediaType mediaType;
@override final  String filePath;
@override final  String? thumbnailPath;
@override@UtcDateTimeConverter() final  DateTime createdAt;

/// Create a copy of Attachment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AttachmentCopyWith<_Attachment> get copyWith => __$AttachmentCopyWithImpl<_Attachment>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AttachmentToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Attachment&&(identical(other.id, id) || other.id == id)&&(identical(other.recordId, recordId) || other.recordId == recordId)&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType)&&(identical(other.filePath, filePath) || other.filePath == filePath)&&(identical(other.thumbnailPath, thumbnailPath) || other.thumbnailPath == thumbnailPath)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,recordId,mediaType,filePath,thumbnailPath,createdAt);

@override
String toString() {
  return 'Attachment(id: $id, recordId: $recordId, mediaType: $mediaType, filePath: $filePath, thumbnailPath: $thumbnailPath, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$AttachmentCopyWith<$Res> implements $AttachmentCopyWith<$Res> {
  factory _$AttachmentCopyWith(_Attachment value, $Res Function(_Attachment) _then) = __$AttachmentCopyWithImpl;
@override @useResult
$Res call({
 String id, String recordId, MediaType mediaType, String filePath, String? thumbnailPath,@UtcDateTimeConverter() DateTime createdAt
});




}
/// @nodoc
class __$AttachmentCopyWithImpl<$Res>
    implements _$AttachmentCopyWith<$Res> {
  __$AttachmentCopyWithImpl(this._self, this._then);

  final _Attachment _self;
  final $Res Function(_Attachment) _then;

/// Create a copy of Attachment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? recordId = null,Object? mediaType = null,Object? filePath = null,Object? thumbnailPath = freezed,Object? createdAt = null,}) {
  return _then(_Attachment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,recordId: null == recordId ? _self.recordId : recordId // ignore: cast_nullable_to_non_nullable
as String,mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as MediaType,filePath: null == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String,thumbnailPath: freezed == thumbnailPath ? _self.thumbnailPath : thumbnailPath // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}


/// @nodoc
mixin _$NewAttachmentInput {

 String? get id; MediaType get mediaType; String get filePath; String? get thumbnailPath;
/// Create a copy of NewAttachmentInput
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NewAttachmentInputCopyWith<NewAttachmentInput> get copyWith => _$NewAttachmentInputCopyWithImpl<NewAttachmentInput>(this as NewAttachmentInput, _$identity);

  /// Serializes this NewAttachmentInput to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NewAttachmentInput&&(identical(other.id, id) || other.id == id)&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType)&&(identical(other.filePath, filePath) || other.filePath == filePath)&&(identical(other.thumbnailPath, thumbnailPath) || other.thumbnailPath == thumbnailPath));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,mediaType,filePath,thumbnailPath);

@override
String toString() {
  return 'NewAttachmentInput(id: $id, mediaType: $mediaType, filePath: $filePath, thumbnailPath: $thumbnailPath)';
}


}

/// @nodoc
abstract mixin class $NewAttachmentInputCopyWith<$Res>  {
  factory $NewAttachmentInputCopyWith(NewAttachmentInput value, $Res Function(NewAttachmentInput) _then) = _$NewAttachmentInputCopyWithImpl;
@useResult
$Res call({
 String? id, MediaType mediaType, String filePath, String? thumbnailPath
});




}
/// @nodoc
class _$NewAttachmentInputCopyWithImpl<$Res>
    implements $NewAttachmentInputCopyWith<$Res> {
  _$NewAttachmentInputCopyWithImpl(this._self, this._then);

  final NewAttachmentInput _self;
  final $Res Function(NewAttachmentInput) _then;

/// Create a copy of NewAttachmentInput
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = freezed,Object? mediaType = null,Object? filePath = null,Object? thumbnailPath = freezed,}) {
  return _then(NewAttachmentInput(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as MediaType,filePath: null == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String,thumbnailPath: freezed == thumbnailPath ? _self.thumbnailPath : thumbnailPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [NewAttachmentInput].
extension NewAttachmentInputPatterns on NewAttachmentInput {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NewAttachmentInput value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NewAttachmentInput() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NewAttachmentInput value)  $default,){
final _that = this;
switch (_that) {
case _NewAttachmentInput():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NewAttachmentInput value)?  $default,){
final _that = this;
switch (_that) {
case _NewAttachmentInput() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? id,  MediaType mediaType,  String filePath,  String? thumbnailPath)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NewAttachmentInput() when $default != null:
return $default(_that.id,_that.mediaType,_that.filePath,_that.thumbnailPath);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? id,  MediaType mediaType,  String filePath,  String? thumbnailPath)  $default,) {final _that = this;
switch (_that) {
case _NewAttachmentInput():
return $default(_that.id,_that.mediaType,_that.filePath,_that.thumbnailPath);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? id,  MediaType mediaType,  String filePath,  String? thumbnailPath)?  $default,) {final _that = this;
switch (_that) {
case _NewAttachmentInput() when $default != null:
return $default(_that.id,_that.mediaType,_that.filePath,_that.thumbnailPath);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _NewAttachmentInput implements NewAttachmentInput {
  const _NewAttachmentInput({this.id, required this.mediaType, required this.filePath, this.thumbnailPath});
  factory _NewAttachmentInput.fromJson(Map<String, dynamic> json) => _$NewAttachmentInputFromJson(json);

@override final  String? id;
@override final  MediaType mediaType;
@override final  String filePath;
@override final  String? thumbnailPath;

/// Create a copy of NewAttachmentInput
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NewAttachmentInputCopyWith<_NewAttachmentInput> get copyWith => __$NewAttachmentInputCopyWithImpl<_NewAttachmentInput>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$NewAttachmentInputToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _NewAttachmentInput&&(identical(other.id, id) || other.id == id)&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType)&&(identical(other.filePath, filePath) || other.filePath == filePath)&&(identical(other.thumbnailPath, thumbnailPath) || other.thumbnailPath == thumbnailPath));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,mediaType,filePath,thumbnailPath);

@override
String toString() {
  return 'NewAttachmentInput(id: $id, mediaType: $mediaType, filePath: $filePath, thumbnailPath: $thumbnailPath)';
}


}

/// @nodoc
abstract mixin class _$NewAttachmentInputCopyWith<$Res> implements $NewAttachmentInputCopyWith<$Res> {
  factory _$NewAttachmentInputCopyWith(_NewAttachmentInput value, $Res Function(_NewAttachmentInput) _then) = __$NewAttachmentInputCopyWithImpl;
@override @useResult
$Res call({
 String? id, MediaType mediaType, String filePath, String? thumbnailPath
});




}
/// @nodoc
class __$NewAttachmentInputCopyWithImpl<$Res>
    implements _$NewAttachmentInputCopyWith<$Res> {
  __$NewAttachmentInputCopyWithImpl(this._self, this._then);

  final _NewAttachmentInput _self;
  final $Res Function(_NewAttachmentInput) _then;

/// Create a copy of NewAttachmentInput
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = freezed,Object? mediaType = null,Object? filePath = null,Object? thumbnailPath = freezed,}) {
  return _then(_NewAttachmentInput(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as MediaType,filePath: null == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String,thumbnailPath: freezed == thumbnailPath ? _self.thumbnailPath : thumbnailPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
