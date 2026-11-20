import 'package:grove/grove.dart';
import 'package:uuid/uuid.dart';

part 'scout.g.dart';

@GroveEntity('scouting.scout', version: 1, idField: 'uuid')
class Scout {
  Scout({required this.name, required this.uuid}) {
    if (uuid.isEmpty || name.trim().isEmpty) {
      throw ArgumentError('Scout ID and name are required');
    }
  }

  final String name;
  final String uuid;

  factory Scout.create(String name) =>
      Scout(name: name.trim(), uuid: const Uuid().v4());

  factory Scout.fromJson(Map<String, dynamic> json) {
    return Scout(
      name: json['name']?.toString() ?? '',
      uuid: json['uuid']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'uuid': uuid};
  }
}
