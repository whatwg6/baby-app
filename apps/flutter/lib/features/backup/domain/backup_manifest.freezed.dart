// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'backup_manifest.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$BackupManifestV1 {

 String get format; int get version; String get createdAt; BackupFileEntry get database; List<BackupFileEntry> get media;
/// Create a copy of BackupManifestV1
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackupManifestV1CopyWith<BackupManifestV1> get copyWith => _$BackupManifestV1CopyWithImpl<BackupManifestV1>(this as BackupManifestV1, _$identity);

  /// Serializes this BackupManifestV1 to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupManifestV1&&(identical(other.format, format) || other.format == format)&&(identical(other.version, version) || other.version == version)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.database, database) || other.database == database)&&const DeepCollectionEquality().equals(other.media, media));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,format,version,createdAt,database,const DeepCollectionEquality().hash(media));

@override
String toString() {
  return 'BackupManifestV1(format: $format, version: $version, createdAt: $createdAt, database: $database, media: $media)';
}


}

/// @nodoc
abstract mixin class $BackupManifestV1CopyWith<$Res>  {
  factory $BackupManifestV1CopyWith(BackupManifestV1 value, $Res Function(BackupManifestV1) _then) = _$BackupManifestV1CopyWithImpl;
@useResult
$Res call({
 String format, int version, String createdAt, BackupFileEntry database, List<BackupFileEntry> media
});


$BackupFileEntryCopyWith<$Res> get database;

}
/// @nodoc
class _$BackupManifestV1CopyWithImpl<$Res>
    implements $BackupManifestV1CopyWith<$Res> {
  _$BackupManifestV1CopyWithImpl(this._self, this._then);

  final BackupManifestV1 _self;
  final $Res Function(BackupManifestV1) _then;

/// Create a copy of BackupManifestV1
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? format = null,Object? version = null,Object? createdAt = null,Object? database = null,Object? media = null,}) {
  return _then(BackupManifestV1(
format: null == format ? _self.format : format // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,database: null == database ? _self.database : database // ignore: cast_nullable_to_non_nullable
as BackupFileEntry,media: null == media ? _self.media : media // ignore: cast_nullable_to_non_nullable
as List<BackupFileEntry>,
  ));
}
/// Create a copy of BackupManifestV1
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BackupFileEntryCopyWith<$Res> get database {

  return $BackupFileEntryCopyWith<$Res>(_self.database, (value) {
    return _then(_self.copyWith(database: value));
  });
}
}


/// Adds pattern-matching-related methods to [BackupManifestV1].
extension BackupManifestV1Patterns on BackupManifestV1 {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BackupManifestV1 value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BackupManifestV1() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BackupManifestV1 value)  $default,){
final _that = this;
switch (_that) {
case _BackupManifestV1():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BackupManifestV1 value)?  $default,){
final _that = this;
switch (_that) {
case _BackupManifestV1() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String format,  int version,  String createdAt,  BackupFileEntry database,  List<BackupFileEntry> media)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BackupManifestV1() when $default != null:
return $default(_that.format,_that.version,_that.createdAt,_that.database,_that.media);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String format,  int version,  String createdAt,  BackupFileEntry database,  List<BackupFileEntry> media)  $default,) {final _that = this;
switch (_that) {
case _BackupManifestV1():
return $default(_that.format,_that.version,_that.createdAt,_that.database,_that.media);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String format,  int version,  String createdAt,  BackupFileEntry database,  List<BackupFileEntry> media)?  $default,) {final _that = this;
switch (_that) {
case _BackupManifestV1() when $default != null:
return $default(_that.format,_that.version,_that.createdAt,_that.database,_that.media);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BackupManifestV1 implements BackupManifestV1 {
  const _BackupManifestV1({this.format = 'baby-growth-backup', this.version = 1, required this.createdAt, required this.database, required  List<BackupFileEntry> media}): _media = media;
  factory _BackupManifestV1.fromJson(Map<String, dynamic> json) => _$BackupManifestV1FromJson(json);

@override@JsonKey() final  String format;
@override@JsonKey() final  int version;
@override final  String createdAt;
@override final  BackupFileEntry database;
 final  List<BackupFileEntry> _media;
@override List<BackupFileEntry> get media {
  if (_media is EqualUnmodifiableListView) return _media;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_media);
}


/// Create a copy of BackupManifestV1
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BackupManifestV1CopyWith<_BackupManifestV1> get copyWith => __$BackupManifestV1CopyWithImpl<_BackupManifestV1>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BackupManifestV1ToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BackupManifestV1&&(identical(other.format, format) || other.format == format)&&(identical(other.version, version) || other.version == version)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.database, database) || other.database == database)&&const DeepCollectionEquality().equals(other._media, _media));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,format,version,createdAt,database,const DeepCollectionEquality().hash(_media));

@override
String toString() {
  return 'BackupManifestV1(format: $format, version: $version, createdAt: $createdAt, database: $database, media: $media)';
}


}

/// @nodoc
abstract mixin class _$BackupManifestV1CopyWith<$Res> implements $BackupManifestV1CopyWith<$Res> {
  factory _$BackupManifestV1CopyWith(_BackupManifestV1 value, $Res Function(_BackupManifestV1) _then) = __$BackupManifestV1CopyWithImpl;
@override @useResult
$Res call({
 String format, int version, String createdAt, BackupFileEntry database, List<BackupFileEntry> media
});


@override $BackupFileEntryCopyWith<$Res> get database;

}
/// @nodoc
class __$BackupManifestV1CopyWithImpl<$Res>
    implements _$BackupManifestV1CopyWith<$Res> {
  __$BackupManifestV1CopyWithImpl(this._self, this._then);

  final _BackupManifestV1 _self;
  final $Res Function(_BackupManifestV1) _then;

/// Create a copy of BackupManifestV1
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? format = null,Object? version = null,Object? createdAt = null,Object? database = null,Object? media = null,}) {
  return _then(_BackupManifestV1(
format: null == format ? _self.format : format // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,database: null == database ? _self.database : database // ignore: cast_nullable_to_non_nullable
as BackupFileEntry,media: null == media ? _self._media : media // ignore: cast_nullable_to_non_nullable
as List<BackupFileEntry>,
  ));
}

/// Create a copy of BackupManifestV1
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BackupFileEntryCopyWith<$Res> get database {

  return $BackupFileEntryCopyWith<$Res>(_self.database, (value) {
    return _then(_self.copyWith(database: value));
  });
}
}


/// @nodoc
mixin _$BackupFileEntry {

 String get path; String get sha256; int get size;
/// Create a copy of BackupFileEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackupFileEntryCopyWith<BackupFileEntry> get copyWith => _$BackupFileEntryCopyWithImpl<BackupFileEntry>(this as BackupFileEntry, _$identity);

  /// Serializes this BackupFileEntry to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupFileEntry&&(identical(other.path, path) || other.path == path)&&(identical(other.sha256, sha256) || other.sha256 == sha256)&&(identical(other.size, size) || other.size == size));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,path,sha256,size);

@override
String toString() {
  return 'BackupFileEntry(path: $path, sha256: $sha256, size: $size)';
}


}

/// @nodoc
abstract mixin class $BackupFileEntryCopyWith<$Res>  {
  factory $BackupFileEntryCopyWith(BackupFileEntry value, $Res Function(BackupFileEntry) _then) = _$BackupFileEntryCopyWithImpl;
@useResult
$Res call({
 String path, String sha256, int size
});




}
/// @nodoc
class _$BackupFileEntryCopyWithImpl<$Res>
    implements $BackupFileEntryCopyWith<$Res> {
  _$BackupFileEntryCopyWithImpl(this._self, this._then);

  final BackupFileEntry _self;
  final $Res Function(BackupFileEntry) _then;

/// Create a copy of BackupFileEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,Object? sha256 = null,Object? size = null,}) {
  return _then(BackupFileEntry(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,sha256: null == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [BackupFileEntry].
extension BackupFileEntryPatterns on BackupFileEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BackupFileEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BackupFileEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BackupFileEntry value)  $default,){
final _that = this;
switch (_that) {
case _BackupFileEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BackupFileEntry value)?  $default,){
final _that = this;
switch (_that) {
case _BackupFileEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String path,  String sha256,  int size)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BackupFileEntry() when $default != null:
return $default(_that.path,_that.sha256,_that.size);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String path,  String sha256,  int size)  $default,) {final _that = this;
switch (_that) {
case _BackupFileEntry():
return $default(_that.path,_that.sha256,_that.size);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String path,  String sha256,  int size)?  $default,) {final _that = this;
switch (_that) {
case _BackupFileEntry() when $default != null:
return $default(_that.path,_that.sha256,_that.size);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BackupFileEntry implements BackupFileEntry {
  const _BackupFileEntry({required this.path, required this.sha256, required this.size});
  factory _BackupFileEntry.fromJson(Map<String, dynamic> json) => _$BackupFileEntryFromJson(json);

@override final  String path;
@override final  String sha256;
@override final  int size;

/// Create a copy of BackupFileEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BackupFileEntryCopyWith<_BackupFileEntry> get copyWith => __$BackupFileEntryCopyWithImpl<_BackupFileEntry>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BackupFileEntryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BackupFileEntry&&(identical(other.path, path) || other.path == path)&&(identical(other.sha256, sha256) || other.sha256 == sha256)&&(identical(other.size, size) || other.size == size));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,path,sha256,size);

@override
String toString() {
  return 'BackupFileEntry(path: $path, sha256: $sha256, size: $size)';
}


}

/// @nodoc
abstract mixin class _$BackupFileEntryCopyWith<$Res> implements $BackupFileEntryCopyWith<$Res> {
  factory _$BackupFileEntryCopyWith(_BackupFileEntry value, $Res Function(_BackupFileEntry) _then) = __$BackupFileEntryCopyWithImpl;
@override @useResult
$Res call({
 String path, String sha256, int size
});




}
/// @nodoc
class __$BackupFileEntryCopyWithImpl<$Res>
    implements _$BackupFileEntryCopyWith<$Res> {
  __$BackupFileEntryCopyWithImpl(this._self, this._then);

  final _BackupFileEntry _self;
  final $Res Function(_BackupFileEntry) _then;

/// Create a copy of BackupFileEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? sha256 = null,Object? size = null,}) {
  return _then(_BackupFileEntry(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,sha256: null == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
