import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:grove/grove.dart';
import 'package:source_gen/source_gen.dart';

Builder groveBuilder(BuilderOptions options) => SharedPartBuilder([
  const _GroveGenerator(),
  const _GroveValueGenerator(),
], 'grove');

class _GroveValueGenerator extends GeneratorForAnnotation<GroveValue> {
  const _GroveValueGenerator() : super(inPackage: 'grove');

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) => _generate(element);
}

class _GroveGenerator extends GeneratorForAnnotation<GroveEntity> {
  const _GroveGenerator() : super(inPackage: 'grove');

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) => _generate(element, annotation);
}

String _generate(Element element, [ConstantReader? entity]) {
  if (element is! ClassElement || element.typeParameters.isNotEmpty) {
    throw InvalidGenerationSourceError(
      'Use a Grove annotation on a non-generic model class.',
      element: element,
    );
  }
  final constructor = element.unnamedConstructor;
  if (constructor == null || constructor.isFactory) {
    throw InvalidGenerationSourceError(
      'A Grove model needs an unnamed generative constructor.',
      element: element,
    );
  }
  final name = element.name!;
  final descriptor = '${name[0].toLowerCase()}${name.substring(1)}Entity';
  final idField = entity?.read('idField').stringValue;
  final fields = element.fields.where((field) => !field.isStatic);
  final byName = {for (final field in fields) field.name: field};
  final parameters = constructor.formalParameters;
  if (idField != null &&
      (!parameters.any((parameter) => parameter.name == idField) ||
          byName[idField]?.type.getDisplayString() != 'String')) {
    throw InvalidGenerationSourceError(
      'The Grove ID must be a non-null String constructor field.',
      element: element,
    );
  }

  final codecs = StringBuffer()
    ..writeln('Json _${name}ToGroveJson($name value) => {');
  final constructorArgs = StringBuffer();
  final queryFields = StringBuffer('abstract final class ${name}Fields {\n');
  for (final parameter in parameters) {
    final field = byName[parameter.name];
    if (field == null || field.isPrivate || !field.isFinal) {
      throw InvalidGenerationSourceError(
        'Each Grove constructor parameter must have a public final field.',
        element: parameter,
      );
    }
    final fieldName = field.name!;
    final key = jsonEncode(fieldName == idField ? 'id' : fieldName);
    final type = field.type;
    try {
      final encoded = _encode(type, 'value.$fieldName');
      codecs.writeln('$key: $encoded,');
      final prefix = parameter.isNamed ? '$fieldName: ' : '';
      constructorArgs.writeln('$prefix${_decode(type, 'json[$key]')},');
      if (entity != null &&
          (_isScalar(type) || _typeName(type) == 'EntityRef')) {
        queryFields.writeln(
          'static const $fieldName = EntityField<$name, '
          '${type.getDisplayString()}>($key);',
        );
      }
    } on UnsupportedError catch (error) {
      throw InvalidGenerationSourceError(
        error.message ?? 'Unsupported Grove field',
        element: field,
      );
    }
  }
  codecs
    ..writeln('};')
    ..writeln('$name _${name}FromGroveJson(Json json) => $name(')
    ..write(constructorArgs)
    ..writeln(');');

  if (entity == null) return codecs.toString();
  final staticFields = element.fields.where((field) => field.isStatic);
  return '''
$codecs
final $descriptor = EntityDescriptor<$name>(
  type: ${jsonEncode(entity.read('type').stringValue)},
  version: ${entity.read('version').intValue},
  offlineMutable: ${entity.read('offlineMutable').boolValue},
  ${entity.read('serverManaged').boolValue ? 'serverManaged: true,' : ''}
  encode: _${name}ToGroveJson,
  decode: _${name}FromGroveJson,
  ${staticFields.any((field) => field.name == 'groveMigrations') ? 'migrations: $name.groveMigrations,' : ''}
  ${staticFields.any((field) => field.name == 'groveFieldVersions') ? 'fieldVersions: $name.groveFieldVersions,' : ''}
);
$queryFields
}
'''
      .trim();
}

bool _isValue(InterfaceType type) =>
    const TypeChecker.typeNamed(
      GroveValue,
      inPackage: 'grove',
    ).hasAnnotationOfExact(type.element) ||
    const TypeChecker.typeNamed(
      GroveEntity,
      inPackage: 'grove',
    ).hasAnnotationOfExact(type.element);

String? _typeName(DartType type) =>
    type is InterfaceType ? type.element.name : null;

bool _isScalar(DartType type) =>
    const {'String', 'bool', 'int', 'double', 'num'}.contains(_typeName(type));

bool _isNullable(DartType type) =>
    type.nullabilitySuffix == NullabilitySuffix.question;

String _encode(DartType type, String value) {
  if (_isScalar(type) || type is DynamicType) return value;
  if (type is! InterfaceType) return _unsupported(type);
  final encoded = _encodeNonNull(type, _isNullable(type) ? '$value!' : value);
  return _isNullable(type) ? '$value == null ? null : $encoded' : encoded;
}

String _encodeNonNull(InterfaceType type, String value) {
  final args = type.typeArguments;
  return switch (_typeName(type)) {
    'DateTime' => '$value.toUtc().toIso8601String()',
    'EntityRef' => '$value.id',
    'List' => '$value.map((item) => ${_encode(args.single, 'item')}).toList()',
    'Set' when _typeName(args.single) == 'String' =>
      '($value.toList()..sort())',
    'Map' when _typeName(args.first) == 'String' =>
      '$value.map((key, item) => MapEntry(key, ${_encode(args.last, 'item')}))',
    final name when _isValue(type) => '_${name}ToGroveJson($value)',
    _ => _unsupported(type),
  };
}

String _decode(DartType type, String value) {
  if (type is DynamicType) return value;
  final text = type.getDisplayString();
  if (_isScalar(type)) {
    if (_typeName(type) == 'double') {
      return _isNullable(type)
          ? '($value as num?)?.toDouble()'
          : '($value as num).toDouble()';
    }
    return '$value as $text';
  }
  if (type is! InterfaceType) return _unsupported(type);
  final args = type.typeArguments;
  final decoded = switch (_typeName(type)) {
    'DateTime' => 'DateTime.parse($value as String)',
    'EntityRef' => '${text.replaceFirst(RegExp(r'\?$'), '')}($value as String)',
    'List' =>
      '($value as List).map((item) => ${_decode(args.single, 'item')}).toList()',
    'Set' when _typeName(args.single) == 'String' =>
      '($value as List).cast<String>().toSet()',
    'Map' when _typeName(args.first) == 'String' =>
      '($value as Map).map((key, item) => MapEntry(key as String, ${_decode(args.last, 'item')}))',
    final name when _isValue(type) => '_${name}FromGroveJson($value as Json)',
    _ => _unsupported(type),
  };
  return _isNullable(type) ? '$value == null ? null : $decoded' : decoded;
}

Never _unsupported(DartType type) => throw UnsupportedError(
  'Unsupported Grove field type ${type.getDisplayString()}',
);
