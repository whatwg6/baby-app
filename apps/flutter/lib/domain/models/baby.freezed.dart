// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'baby.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Baby {

 String get id; String get name; String get birthDate; String? get sex; String? get avatarPath;@UtcDateTimeConverter() DateTime get createdAt;@UtcDateTimeConverter() DateTime get updatedAt;
/// Create a copy of Baby
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BabyCopyWith<Baby> get copyWith => _$BabyCopyWithImpl<Baby>(this as Baby, _$identity);

  /// Serializes this Baby to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Baby&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.birthDate, birthDate) || other.birthDate == birthDate)&&(identical(other.sex, sex) || other.sex == sex)&&(identical(other.avatarPath, avatarPath) || other.avatarPath == avatarPath)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,birthDate,sex,avatarPath,createdAt,updatedAt);

@override
String toString() {
  return 'Baby(id: $id, name: $name, birthDate: $birthDate, sex: $sex, avatarPath: $avatarPath, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $BabyCopyWith<$Res>  {
  factory $BabyCopyWith(Baby value, $Res Function(Baby) _then) = _$BabyCopyWithImpl;
@useResult
$Res call({
 String id, String name, String birthDate, String? sex, String? avatarPath,@UtcDateTimeConverter() DateTime createdAt,@UtcDateTimeConverter() DateTime updatedAt
});




}
/// @nodoc
class _$BabyCopyWithImpl<$Res>
    implements $BabyCopyWith<$Res> {
  _$BabyCopyWithImpl(this._self, this._then);

  final Baby _self;
  final $Res Function(Baby) _then;

/// Create a copy of Baby
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? birthDate = null,Object? sex = freezed,Object? avatarPath = freezed,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(Baby(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,birthDate: null == birthDate ? _self.birthDate : birthDate // ignore: cast_nullable_to_non_nullable
as String,sex: freezed == sex ? _self.sex : sex // ignore: cast_nullable_to_non_nullable
as String?,avatarPath: freezed == avatarPath ? _self.avatarPath : avatarPath // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [Baby].
extension BabyPatterns on Baby {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Baby value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Baby() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Baby value)  $default,){
final _that = this;
switch (_that) {
case _Baby():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Baby value)?  $default,){
final _that = this;
switch (_that) {
case _Baby() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String birthDate,  String? sex,  String? avatarPath, @UtcDateTimeConverter()  DateTime createdAt, @UtcDateTimeConverter()  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Baby() when $default != null:
return $default(_that.id,_that.name,_that.birthDate,_that.sex,_that.avatarPath,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String birthDate,  String? sex,  String? avatarPath, @UtcDateTimeConverter()  DateTime createdAt, @UtcDateTimeConverter()  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _Baby():
return $default(_that.id,_that.name,_that.birthDate,_that.sex,_that.avatarPath,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String birthDate,  String? sex,  String? avatarPath, @UtcDateTimeConverter()  DateTime createdAt, @UtcDateTimeConverter()  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Baby() when $default != null:
return $default(_that.id,_that.name,_that.birthDate,_that.sex,_that.avatarPath,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Baby implements Baby {
  const _Baby({required this.id, required this.name, required this.birthDate, this.sex, this.avatarPath, @UtcDateTimeConverter() required this.createdAt, @UtcDateTimeConverter() required this.updatedAt});
  factory _Baby.fromJson(Map<String, dynamic> json) => _$BabyFromJson(json);

@override final  String id;
@override final  String name;
@override final  String birthDate;
@override final  String? sex;
@override final  String? avatarPath;
@override@UtcDateTimeConverter() final  DateTime createdAt;
@override@UtcDateTimeConverter() final  DateTime updatedAt;

/// Create a copy of Baby
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BabyCopyWith<_Baby> get copyWith => __$BabyCopyWithImpl<_Baby>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BabyToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Baby&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.birthDate, birthDate) || other.birthDate == birthDate)&&(identical(other.sex, sex) || other.sex == sex)&&(identical(other.avatarPath, avatarPath) || other.avatarPath == avatarPath)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,birthDate,sex,avatarPath,createdAt,updatedAt);

@override
String toString() {
  return 'Baby(id: $id, name: $name, birthDate: $birthDate, sex: $sex, avatarPath: $avatarPath, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$BabyCopyWith<$Res> implements $BabyCopyWith<$Res> {
  factory _$BabyCopyWith(_Baby value, $Res Function(_Baby) _then) = __$BabyCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String birthDate, String? sex, String? avatarPath,@UtcDateTimeConverter() DateTime createdAt,@UtcDateTimeConverter() DateTime updatedAt
});




}
/// @nodoc
class __$BabyCopyWithImpl<$Res>
    implements _$BabyCopyWith<$Res> {
  __$BabyCopyWithImpl(this._self, this._then);

  final _Baby _self;
  final $Res Function(_Baby) _then;

/// Create a copy of Baby
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? birthDate = null,Object? sex = freezed,Object? avatarPath = freezed,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_Baby(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,birthDate: null == birthDate ? _self.birthDate : birthDate // ignore: cast_nullable_to_non_nullable
as String,sex: freezed == sex ? _self.sex : sex // ignore: cast_nullable_to_non_nullable
as String?,avatarPath: freezed == avatarPath ? _self.avatarPath : avatarPath // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}


/// @nodoc
mixin _$BabyDraft {

 String get name; String get birthDate; String? get sex; String? get avatarPath;
/// Create a copy of BabyDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BabyDraftCopyWith<BabyDraft> get copyWith => _$BabyDraftCopyWithImpl<BabyDraft>(this as BabyDraft, _$identity);

  /// Serializes this BabyDraft to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BabyDraft&&(identical(other.name, name) || other.name == name)&&(identical(other.birthDate, birthDate) || other.birthDate == birthDate)&&(identical(other.sex, sex) || other.sex == sex)&&(identical(other.avatarPath, avatarPath) || other.avatarPath == avatarPath));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,birthDate,sex,avatarPath);

@override
String toString() {
  return 'BabyDraft(name: $name, birthDate: $birthDate, sex: $sex, avatarPath: $avatarPath)';
}


}

/// @nodoc
abstract mixin class $BabyDraftCopyWith<$Res>  {
  factory $BabyDraftCopyWith(BabyDraft value, $Res Function(BabyDraft) _then) = _$BabyDraftCopyWithImpl;
@useResult
$Res call({
 String name, String birthDate, String? sex, String? avatarPath
});




}
/// @nodoc
class _$BabyDraftCopyWithImpl<$Res>
    implements $BabyDraftCopyWith<$Res> {
  _$BabyDraftCopyWithImpl(this._self, this._then);

  final BabyDraft _self;
  final $Res Function(BabyDraft) _then;

/// Create a copy of BabyDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? birthDate = null,Object? sex = freezed,Object? avatarPath = freezed,}) {
  return _then(BabyDraft(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,birthDate: null == birthDate ? _self.birthDate : birthDate // ignore: cast_nullable_to_non_nullable
as String,sex: freezed == sex ? _self.sex : sex // ignore: cast_nullable_to_non_nullable
as String?,avatarPath: freezed == avatarPath ? _self.avatarPath : avatarPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BabyDraft].
extension BabyDraftPatterns on BabyDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BabyDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BabyDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BabyDraft value)  $default,){
final _that = this;
switch (_that) {
case _BabyDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BabyDraft value)?  $default,){
final _that = this;
switch (_that) {
case _BabyDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String birthDate,  String? sex,  String? avatarPath)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BabyDraft() when $default != null:
return $default(_that.name,_that.birthDate,_that.sex,_that.avatarPath);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String birthDate,  String? sex,  String? avatarPath)  $default,) {final _that = this;
switch (_that) {
case _BabyDraft():
return $default(_that.name,_that.birthDate,_that.sex,_that.avatarPath);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String birthDate,  String? sex,  String? avatarPath)?  $default,) {final _that = this;
switch (_that) {
case _BabyDraft() when $default != null:
return $default(_that.name,_that.birthDate,_that.sex,_that.avatarPath);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BabyDraft implements BabyDraft {
  const _BabyDraft({required this.name, required this.birthDate, this.sex, this.avatarPath});
  factory _BabyDraft.fromJson(Map<String, dynamic> json) => _$BabyDraftFromJson(json);

@override final  String name;
@override final  String birthDate;
@override final  String? sex;
@override final  String? avatarPath;

/// Create a copy of BabyDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BabyDraftCopyWith<_BabyDraft> get copyWith => __$BabyDraftCopyWithImpl<_BabyDraft>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BabyDraftToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BabyDraft&&(identical(other.name, name) || other.name == name)&&(identical(other.birthDate, birthDate) || other.birthDate == birthDate)&&(identical(other.sex, sex) || other.sex == sex)&&(identical(other.avatarPath, avatarPath) || other.avatarPath == avatarPath));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,birthDate,sex,avatarPath);

@override
String toString() {
  return 'BabyDraft(name: $name, birthDate: $birthDate, sex: $sex, avatarPath: $avatarPath)';
}


}

/// @nodoc
abstract mixin class _$BabyDraftCopyWith<$Res> implements $BabyDraftCopyWith<$Res> {
  factory _$BabyDraftCopyWith(_BabyDraft value, $Res Function(_BabyDraft) _then) = __$BabyDraftCopyWithImpl;
@override @useResult
$Res call({
 String name, String birthDate, String? sex, String? avatarPath
});




}
/// @nodoc
class __$BabyDraftCopyWithImpl<$Res>
    implements _$BabyDraftCopyWith<$Res> {
  __$BabyDraftCopyWithImpl(this._self, this._then);

  final _BabyDraft _self;
  final $Res Function(_BabyDraft) _then;

/// Create a copy of BabyDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? birthDate = null,Object? sex = freezed,Object? avatarPath = freezed,}) {
  return _then(_BabyDraft(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,birthDate: null == birthDate ? _self.birthDate : birthDate // ignore: cast_nullable_to_non_nullable
as String,sex: freezed == sex ? _self.sex : sex // ignore: cast_nullable_to_non_nullable
as String?,avatarPath: freezed == avatarPath ? _self.avatarPath : avatarPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
