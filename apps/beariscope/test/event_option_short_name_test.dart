import 'package:beariscope/providers/current_event_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  EventOption parse(String name) {
    return EventOption.fromJson({'key': '2025wagg', 'name': name});
  }

  test('shortens Girl\'s Generation with any apostrophe style', () {
    expect(
      parse("Washington Girl's Generation").shortName,
      "Washington Girl's Gen",
    );
    expect(
      parse('Washington Girl’s Generation').shortName,
      "Washington Girl's Gen",
    );
    expect(
      parse('Washington Girls Generation').shortName,
      "Washington Girl's Gen",
    );
  });
}
